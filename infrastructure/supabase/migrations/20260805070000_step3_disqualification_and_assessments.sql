-- Architecture Hardening Step 3:
-- - Disqualification categories + append-only DQ facts + disqualify_application RPC
-- - Move Stage forward-skip warning/acknowledgement (sort_order = progression order)
-- - Job Workspace index (tenant_id, job_id, status, current_job_stage_id)
-- - Interview Assessment template versioning + draft/finalize (app-owned)
-- History Never Lies: finalized answers snapshot field key/label/type/config.
-- Not in scope: Hired/Withdrawn workflows, Move/Add job, UI, capabilities, retention.

-- ---------------------------------------------------------------------------
-- Document sort_order semantics (progression + MVP display order)
-- ---------------------------------------------------------------------------
comment on column public.job_stages.sort_order is
  'Normal pipeline progression order for this job (also MVP display order). Forward Move Stage skips are intermediates with sort_order strictly between from and to. Backward moves are not skips. Not a visual-only order.';

comment on column public.pipeline_template_stages.sort_order is
  'Normal pipeline progression order for the template (also MVP display order). Copied to job_stages on sync.';

-- ---------------------------------------------------------------------------
-- 1) Disqualification categories + facts
-- ---------------------------------------------------------------------------
create table public.disqualification_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  key text not null,
  label text not null,
  sort_order int not null check (sort_order >= 1),
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, key),
  unique (id, tenant_id),
  check (length(trim(key)) > 0),
  check (length(trim(label)) > 0)
);

create index disqualification_categories_tenant_idx
  on public.disqualification_categories (tenant_id, is_active, sort_order);

create trigger disqualification_categories_set_updated_at
  before update on public.disqualification_categories
  for each row execute function public.set_updated_at();

create table public.application_disqualifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  job_id uuid not null,
  category_id uuid not null,
  detailed_reason text not null,
  actor_user_id uuid not null references public.users (id),
  occurred_at timestamptz not null default now(),
  from_job_stage_id uuid,
  from_stage_key text not null,
  from_stage_name text not null,
  from_stage_category text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id),
  foreign key (job_id, tenant_id)
    references public.jobs (id, tenant_id),
  foreign key (category_id, tenant_id)
    references public.disqualification_categories (id, tenant_id)
    on delete restrict,
  foreign key (from_job_stage_id, job_id)
    references public.job_stages (id, job_id)
    on delete set null,
  check (length(trim(detailed_reason)) > 0)
);

create index application_disqualifications_app_idx
  on public.application_disqualifications (application_id, occurred_at desc);

create index application_disqualifications_tenant_idx
  on public.application_disqualifications (tenant_id, occurred_at desc);

create or replace function public.application_disqualifications_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'application_disqualifications is append-only';
end;
$$;

create trigger application_disqualifications_append_only_upd
  before update on public.application_disqualifications
  for each row execute function public.application_disqualifications_append_only();

create trigger application_disqualifications_append_only_del
  before delete on public.application_disqualifications
  for each row execute function public.application_disqualifications_append_only();

comment on table public.application_disqualifications is
  'Authoritative append-only disqualification history. applications.reject_reason_code is a non-authoritative compatibility mirror only. Lifecycle outcome is applications.status=disqualified; current_job_stage_id remains last pipeline stage reached (not a Disqualified stage).';

-- RLS
alter table public.disqualification_categories enable row level security;
alter table public.application_disqualifications enable row level security;

create policy disqualification_categories_select on public.disqualification_categories
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy disqualification_categories_write on public.disqualification_categories
  for all to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  )
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy application_disqualifications_select on public.application_disqualifications
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy application_disqualifications_insert on public.application_disqualifications
  for insert to authenticated
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

grant select, insert, update, delete on public.disqualification_categories to authenticated;
grant select, insert on public.application_disqualifications to authenticated;
grant all on public.disqualification_categories to service_role;
grant all on public.application_disqualifications to service_role;

create or replace function public.seed_disqualification_categories(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.disqualification_categories (
    tenant_id, key, label, sort_order, is_active
  )
  values
    (p_tenant_id, 'skills_mismatch', 'Skills mismatch', 1, true),
    (p_tenant_id, 'experience', 'Insufficient experience', 2, true),
    (p_tenant_id, 'compensation', 'Compensation expectations', 3, true),
    (p_tenant_id, 'location', 'Location / remote constraints', 4, true),
    (p_tenant_id, 'timeline', 'Availability / timeline', 5, true),
    (p_tenant_id, 'culture_fit', 'Culture / team fit', 6, true),
    (p_tenant_id, 'other', 'Other', 7, true)
  on conflict (tenant_id, key) do nothing;
end;
$$;

grant execute on function public.seed_disqualification_categories(uuid)
  to authenticated, service_role;

-- Provisioning hook
create or replace function public.create_tenant(
  p_name text,
  p_slug text,
  p_owner_user_id uuid,
  p_timezone text default 'UTC',
  p_locale text default 'en-US'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  insert into public.tenants (name, slug, timezone, locale, status)
  values (p_name, p_slug, p_timezone, p_locale, 'active')
  returning id into v_tenant_id;

  perform public.seed_default_pipeline_stages(v_tenant_id);
  perform public.seed_default_pipeline_template(v_tenant_id, p_owner_user_id);
  perform public.seed_disqualification_categories(v_tenant_id);

  insert into public.tenant_memberships (tenant_id, user_id, role, status)
  values (v_tenant_id, p_owner_user_id, 'tenant_owner', 'active');

  insert into public.audit_events (tenant_id, actor_user_id, action, entity_type, entity_id)
  values (v_tenant_id, p_owner_user_id, 'tenant.created', 'tenant', v_tenant_id);

  return v_tenant_id;
end;
$$;

-- Backfill categories for any existing tenants (none expected pre-prod)
do $$
declare
  r record;
begin
  for r in select id as tenant_id from public.tenants
  loop
    perform public.seed_disqualification_categories(r.tenant_id);
  end loop;
end;
$$;

create or replace function public.disqualify_application(
  p_tenant_id uuid,
  p_application_id uuid,
  p_category_id uuid,
  p_detailed_reason text
)
returns public.applications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_stage public.job_stages;
  v_category public.disqualification_categories;
  v_actor uuid := auth.uid();
  v_reason text := trim(coalesce(p_detailed_reason, ''));
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  if length(v_reason) = 0 then
    raise exception 'Detailed disqualification reason is required';
  end if;

  select * into v_category
  from public.disqualification_categories
  where id = p_category_id
    and tenant_id = p_tenant_id
    and is_active = true
    and archived_at is null;

  if v_category.id is null then
    raise exception 'Disqualification category not found or inactive';
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
    raise exception 'Only active applications can be disqualified';
  end if;

  select * into v_stage
  from public.job_stages
  where id = v_app.current_job_stage_id;

  insert into public.application_disqualifications (
    tenant_id,
    application_id,
    job_id,
    category_id,
    detailed_reason,
    actor_user_id,
    occurred_at,
    from_job_stage_id,
    from_stage_key,
    from_stage_name,
    from_stage_category,
    metadata
  )
  values (
    p_tenant_id,
    v_app.id,
    v_app.job_id,
    v_category.id,
    v_reason,
    v_actor,
    now(),
    v_stage.id,
    v_stage.key,
    v_stage.name,
    v_stage.category,
    '{}'::jsonb
  );

  -- Leave current_job_stage_id unchanged (last pipeline stage reached).
  -- application_disqualifications is authoritative; reject_reason_code is
  -- a compatibility mirror of category.key only (not source of truth).
  update public.applications
  set status = 'disqualified',
      rejected_at = now(),
      reject_reason_code = v_category.key,
      updated_at = now()
  where id = v_app.id
    and tenant_id = p_tenant_id
  returning * into v_app;

  return v_app;
end;
$$;

comment on column public.applications.reject_reason_code is
  'Compatibility mirror only (e.g. disqualification category key). Authoritative disqualification history is application_disqualifications.';


-- ---------------------------------------------------------------------------
-- 2) Move Stage: forward-skip acknowledgement
-- ---------------------------------------------------------------------------
drop function if exists public.transition_application_stage(uuid, uuid, uuid, text, text);

create or replace function public.transition_application_stage(
  p_tenant_id uuid,
  p_application_id uuid,
  p_to_job_stage_id uuid,
  p_note text default null,
  p_reason_code text default null,
  p_acknowledge_skip boolean default false
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
  v_skipped jsonb := '[]'::jsonb;
  v_meta jsonb := '{}'::jsonb;
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

  -- Hired/Disqualified/Withdrawn are lifecycle workflows — not Move Stage.
  if v_to.category in ('hired', 'closed')
    or v_to.key in ('hired', 'rejected', 'withdrawn', 'disqualified')
  then
    raise exception
      'Cannot transition into lifecycle-terminal stage via transition_application_stage; use the dedicated lifecycle workflow';
  end if;

  -- Forward skip only: intermediates by progression sort_order (exclusive).
  -- Backward movement is allowed without skip acknowledgement.
  if v_to.sort_order > v_from.sort_order then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'key', s.key,
          'name', s.name,
          'sort_order', s.sort_order
        )
        order by s.sort_order
      ),
      '[]'::jsonb
    )
    into v_skipped
    from public.job_stages s
    where s.job_id = v_app.job_id
      and s.tenant_id = p_tenant_id
      and s.sort_order > v_from.sort_order
      and s.sort_order < v_to.sort_order
      and s.category not in ('hired', 'closed')
      and s.key not in ('hired', 'rejected', 'withdrawn', 'disqualified');

    if jsonb_array_length(v_skipped) > 0
      and coalesce(p_acknowledge_skip, false) is not true
    then
      raise exception
        'Forward stage skip acknowledgement required: %',
        v_skipped::text;
    end if;

    if jsonb_array_length(v_skipped) > 0 then
      v_meta := jsonb_build_object(
        'skipped_stages', v_skipped,
        'skip_acknowledged', true,
        'movement', 'forward_skip'
      );
    else
      v_meta := jsonb_build_object('movement', 'forward');
    end if;
  elsif v_to.sort_order < v_from.sort_order then
    v_meta := jsonb_build_object('movement', 'backward');
  else
    -- Distinct stages can share sort_order only if constraints broken; treat as lateral.
    v_meta := jsonb_build_object('movement', 'same_order');
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
    v_meta
  );

  perform set_config('hireflow.stage_transition', '1', true);

  update public.applications
  set current_job_stage_id = v_to.id,
      updated_at = now()
  where id = v_app.id
    and tenant_id = p_tenant_id
  returning * into v_app;

  perform set_config('hireflow.stage_transition', '', true);

  return v_app;
end;
$$;

grant execute on function public.transition_application_stage(uuid, uuid, uuid, text, text, boolean)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Job Workspace index
-- ---------------------------------------------------------------------------
create index if not exists applications_board_status_stage_idx
  on public.applications (tenant_id, job_id, status, current_job_stage_id);

-- ---------------------------------------------------------------------------
-- 4) Interview Assessment foundation
-- ---------------------------------------------------------------------------
create table public.assessment_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  name text not null,
  description text,
  archived_at timestamptz,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  check (length(trim(name)) > 0)
);

create trigger assessment_templates_set_updated_at
  before update on public.assessment_templates
  for each row execute function public.set_updated_at();

create table public.assessment_template_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  template_id uuid not null,
  version_number int not null check (version_number >= 1),
  status text not null default 'draft'
    check (status in ('draft', 'published')),
  published_at timestamptz,
  published_by uuid references public.users (id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, version_number),
  unique (id, tenant_id),
  foreign key (template_id, tenant_id)
    references public.assessment_templates (id, tenant_id)
    on delete cascade,
  check (
    (status = 'draft' and published_at is null and published_by is null)
    or (status = 'published' and published_at is not null)
  )
);

create trigger assessment_template_versions_set_updated_at
  before update on public.assessment_template_versions
  for each row execute function public.set_updated_at();

comment on table public.assessment_template_versions is
  'Draft versions and fields are editable. Once status=published, the version and its fields are immutable; further changes require a new version.';

-- Only PUBLISHED versions are immutable. Draft versions may be updated/deleted.
-- Transition draft → published is allowed (publish). Published rows cannot be mutated.
create or replace function public.assessment_template_versions_protect_published()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    if old.status = 'published' then
      raise exception 'Published assessment_template_versions are immutable';
    end if;
    return new;
  end if;

  -- DELETE
  if old.status = 'published' then
    raise exception 'Published assessment_template_versions are immutable';
  end if;
  return old;
end;
$$;

create trigger assessment_template_versions_protect_published_upd
  before update on public.assessment_template_versions
  for each row execute function public.assessment_template_versions_protect_published();

create trigger assessment_template_versions_protect_published_del
  before delete on public.assessment_template_versions
  for each row execute function public.assessment_template_versions_protect_published();

create table public.assessment_template_fields (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  template_version_id uuid not null,
  key text not null,
  label text not null,
  field_type text not null
    check (field_type in (
      'text',
      'long_text',
      'yes_no',
      'single_select',
      'multi_select',
      'numeric_rating',
      'number'
    )),
  -- Structured config: options[], min/max for ratings, required, etc.
  field_config jsonb not null default '{}'::jsonb,
  sort_order int not null check (sort_order >= 1),
  is_required boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_version_id, key),
  unique (template_version_id, sort_order),
  unique (id, tenant_id),
  foreign key (template_version_id, tenant_id)
    references public.assessment_template_versions (id, tenant_id)
    on delete cascade,
  check (length(trim(key)) > 0),
  check (length(trim(label)) > 0)
);

create trigger assessment_template_fields_set_updated_at
  before update on public.assessment_template_fields
  for each row execute function public.set_updated_at();

create or replace function public.assessment_template_fields_protect_published()
returns trigger
language plpgsql
as $$
declare
  v_new_status text;
  v_old_status text;
begin
  -- Block INSERT/UPDATE/DELETE against published versions.
  -- On UPDATE, check both old and new version ids so fields cannot be
  -- "moved" off a published version onto a draft.
  if tg_op in ('INSERT', 'UPDATE') then
    select status into v_new_status
    from public.assessment_template_versions
    where id = new.template_version_id;

    if v_new_status = 'published' then
      raise exception 'assessment_template_fields are immutable on published versions';
    end if;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    select status into v_old_status
    from public.assessment_template_versions
    where id = old.template_version_id;

    if v_old_status = 'published' then
      raise exception 'assessment_template_fields are immutable on published versions';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger assessment_template_fields_protect_published_ins
  before insert on public.assessment_template_fields
  for each row execute function public.assessment_template_fields_protect_published();

create trigger assessment_template_fields_protect_published_upd
  before update on public.assessment_template_fields
  for each row execute function public.assessment_template_fields_protect_published();

create trigger assessment_template_fields_protect_published_del
  before delete on public.assessment_template_fields
  for each row execute function public.assessment_template_fields_protect_published();

create table public.interview_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  interview_id uuid,
  template_version_id uuid not null,
  status text not null default 'draft'
    check (status in ('draft', 'finalized')),
  created_by uuid not null references public.users (id),
  finalized_at timestamptz,
  finalized_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id),
  foreign key (interview_id, tenant_id)
    references public.interviews (id, tenant_id),
  foreign key (template_version_id, tenant_id)
    references public.assessment_template_versions (id, tenant_id),
  check (
    (status = 'draft' and finalized_at is null and finalized_by is null)
    or (status = 'finalized' and finalized_at is not null and finalized_by is not null)
  )
);

-- Future amendments: never UPDATE finalized rows/answers. A later explicit
-- auditable amendment/revision workflow may add new rows; no overwrite hatch.
comment on table public.interview_assessments is
  'Application-owned interview assessments. interview_id optional. Finalized assessments and answers are immutable in Step 3; future corrections must be auditable amendments, never silent overwrite.';

create trigger interview_assessments_set_updated_at
  before update on public.interview_assessments
  for each row execute function public.set_updated_at();

create index interview_assessments_app_idx
  on public.interview_assessments (application_id, created_at desc);

create table public.interview_assessment_answers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  assessment_id uuid not null,
  template_field_id uuid,
  -- Immutable historical field definition (History Never Lies)
  field_key text not null,
  field_label text not null,
  field_type text not null,
  field_config jsonb not null default '{}'::jsonb,
  value jsonb not null default 'null'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (assessment_id, field_key),
  unique (id, tenant_id),
  foreign key (assessment_id, tenant_id)
    references public.interview_assessments (id, tenant_id)
    on delete cascade,
  foreign key (template_field_id, tenant_id)
    references public.assessment_template_fields (id, tenant_id)
    on delete set null,
  check (length(trim(field_key)) > 0),
  check (length(trim(field_label)) > 0)
);

create trigger interview_assessment_answers_set_updated_at
  before update on public.interview_assessment_answers
  for each row execute function public.set_updated_at();

create or replace function public.interview_assessments_guard_finalized()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'finalized' then
    raise exception 'Finalized interview assessments are immutable';
  end if;
  return new;
end;
$$;

create trigger interview_assessments_guard_finalized
  before update on public.interview_assessments
  for each row execute function public.interview_assessments_guard_finalized();

create or replace function public.interview_assessment_answers_guard_finalized()
returns trigger
language plpgsql
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.interview_assessments
  where id = coalesce(new.assessment_id, old.assessment_id);

  if v_status = 'finalized' then
    raise exception 'Finalized interview assessment answers are immutable';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger interview_assessment_answers_guard_finalized_ins
  before insert on public.interview_assessment_answers
  for each row execute function public.interview_assessment_answers_guard_finalized();

create trigger interview_assessment_answers_guard_finalized_upd
  before update on public.interview_assessment_answers
  for each row execute function public.interview_assessment_answers_guard_finalized();

create trigger interview_assessment_answers_guard_finalized_del
  before delete on public.interview_assessment_answers
  for each row execute function public.interview_assessment_answers_guard_finalized();

-- RLS for assessment tables
alter table public.assessment_templates enable row level security;
alter table public.assessment_template_versions enable row level security;
alter table public.assessment_template_fields enable row level security;
alter table public.interview_assessments enable row level security;
alter table public.interview_assessment_answers enable row level security;

create policy assessment_templates_select on public.assessment_templates
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy assessment_templates_write on public.assessment_templates
  for all to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  )
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy assessment_template_versions_select on public.assessment_template_versions
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy assessment_template_versions_write on public.assessment_template_versions
  for all to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  )
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy assessment_template_fields_select on public.assessment_template_fields
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy assessment_template_fields_write on public.assessment_template_fields
  for all to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  )
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy interview_assessments_select on public.interview_assessments
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy interview_assessments_write on public.interview_assessments
  for all to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  )
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy interview_assessment_answers_select on public.interview_assessment_answers
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy interview_assessment_answers_write on public.interview_assessment_answers
  for all to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  )
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

grant select, insert, update, delete on public.assessment_templates to authenticated;
grant select, insert, update, delete on public.assessment_template_versions to authenticated;
grant select, insert, update, delete on public.assessment_template_fields to authenticated;
grant select, insert, update, delete on public.interview_assessments to authenticated;
grant select, insert, update, delete on public.interview_assessment_answers to authenticated;
grant all on public.assessment_templates to service_role;
grant all on public.assessment_template_versions to service_role;
grant all on public.assessment_template_fields to service_role;
grant all on public.interview_assessments to service_role;
grant all on public.interview_assessment_answers to service_role;

-- Publish a draft template version (draft → published). After this, version/fields are immutable.
create or replace function public.publish_assessment_template_version(
  p_tenant_id uuid,
  p_template_version_id uuid
)
returns public.assessment_template_versions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_version public.assessment_template_versions;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_version
  from public.assessment_template_versions
  where id = p_template_version_id
    and tenant_id = p_tenant_id
  for update;

  if v_version.id is null then
    raise exception 'Assessment template version not found';
  end if;

  if v_version.status is distinct from 'draft' then
    raise exception 'Only draft assessment template versions can be published';
  end if;

  if not exists (
    select 1
    from public.assessment_template_fields
    where template_version_id = p_template_version_id
      and tenant_id = p_tenant_id
  ) then
    raise exception 'Cannot publish a template version with no fields';
  end if;

  update public.assessment_template_versions
  set status = 'published',
      published_at = now(),
      published_by = v_actor,
      updated_at = now()
  where id = p_template_version_id
    and tenant_id = p_tenant_id
  returning * into v_version;

  return v_version;
end;
$$;

-- Create draft assessment against a published template version
create or replace function public.create_interview_assessment(
  p_tenant_id uuid,
  p_application_id uuid,
  p_template_version_id uuid,
  p_interview_id uuid default null
)
returns public.interview_assessments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_app public.applications;
  v_version public.assessment_template_versions;
  v_row public.interview_assessments;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_app
  from public.applications
  where id = p_application_id
    and tenant_id = p_tenant_id;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;

  select * into v_version
  from public.assessment_template_versions
  where id = p_template_version_id
    and tenant_id = p_tenant_id;

  if v_version.id is null then
    raise exception 'Assessment template version not found';
  end if;

  if v_version.status is distinct from 'published' then
    raise exception 'Assessments can only be created from a published template version';
  end if;

  if p_interview_id is not null
    and not exists (
      select 1
      from public.interviews i
      where i.id = p_interview_id
        and i.tenant_id = p_tenant_id
        and i.application_id = p_application_id
    )
  then
    raise exception 'Interview not found for this application';
  end if;

  insert into public.interview_assessments (
    tenant_id,
    application_id,
    interview_id,
    template_version_id,
    status,
    created_by
  )
  values (
    p_tenant_id,
    p_application_id,
    p_interview_id,
    p_template_version_id,
    'draft',
    v_actor
  )
  returning * into v_row;

  return v_row;
end;
$$;

-- Upsert draft answers; snapshots field definition including field_config
create or replace function public.save_interview_assessment_answers(
  p_tenant_id uuid,
  p_assessment_id uuid,
  p_answers jsonb
)
returns setof public.interview_assessment_answers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assessment public.interview_assessments;
  v_item jsonb;
  v_field public.assessment_template_fields;
  v_field_id uuid;
  v_value jsonb;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  select * into v_assessment
  from public.interview_assessments
  where id = p_assessment_id
    and tenant_id = p_tenant_id
  for update;

  if v_assessment.id is null then
    raise exception 'Assessment not found';
  end if;

  if v_assessment.status is distinct from 'draft' then
    raise exception 'Only draft assessments can be edited';
  end if;

  if p_answers is null or jsonb_typeof(p_answers) is distinct from 'array' then
    raise exception 'Answers payload must be a JSON array';
  end if;

  for v_item in select * from jsonb_array_elements(p_answers)
  loop
    v_field_id := nullif(v_item->>'template_field_id', '')::uuid;
    v_value := coalesce(v_item->'value', 'null'::jsonb);

    if v_field_id is null then
      raise exception 'Each answer requires template_field_id';
    end if;

    select * into v_field
    from public.assessment_template_fields
    where id = v_field_id
      and tenant_id = p_tenant_id
      and template_version_id = v_assessment.template_version_id;

    if v_field.id is null then
      raise exception 'Template field % not found on this assessment version', v_field_id;
    end if;

    insert into public.interview_assessment_answers (
      tenant_id,
      assessment_id,
      template_field_id,
      field_key,
      field_label,
      field_type,
      field_config,
      value
    )
    values (
      p_tenant_id,
      p_assessment_id,
      v_field.id,
      v_field.key,
      v_field.label,
      v_field.field_type,
      coalesce(v_field.field_config, '{}'::jsonb),
      v_value
    )
    on conflict (assessment_id, field_key) do update
      set template_field_id = excluded.template_field_id,
          field_label = excluded.field_label,
          field_type = excluded.field_type,
          field_config = excluded.field_config,
          value = excluded.value,
          updated_at = now();
  end loop;

  return query
  select *
  from public.interview_assessment_answers
  where assessment_id = p_assessment_id
    and tenant_id = p_tenant_id
  order by field_key;
end;
$$;

create or replace function public.finalize_interview_assessment(
  p_tenant_id uuid,
  p_assessment_id uuid
)
returns public.interview_assessments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_assessment public.interview_assessments;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin', 'recruiter']::text[]
  ) then
    raise exception 'Not allowed';
  end if;

  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_assessment
  from public.interview_assessments
  where id = p_assessment_id
    and tenant_id = p_tenant_id
  for update;

  if v_assessment.id is null then
    raise exception 'Assessment not found';
  end if;

  if v_assessment.status is distinct from 'draft' then
    raise exception 'Assessment is already finalized';
  end if;

  -- old.status is draft, so finalized-immutability guard allows this transition.
  update public.interview_assessments
  set status = 'finalized',
      finalized_at = now(),
      finalized_by = v_actor,
      updated_at = now()
  where id = p_assessment_id
    and tenant_id = p_tenant_id
  returning * into v_assessment;

  return v_assessment;
end;
$$;

grant execute on function public.publish_assessment_template_version(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.create_interview_assessment(uuid, uuid, uuid, uuid)
  to authenticated, service_role;
grant execute on function public.save_interview_assessment_answers(uuid, uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.finalize_interview_assessment(uuid, uuid)
  to authenticated, service_role;
