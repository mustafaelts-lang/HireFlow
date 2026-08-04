-- Sprint 3: Pipeline Templates

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.pipeline_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  name text not null,
  description text,
  is_default boolean not null default false,
  archived_at timestamptz,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  check (length(trim(name)) > 0)
);

create index pipeline_templates_tenant_idx
  on public.pipeline_templates (tenant_id, archived_at, created_at desc);

-- Exactly one active default template per organization.
create unique index pipeline_templates_one_default_per_tenant
  on public.pipeline_templates (tenant_id)
  where is_default = true and archived_at is null;

create trigger pipeline_templates_set_updated_at
  before update on public.pipeline_templates
  for each row execute function public.set_updated_at();

create table public.pipeline_template_stages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  template_id uuid not null,
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
  unique (template_id, key),
  unique (template_id, sort_order),
  unique (id, tenant_id),
  foreign key (template_id, tenant_id)
    references public.pipeline_templates (id, tenant_id)
    on delete cascade,
  check (length(trim(name)) > 0),
  check (length(trim(key)) > 0)
);

create index pipeline_template_stages_template_idx
  on public.pipeline_template_stages (template_id, sort_order);

create trigger pipeline_template_stages_set_updated_at
  before update on public.pipeline_template_stages
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.pipeline_templates enable row level security;
alter table public.pipeline_template_stages enable row level security;

create policy pipeline_templates_select on public.pipeline_templates
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy pipeline_templates_insert on public.pipeline_templates
  for insert to authenticated
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy pipeline_templates_update on public.pipeline_templates
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

create policy pipeline_templates_delete on public.pipeline_templates
  for delete to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin']::text[]
    )
  );

create policy pipeline_template_stages_select on public.pipeline_template_stages
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy pipeline_template_stages_insert on public.pipeline_template_stages
  for insert to authenticated
  with check (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

create policy pipeline_template_stages_update on public.pipeline_template_stages
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

create policy pipeline_template_stages_delete on public.pipeline_template_stages
  for delete to authenticated
  using (
    public.has_tenant_role(
      tenant_id,
      array['tenant_owner', 'company_admin', 'recruiter']::text[]
    )
  );

grant select, insert, update, delete on public.pipeline_templates to authenticated;
grant select, insert, update, delete on public.pipeline_template_stages to authenticated;
grant all on public.pipeline_templates to service_role;
grant all on public.pipeline_template_stages to service_role;

-- ---------------------------------------------------------------------------
-- Default template seed (HireFlow default stages)
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
    tenant_id, template_id, key, name, sort_order, color, sla_days, category, notes
  )
  values
    (p_tenant_id, v_template_id, 'applied', 'Applied', 1, '#64748B', 2, 'intake', 'New applications land here.'),
    (p_tenant_id, v_template_id, 'cv_screening', 'CV Screening', 2, '#0EA5E9', 3, 'screening', null),
    (p_tenant_id, v_template_id, 'phone_screening', 'Phone Screening', 3, '#06B6D4', 3, 'screening', null),
    (p_tenant_id, v_template_id, 'interview', 'Interview', 4, '#8B5CF6', 7, 'interview', null),
    (p_tenant_id, v_template_id, 'reference_check', 'Reference Check', 5, '#F59E0B', 5, 'reference', null),
    (p_tenant_id, v_template_id, 'offer', 'Offer', 6, '#10B981', 5, 'offer', null),
    (p_tenant_id, v_template_id, 'pre_hire', 'Pre-Hire', 7, '#14B8A6', 7, 'pre_hire', 'Documents and signatures.'),
    (p_tenant_id, v_template_id, 'hired', 'Hired', 8, '#0F6B4C', null, 'hired', 'Terminal success.'),
    (p_tenant_id, v_template_id, 'rejected', 'Rejected', 9, '#DC2626', null, 'closed', 'Terminal closed.'),
    (p_tenant_id, v_template_id, 'withdrawn', 'Withdrawn', 10, '#78716C', null, 'closed', 'Candidate withdrew.');

  return v_template_id;
end;
$$;

-- Wire into tenant provisioning
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

  insert into public.tenant_memberships (tenant_id, user_id, role, status)
  values (v_tenant_id, p_owner_user_id, 'tenant_owner', 'active');

  insert into public.audit_events (tenant_id, actor_user_id, action, entity_type, entity_id)
  values (v_tenant_id, p_owner_user_id, 'tenant.created', 'tenant', v_tenant_id);

  return v_tenant_id;
end;
$$;

-- Backfill existing tenants
do $$
declare
  r record;
begin
  for r in
    select t.id as tenant_id, tm.user_id as owner_id
    from public.tenants t
    left join lateral (
      select user_id
      from public.tenant_memberships
      where tenant_id = t.id
        and role = 'tenant_owner'
        and status = 'active'
      order by created_at
      limit 1
    ) tm on true
  loop
    perform public.seed_default_pipeline_template(r.tenant_id, r.owner_id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Safe default setter + delete guards
-- ---------------------------------------------------------------------------
create or replace function public.set_default_pipeline_template(
  p_tenant_id uuid,
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
    from public.pipeline_templates
    where id = p_template_id
      and tenant_id = p_tenant_id
      and archived_at is null
  ) then
    raise exception 'Template not found or archived';
  end if;

  update public.pipeline_templates
  set is_default = false,
      updated_at = now()
  where tenant_id = p_tenant_id
    and is_default = true
    and archived_at is null
    and id <> p_template_id;

  update public.pipeline_templates
  set is_default = true,
      updated_at = now()
  where id = p_template_id
    and tenant_id = p_tenant_id;
end;
$$;

create or replace function public.delete_pipeline_template(
  p_tenant_id uuid,
  p_template_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_default boolean;
begin
  if not public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin']::text[]
  ) then
    raise exception 'Only Owner or Admin can delete templates';
  end if;

  select is_default into v_is_default
  from public.pipeline_templates
  where id = p_template_id
    and tenant_id = p_tenant_id;

  if v_is_default is null then
    raise exception 'Template not found';
  end if;

  if v_is_default then
    raise exception 'Cannot delete the default template. Set another default first.';
  end if;

  delete from public.pipeline_templates
  where id = p_template_id
    and tenant_id = p_tenant_id;
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
    tenant_id, template_id, key, name, sort_order, color, sla_days, category, notes
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
    notes
  from public.pipeline_template_stages
  where template_id = p_template_id
  order by sort_order;

  return v_new_id;
end;
$$;

grant execute on function public.seed_default_pipeline_template(uuid, uuid) to authenticated, service_role;
grant execute on function public.set_default_pipeline_template(uuid, uuid) to authenticated, service_role;
grant execute on function public.delete_pipeline_template(uuid, uuid) to authenticated, service_role;
grant execute on function public.duplicate_pipeline_template(uuid, uuid, text) to authenticated, service_role;
