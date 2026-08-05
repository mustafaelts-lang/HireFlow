-- Sprint 4: Jobs foundation — template link, stage snapshot, role-aware RLS

-- ---------------------------------------------------------------------------
-- Link jobs to pipeline templates + snapshot stages per job
-- ---------------------------------------------------------------------------
alter table public.jobs
  add column if not exists pipeline_template_id uuid;

alter table public.jobs
  drop constraint if exists jobs_pipeline_template_tenant_fk;

alter table public.jobs
  add constraint jobs_pipeline_template_tenant_fk
  foreign key (pipeline_template_id, tenant_id)
  references public.pipeline_templates (id, tenant_id);

create index if not exists jobs_tenant_template_idx
  on public.jobs (tenant_id, pipeline_template_id);

create table if not exists public.job_stages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  job_id uuid not null,
  key text not null,
  name text not null,
  sort_order int not null check (sort_order >= 1),
  color text not null default '#0F6B4C'
    check (color ~ '^#[0-9A-Fa-f]{6}$'),
  sla_days int check (sla_days is null or sla_days >= 0),
  category text not null
    check (category in (
      'intake',
      'screening',
      'interview',
      'reference',
      'offer',
      'pre_hire',
      'hired',
      'closed',
      'custom'
    )),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_id, key),
  unique (job_id, sort_order),
  unique (id, tenant_id),
  foreign key (job_id, tenant_id)
    references public.jobs (id, tenant_id)
    on delete cascade,
  check (length(trim(name)) > 0),
  check (length(trim(key)) > 0)
);

create index if not exists job_stages_job_idx
  on public.job_stages (job_id, sort_order);

create trigger job_stages_set_updated_at
  before update on public.job_stages
  for each row execute function public.set_updated_at();

alter table public.job_stages enable row level security;

-- ---------------------------------------------------------------------------
-- Tighten jobs RLS to role-aware policies (match pipelines pattern)
-- ---------------------------------------------------------------------------
drop policy if exists jobs_tenant_all on public.jobs;

create policy jobs_select_member on public.jobs
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy jobs_insert_writers on public.jobs
  for insert to authenticated
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy jobs_update_writers on public.jobs
  for update to authenticated
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

create policy jobs_delete_admins on public.jobs
  for delete to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin']::text[]
    )
  );

create policy job_stages_select on public.job_stages
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy job_stages_insert on public.job_stages
  for insert to authenticated
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy job_stages_update on public.job_stages
  for update to authenticated
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

create policy job_stages_delete on public.job_stages
  for delete to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

grant select, insert, update, delete on public.job_stages to authenticated;
grant all on public.job_stages to service_role;

-- ---------------------------------------------------------------------------
-- Copy template stages onto a job (draft create / template change)
-- ---------------------------------------------------------------------------
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

  delete from public.job_stages
  where job_id = p_job_id
    and tenant_id = p_tenant_id;

  insert into public.job_stages (
    tenant_id, job_id, key, name, sort_order, color, sla_days, category, notes
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
    notes
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

grant execute on function public.sync_job_stages_from_template(uuid, uuid, uuid)
  to authenticated, service_role;
grant execute on function public.publish_job(uuid, uuid)
  to authenticated, service_role;
