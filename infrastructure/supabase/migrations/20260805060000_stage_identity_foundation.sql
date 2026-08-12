-- Architecture Hardening Step 2: Stage identity foundation
-- - Designate exactly one Applied entry stage per template/job (not sort_order/intake)
-- - applications.current_job_stage_id becomes sole pipeline-stage source of truth
-- - Drop applications.current_stage after verified backfill
-- - Append-only application_stage_events with immutable snapshots + job_id
-- - Atomic transition_application_stage RPC; block lifecycle-terminal destinations
-- - Lifecycle status is never derived from stage names/keys

-- ---------------------------------------------------------------------------
-- 1) Applied entry stage designation (templates + job snapshots)
-- ---------------------------------------------------------------------------
alter table public.pipeline_template_stages
  add column if not exists is_applied_entry boolean not null default false;

alter table public.job_stages
  add column if not exists is_applied_entry boolean not null default false;

alter table public.pipeline_template_stages
  drop constraint if exists pipeline_template_stages_applied_entry_category_check;

alter table public.pipeline_template_stages
  add constraint pipeline_template_stages_applied_entry_category_check
  check (not is_applied_entry or category not in ('hired', 'closed'));

alter table public.job_stages
  drop constraint if exists job_stages_applied_entry_category_check;

alter table public.job_stages
  add constraint job_stages_applied_entry_category_check
  check (not is_applied_entry or category not in ('hired', 'closed'));

-- Backfill: system Applied stage is identified by stable key 'applied'
update public.pipeline_template_stages
set is_applied_entry = true
where key = 'applied'
  and is_applied_entry = false;

update public.job_stages
set is_applied_entry = true
where key = 'applied'
  and is_applied_entry = false;

do $$
declare
  v_bad_templates int;
  v_bad_jobs int;
begin
  select count(*) into v_bad_templates
  from (
    select pts.template_id
    from public.pipeline_template_stages pts
    group by pts.template_id
    having count(*) filter (where pts.is_applied_entry) <> 1
  ) t;

  if v_bad_templates > 0 then
    raise exception
      'Step 2 backfill failed: % pipeline template(s) do not have exactly one is_applied_entry stage',
      v_bad_templates;
  end if;

  select count(*) into v_bad_jobs
  from (
    select js.job_id
    from public.job_stages js
    group by js.job_id
    having count(*) filter (where js.is_applied_entry) <> 1
  ) j;

  if v_bad_jobs > 0 then
    raise exception
      'Step 2 backfill failed: % job(s) do not have exactly one is_applied_entry stage',
      v_bad_jobs;
  end if;
end;
$$;

create unique index if not exists pipeline_template_stages_one_applied_entry_uidx
  on public.pipeline_template_stages (template_id)
  where is_applied_entry;

create unique index if not exists job_stages_one_applied_entry_uidx
  on public.job_stages (job_id)
  where is_applied_entry;

comment on column public.pipeline_template_stages.is_applied_entry is
  'Exactly one stage per template is the system Applied entry stage for new applications.';

comment on column public.job_stages.is_applied_entry is
  'Exactly one stage per job is the system Applied entry stage for new applications.';

-- Composite FK target for applications.current_job_stage_id
alter table public.job_stages
  drop constraint if exists job_stages_id_job_id_key;

alter table public.job_stages
  add constraint job_stages_id_job_id_key unique (id, job_id);

-- ---------------------------------------------------------------------------
-- 2) Replace seed / duplicate / sync / publish to preserve Applied entry
-- ---------------------------------------------------------------------------
create or replace function public.seed_default_pipeline_template(
  p_tenant_id uuid,
  p_created_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template_id uuid;
begin
  if exists (
    select 1
    from public.pipeline_templates
    where tenant_id = p_tenant_id
      and is_default = true
      and archived_at is null
  ) then
    select id into v_template_id
    from public.pipeline_templates
    where tenant_id = p_tenant_id
      and is_default = true
      and archived_at is null
    limit 1;
    return v_template_id;
  end if;

  insert into public.pipeline_templates (
    tenant_id, name, description, is_default, created_by
  )
  values (
    p_tenant_id,
    'Default hiring pipeline',
    'Standard HireFlow stages from applied through hired, plus closed outcomes.',
    true,
    p_created_by
  )
  returning id into v_template_id;

  insert into public.pipeline_template_stages (
    tenant_id, template_id, key, name, sort_order, color, sla_days, category, notes, is_applied_entry
  )
  values
    (p_tenant_id, v_template_id, 'applied', 'Applied', 1, '#64748B', 2, 'intake', 'New applications land here.', true),
    (p_tenant_id, v_template_id, 'cv_screening', 'CV Screening', 2, '#0EA5E9', 3, 'screening', null, false),
    (p_tenant_id, v_template_id, 'phone_screening', 'Phone Screening', 3, '#06B6D4', 3, 'screening', null, false),
    (p_tenant_id, v_template_id, 'interview', 'Interview', 4, '#8B5CF6', 7, 'interview', null, false),
    (p_tenant_id, v_template_id, 'reference_check', 'Reference Check', 5, '#F59E0B', 5, 'reference', null, false),
    (p_tenant_id, v_template_id, 'offer', 'Offer', 6, '#10B981', 5, 'offer', null, false),
    (p_tenant_id, v_template_id, 'pre_hire', 'Pre-Hire', 7, '#14B8A6', 7, 'pre_hire', 'Documents and signatures.', false),
    (p_tenant_id, v_template_id, 'hired', 'Hired', 8, '#0F6B4C', null, 'hired', 'Terminal success.', false),
    (p_tenant_id, v_template_id, 'rejected', 'Rejected', 9, '#DC2626', null, 'closed', 'Terminal closed.', false),
    (p_tenant_id, v_template_id, 'withdrawn', 'Withdrawn', 10, '#78716C', null, 'closed', 'Candidate withdrew.', false);

  return v_template_id;
end;
$$;

create or replace function public.duplicate_pipeline_template(
  p_tenant_id uuid,
  p_template_id uuid,
  p_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.pipeline_templates;
  v_new_id uuid;
  v_name text;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select * into v_source
  from public.pipeline_templates
  where id = p_template_id
    and tenant_id = p_tenant_id;

  if v_source.id is null then
    raise exception 'Template not found';
  end if;

  v_name := coalesce(nullif(trim(p_name), ''), v_source.name || ' (Copy)');

  insert into public.pipeline_templates (
    tenant_id, name, description, is_default, created_by
  )
  values (
    p_tenant_id,
    v_name,
    v_source.description,
    false,
    auth.uid()
  )
  returning id into v_new_id;

  insert into public.pipeline_template_stages (
    tenant_id, template_id, key, name, sort_order, color, sla_days, category, notes, is_applied_entry
  )
  select
    p_tenant_id,
    v_new_id,
    key,
    name,
    sort_order,
    color,
    sla_days,
    category,
    notes,
    is_applied_entry
  from public.pipeline_template_stages
  where template_id = p_template_id
  order by sort_order;

  return v_new_id;
end;
$$;

create or replace function public.sync_job_stages_from_template(
  p_tenant_id uuid,
  p_job_id uuid,
  p_template_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.jobs
    where id = p_job_id
      and tenant_id = p_tenant_id
  ) then
    raise exception 'Job not found';
  end if;

  if not exists (
    select 1
    from public.pipeline_templates
    where id = p_template_id
      and tenant_id = p_tenant_id
      and archived_at is null
  ) then
    raise exception 'Pipeline template not found or archived';
  end if;

  if not exists (
    select 1
    from public.pipeline_template_stages
    where template_id = p_template_id
      and tenant_id = p_tenant_id
  ) then
    raise exception 'Pipeline template has no stages';
  end if;

  if (
    select count(*) filter (where is_applied_entry)
    from public.pipeline_template_stages
    where template_id = p_template_id
      and tenant_id = p_tenant_id
  ) <> 1 then
    raise exception 'Pipeline template must designate exactly one Applied entry stage';
  end if;

  delete from public.job_stages
  where job_id = p_job_id
    and tenant_id = p_tenant_id;

  insert into public.job_stages (
    tenant_id, job_id, key, name, sort_order, color, sla_days, category, notes, is_applied_entry
  )
  select
    p_tenant_id,
    p_job_id,
    key,
    name,
    sort_order,
    color,
    sla_days,
    category,
    notes,
    is_applied_entry
  from public.pipeline_template_stages
  where template_id = p_template_id
    and tenant_id = p_tenant_id
  order by sort_order;

  update public.jobs
  set pipeline_template_id = p_template_id,
      updated_at = now()
  where id = p_job_id
    and tenant_id = p_tenant_id;
end;
$$;

create or replace function public.publish_job(
  p_tenant_id uuid,
  p_job_id uuid
)
returns public.jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.jobs;
  v_token text;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select * into v_job
  from public.jobs
  where id = p_job_id
    and tenant_id = p_tenant_id
  for update;

  if v_job.id is null then
    raise exception 'Job not found';
  end if;

  if v_job.archived_at is not null then
    raise exception 'Archived jobs cannot be published';
  end if;

  if v_job.title is null or length(trim(v_job.title)) = 0 then
    raise exception 'Job title is required before publish';
  end if;

  if v_job.description is null or length(trim(v_job.description)) = 0 then
    raise exception 'Job description is required before publish';
  end if;

  if v_job.pipeline_template_id is null then
    raise exception 'Select a pipeline template before publish';
  end if;

  if not exists (
    select 1 from public.job_stages
    where job_id = p_job_id and tenant_id = p_tenant_id
  ) then
    raise exception 'Job has no pipeline stages';
  end if;

  if (
    select count(*) filter (where is_applied_entry)
    from public.job_stages
    where job_id = p_job_id
      and tenant_id = p_tenant_id
  ) <> 1 then
    raise exception 'Job must designate exactly one Applied entry stage before publish';
  end if;

  v_token := coalesce(
    v_job.public_apply_token,
    replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
  );

  update public.jobs
  set status = 'open',
      apply_enabled = true,
      public_apply_token = v_token,
      published_at = coalesce(published_at, now()),
      updated_at = now()
  where id = p_job_id
    and tenant_id = p_tenant_id
  returning * into v_job;

  insert into public.audit_events (
    tenant_id, actor_user_id, action, entity_type, entity_id
  )
  values (
    p_tenant_id, auth.uid(), 'job.published', 'job', p_job_id
  );

  return v_job;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) applications.current_job_stage_id
-- ---------------------------------------------------------------------------
alter table public.applications
  add column if not exists current_job_stage_id uuid;

alter table public.applications
  drop constraint if exists applications_current_job_stage_job_fk;

alter table public.applications
  add constraint applications_current_job_stage_job_fk
  foreign key (current_job_stage_id, job_id)
  references public.job_stages (id, job_id)
  on delete restrict;

-- ---------------------------------------------------------------------------
-- 4) application_stage_events: job scope, snapshots, event_type, metadata
-- ---------------------------------------------------------------------------
alter table public.application_stage_events
  add column if not exists job_id uuid;

alter table public.application_stage_events
  add column if not exists event_type text;

alter table public.application_stage_events
  add column if not exists from_job_stage_id uuid;

alter table public.application_stage_events
  add column if not exists to_job_stage_id uuid;

alter table public.application_stage_events
  add column if not exists from_stage_key text;

alter table public.application_stage_events
  add column if not exists from_stage_name text;

alter table public.application_stage_events
  add column if not exists from_stage_category text;

alter table public.application_stage_events
  add column if not exists to_stage_key text;

alter table public.application_stage_events
  add column if not exists to_stage_name text;

alter table public.application_stage_events
  add column if not exists to_stage_category text;

alter table public.application_stage_events
  add column if not exists metadata jsonb not null default '{}'::jsonb;

-- Backfill job_id from application for any pre-existing events
update public.application_stage_events e
set job_id = a.job_id
from public.applications a
where e.application_id = a.id
  and e.job_id is null;

-- Convert legacy text events into snapshot columns when present
update public.application_stage_events e
set
  event_type = coalesce(e.event_type, 'migration_backfill'),
  to_stage_key = coalesce(e.to_stage_key, e.to_stage),
  to_stage_name = coalesce(e.to_stage_name, e.to_stage),
  to_stage_category = coalesce(e.to_stage_category, 'custom'),
  from_stage_key = coalesce(e.from_stage_key, e.from_stage),
  from_stage_name = coalesce(e.from_stage_name, e.from_stage),
  metadata = e.metadata || jsonb_build_object(
    'legacy_text_event', true,
    'migration_note', 'Snapshot reconstructed from legacy text stage columns'
  )
where e.to_stage_key is null
  and e.to_stage is not null;

do $$
begin
  if exists (
    select 1
    from public.application_stage_events
    where job_id is null
       or to_stage_key is null
       or to_stage_name is null
       or to_stage_category is null
       or event_type is null
  ) then
    raise exception
      'Step 2 event backfill failed: residual application_stage_events lack required snapshot/job fields';
  end if;
end;
$$;

alter table public.application_stage_events
  alter column job_id set not null;

alter table public.application_stage_events
  alter column event_type set not null;

alter table public.application_stage_events
  alter column to_stage_key set not null;

alter table public.application_stage_events
  alter column to_stage_name set not null;

alter table public.application_stage_events
  alter column to_stage_category set not null;

alter table public.application_stage_events
  drop constraint if exists application_stage_events_event_type_check;

alter table public.application_stage_events
  add constraint application_stage_events_event_type_check
  check (event_type in ('initial', 'transition', 'migration_backfill'));

alter table public.application_stage_events
  drop constraint if exists application_stage_events_job_id_fkey;

alter table public.application_stage_events
  add constraint application_stage_events_job_tenant_fk
  foreign key (job_id, tenant_id)
  references public.jobs (id, tenant_id);

alter table public.application_stage_events
  drop constraint if exists application_stage_events_from_stage_job_fk;

alter table public.application_stage_events
  add constraint application_stage_events_from_stage_job_fk
  foreign key (from_job_stage_id, job_id)
  references public.job_stages (id, job_id)
  on delete set null;

alter table public.application_stage_events
  drop constraint if exists application_stage_events_to_stage_job_fk;

alter table public.application_stage_events
  add constraint application_stage_events_to_stage_job_fk
  foreign key (to_job_stage_id, job_id)
  references public.job_stages (id, job_id)
  on delete set null;

-- Drop legacy text stage columns after snapshot backfill
alter table public.application_stage_events
  drop column if exists from_stage;

alter table public.application_stage_events
  drop column if exists to_stage;

-- ---------------------------------------------------------------------------
-- 5) Backfill applications.current_job_stage_id from legacy current_stage
-- ---------------------------------------------------------------------------
update public.applications a
set current_job_stage_id = js.id
from public.job_stages js
where a.current_job_stage_id is null
  and js.job_id = a.job_id
  and js.tenant_id = a.tenant_id
  and js.key = a.current_stage;

do $$
declare
  v_unmatched int;
  v_backfill_at timestamptz := clock_timestamp();
begin
  select count(*) into v_unmatched
  from public.applications
  where current_job_stage_id is null;

  if v_unmatched > 0 then
    raise exception
      'Step 2 application backfill failed: % application(s) could not map current_stage to job_stages.key',
      v_unmatched;
  end if;

  -- History Never Lies: migration_backfill occurred_at is the backfill time,
  -- not applications.created_at. Preserve created_at only in metadata.
  insert into public.application_stage_events (
    tenant_id,
    application_id,
    job_id,
    event_type,
    from_job_stage_id,
    to_job_stage_id,
    from_stage_key,
    from_stage_name,
    from_stage_category,
    to_stage_key,
    to_stage_name,
    to_stage_category,
    actor_user_id,
    note,
    reason_code,
    occurred_at,
    metadata
  )
  select
    a.tenant_id,
    a.id,
    a.job_id,
    'migration_backfill',
    null,
    a.current_job_stage_id,
    null,
    null,
    null,
    js.key,
    js.name,
    js.category,
    null,
    'Migration snapshot of current pipeline stage',
    'migration_snapshot',
    v_backfill_at,
    jsonb_build_object(
      'application_created_at', a.created_at,
      'legacy_current_stage', a.current_stage
    )
  from public.applications a
  join public.job_stages js
    on js.id = a.current_job_stage_id
  where not exists (
    select 1
    from public.application_stage_events e
    where e.application_id = a.id
  );
end;
$$;

alter table public.applications
  alter column current_job_stage_id set not null;

drop index if exists public.applications_board_idx;

alter table public.applications
  drop column if exists current_stage;

create index applications_board_idx
  on public.applications (tenant_id, job_id, current_job_stage_id);

comment on column public.applications.current_job_stage_id is
  'Current pipeline stage (job_stages). Source of truth for pipeline position. Independent from lifecycle status.';

-- ---------------------------------------------------------------------------
-- 6) Helpers, guards, append-only, create/transition RPCs
-- ---------------------------------------------------------------------------
create or replace function public.job_applied_entry_stage(p_job_id uuid)
returns public.job_stages
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_stage public.job_stages;
begin
  select * into v_stage
  from public.job_stages
  where job_id = p_job_id
    and is_applied_entry = true;

  if v_stage.id is null then
    raise exception 'Job % has no Applied entry stage', p_job_id;
  end if;

  return v_stage;
end;
$$;

create or replace function public.applications_enforce_applied_entry_on_insert()
returns trigger
language plpgsql
as $$
declare
  v_entry public.job_stages;
begin
  v_entry := public.job_applied_entry_stage(new.job_id);

  if new.current_job_stage_id is null then
    new.current_job_stage_id := v_entry.id;
  elsif new.current_job_stage_id is distinct from v_entry.id
    and coalesce(current_setting('hireflow.allow_non_applied_insert', true), '') is distinct from '1'
  then
    raise exception
      'Applications must be created in the job Applied entry stage';
  end if;

  return new;
end;
$$;

drop trigger if exists applications_enforce_applied_entry_on_insert on public.applications;

create trigger applications_enforce_applied_entry_on_insert
  before insert on public.applications
  for each row
  execute function public.applications_enforce_applied_entry_on_insert();

create or replace function public.applications_write_initial_stage_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stage public.job_stages;
begin
  if coalesce(current_setting('hireflow.skip_initial_stage_event', true), '') = '1' then
    return new;
  end if;

  select * into v_stage
  from public.job_stages
  where id = new.current_job_stage_id;

  insert into public.application_stage_events (
    tenant_id,
    application_id,
    job_id,
    event_type,
    from_job_stage_id,
    to_job_stage_id,
    from_stage_key,
    from_stage_name,
    from_stage_category,
    to_stage_key,
    to_stage_name,
    to_stage_category,
    actor_user_id,
    occurred_at,
    metadata
  )
  values (
    new.tenant_id,
    new.id,
    new.job_id,
    'initial',
    null,
    v_stage.id,
    null,
    null,
    null,
    v_stage.key,
    v_stage.name,
    v_stage.category,
    new.created_by,
    now(),
    '{}'::jsonb
  );

  return new;
end;
$$;

drop trigger if exists applications_write_initial_stage_event on public.applications;

create trigger applications_write_initial_stage_event
  after insert on public.applications
  for each row
  execute function public.applications_write_initial_stage_event();

create or replace function public.applications_guard_stage_id_update()
returns trigger
language plpgsql
as $$
begin
  if new.current_job_stage_id is distinct from old.current_job_stage_id
    and coalesce(current_setting('hireflow.stage_transition', true), '') is distinct from '1'
  then
    raise exception
      'applications.current_job_stage_id can only change via transition_application_stage';
  end if;

  return new;
end;
$$;

drop trigger if exists applications_guard_stage_id_update on public.applications;

create trigger applications_guard_stage_id_update
  before update on public.applications
  for each row
  execute function public.applications_guard_stage_id_update();

create or replace function public.application_stage_events_append_only()
returns trigger
language plpgsql
as $$
begin
  -- Break-glass for controlled maintenance/tests only.
  if coalesce(current_setting('hireflow.allow_event_maintenance', true), '') = '1' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  raise exception 'application_stage_events is append-only';
end;
$$;

drop trigger if exists application_stage_events_append_only_upd on public.application_stage_events;
drop trigger if exists application_stage_events_append_only_del on public.application_stage_events;

create trigger application_stage_events_append_only_upd
  before update on public.application_stage_events
  for each row
  execute function public.application_stage_events_append_only();

create trigger application_stage_events_append_only_del
  before delete on public.application_stage_events
  for each row
  execute function public.application_stage_events_append_only();

create or replace function public.transition_application_stage(
  p_tenant_id uuid,
  p_application_id uuid,
  p_to_job_stage_id uuid,
  p_note text default null,
  p_reason_code text default null
)
returns public.applications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_from public.job_stages;
  v_to public.job_stages;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select * into v_app
  from public.applications
  where id = p_application_id
    and tenant_id = p_tenant_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;

  if v_app.status is distinct from 'active' then
    raise exception 'Only active applications can change pipeline stage';
  end if;

  select * into v_from
  from public.job_stages
  where id = v_app.current_job_stage_id;

  select * into v_to
  from public.job_stages
  where id = p_to_job_stage_id
    and job_id = v_app.job_id
    and tenant_id = p_tenant_id;

  if v_to.id is null then
    raise exception 'Destination stage not found on this job';
  end if;

  if v_to.id = v_app.current_job_stage_id then
    raise exception 'Application is already in that stage';
  end if;

  -- Terminal lifecycle outcomes require dedicated workflows (later steps).
  if v_to.category in ('hired', 'closed')
    or v_to.key in ('hired', 'rejected', 'withdrawn', 'disqualified')
  then
    raise exception
      'Cannot transition into lifecycle-terminal stage via transition_application_stage; use the dedicated lifecycle workflow';
  end if;

  insert into public.application_stage_events (
    tenant_id,
    application_id,
    job_id,
    event_type,
    from_job_stage_id,
    to_job_stage_id,
    from_stage_key,
    from_stage_name,
    from_stage_category,
    to_stage_key,
    to_stage_name,
    to_stage_category,
    actor_user_id,
    note,
    reason_code,
    occurred_at,
    metadata
  )
  values (
    p_tenant_id,
    v_app.id,
    v_app.job_id,
    'transition',
    v_from.id,
    v_to.id,
    v_from.key,
    v_from.name,
    v_from.category,
    v_to.key,
    v_to.name,
    v_to.category,
    auth.uid(),
    nullif(trim(p_note), ''),
    nullif(trim(p_reason_code), ''),
    now(),
    '{}'::jsonb
  );

  perform set_config('hireflow.stage_transition', '1', true);

  update public.applications
  set current_job_stage_id = v_to.id,
      updated_at = now()
  where id = v_app.id
    and tenant_id = p_tenant_id
  returning * into v_app;

  -- Clear so later statements in the same transaction cannot bypass the guard.
  perform set_config('hireflow.stage_transition', '', true);

  return v_app;
end;
$$;

grant execute on function public.job_applied_entry_stage(uuid)
  to authenticated, service_role;
grant execute on function public.transition_application_stage(uuid, uuid, uuid, text, text)
  to authenticated, service_role;
