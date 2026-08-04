-- HireFlow baseline schema
-- Source of truth: docs/DATABASE_DESIGN.md
-- Engine: PostgreSQL (Supabase)

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists citext with schema extensions;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3.1 tenants
-- ---------------------------------------------------------------------------
create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  timezone text not null default 'UTC',
  locale text not null default 'en-US',
  status text not null default 'active'
    check (status in ('active', 'suspended', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tenants_set_updated_at
  before update on public.tenants
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.2 users (staff only; linked to Supabase Auth)
-- ---------------------------------------------------------------------------
create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  email extensions.citext not null unique,
  password_hash text,
  full_name text,
  status text not null default 'active'
    check (status in ('active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger users_set_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();

-- Keep public.users in sync when a Supabase Auth user is created.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, full_name, status)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    'active'
  )
  on conflict (id) do update
    set email = excluded.email,
        updated_at = now();
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- 3.3 tenant_memberships
-- ---------------------------------------------------------------------------
create table public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  user_id uuid not null references public.users (id),
  role text not null
    check (role in (
      'tenant_owner',
      'company_admin',
      'recruiter',
      'hiring_manager',
      'interviewer',
      'viewer'
    )),
  status text not null default 'invited'
    check (status in ('active', 'invited', 'revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);

create index tenant_memberships_user_id_idx
  on public.tenant_memberships (user_id);

create trigger tenant_memberships_set_updated_at
  before update on public.tenant_memberships
  for each row execute function public.set_updated_at();

-- Active tenant memberships for the current auth user (RLS helpers).
create or replace function public.current_tenant_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select tm.tenant_id
  from public.tenant_memberships tm
  where tm.user_id = auth.uid()
    and tm.status = 'active';
$$;

create or replace function public.is_tenant_member(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenant_memberships tm
    where tm.tenant_id = p_tenant_id
      and tm.user_id = auth.uid()
      and tm.status = 'active'
  );
$$;

-- ---------------------------------------------------------------------------
-- 3.8 pipeline_stages (before jobs; seeded per tenant)
-- ---------------------------------------------------------------------------
create table public.pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  key text not null,
  name text not null,
  sort_order int not null,
  stage_type text not null
    check (stage_type in ('active', 'terminal_success', 'terminal_closed')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, key),
  unique (tenant_id, sort_order)
);

create or replace function public.seed_default_pipeline_stages(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.pipeline_stages (tenant_id, key, name, sort_order, stage_type)
  values
    (p_tenant_id, 'applied', 'Applied', 1, 'active'),
    (p_tenant_id, 'cv_screening', 'CV Screening', 2, 'active'),
    (p_tenant_id, 'phone_screening', 'Phone Screening', 3, 'active'),
    (p_tenant_id, 'interview', 'Interview', 4, 'active'),
    (p_tenant_id, 'reference_check', 'Reference Check', 5, 'active'),
    (p_tenant_id, 'offer', 'Offer', 6, 'active'),
    (p_tenant_id, 'pre_hire', 'Pre-Hire / Onboarding Docs', 7, 'active'),
    (p_tenant_id, 'hired', 'Hired', 8, 'terminal_success'),
    (p_tenant_id, 'rejected', 'Rejected', 9, 'terminal_closed'),
    (p_tenant_id, 'withdrawn', 'Withdrawn', 10, 'terminal_closed')
  on conflict (tenant_id, key) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3.4 jobs
-- ---------------------------------------------------------------------------
create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  title text not null,
  department text,
  location text,
  employment_type text
    check (employment_type is null or employment_type in (
      'full_time', 'part_time', 'contract', 'intern'
    )),
  description text,
  status text not null default 'draft'
    check (status in ('draft', 'open', 'on_hold', 'closed', 'filled')),
  openings int not null default 1 check (openings >= 1),
  requesting_department text,
  requested_by_name text,
  requested_at timestamptz,
  hiring_manager_name text,
  hiring_manager_email text,
  published_at timestamptz,
  public_apply_token text unique,
  apply_enabled boolean not null default false,
  created_by uuid references public.users (id),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id)
);

create index jobs_tenant_status_idx on public.jobs (tenant_id, status);
create index jobs_tenant_created_at_idx on public.jobs (tenant_id, created_at desc);

create trigger jobs_set_updated_at
  before update on public.jobs
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.5 candidates
-- ---------------------------------------------------------------------------
create table public.candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  full_name text not null,
  email extensions.citext,
  phone text,
  source text
    check (source is null or source in (
      'inbound', 'referral', 'linkedin', 'agency', 'manual', 'other'
    )),
  linkedin_url text,
  notes text,
  created_by uuid references public.users (id),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id)
);

-- Duplicate detection: one email per tenant when email is present.
create unique index candidates_tenant_email_uidx
  on public.candidates (tenant_id, email)
  where email is not null;

create index candidates_tenant_full_name_idx
  on public.candidates (tenant_id, full_name);

create trigger candidates_set_updated_at
  before update on public.candidates
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.6 applications
-- ---------------------------------------------------------------------------
create table public.applications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  job_id uuid not null,
  candidate_id uuid not null,
  current_stage text not null,
  status text not null default 'active'
    check (status in ('active', 'terminal')),
  reject_reason_code text,
  hired_at timestamptz,
  start_date date,
  withdrawn_at timestamptz,
  rejected_at timestamptz,
  source text,
  submitted_via text
    check (submitted_via is null or submitted_via in (
      'public_form', 'manual', 'import'
    )),
  consent_at timestamptz,
  consent_text_version text,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, job_id, candidate_id),
  unique (id, tenant_id),
  foreign key (job_id, tenant_id) references public.jobs (id, tenant_id),
  foreign key (candidate_id, tenant_id) references public.candidates (id, tenant_id)
);

create index applications_board_idx
  on public.applications (tenant_id, job_id, current_stage);
create index applications_candidate_idx
  on public.applications (tenant_id, candidate_id);

create trigger applications_set_updated_at
  before update on public.applications
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.7 application_stage_events (append-only)
-- ---------------------------------------------------------------------------
create table public.application_stage_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  from_stage text,
  to_stage text not null,
  actor_user_id uuid references public.users (id),
  note text,
  reason_code text,
  occurred_at timestamptz not null default now(),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id)
);

create index application_stage_events_app_idx
  on public.application_stage_events (application_id, occurred_at);
create index application_stage_events_tenant_idx
  on public.application_stage_events (tenant_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- 3.15 files (before offers/checklist FKs)
-- ---------------------------------------------------------------------------
create table public.files (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  owner_type text not null
    check (owner_type in (
      'candidate', 'application', 'offer', 'checklist_item'
    )),
  owner_id uuid not null,
  file_name text,
  content_type text,
  size_bytes bigint,
  storage_key text not null,
  status text not null default 'pending'
    check (status in ('pending', 'ready', 'deleted')),
  uploaded_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (id, tenant_id)
);

create index files_owner_idx
  on public.files (tenant_id, owner_type, owner_id);

-- ---------------------------------------------------------------------------
-- 3.9 interviews
-- ---------------------------------------------------------------------------
create table public.interviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  interview_type text,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'completed', 'canceled', 'no_show')),
  scheduled_starts_at timestamptz,
  scheduled_ends_at timestamptz,
  interviewer_name text,
  interviewer_email text,
  interviewer_user_id uuid references public.users (id),
  location_or_link text,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id)
);

create index interviews_tenant_starts_idx
  on public.interviews (tenant_id, scheduled_starts_at);
create index interviews_application_idx
  on public.interviews (application_id);

create trigger interviews_set_updated_at
  before update on public.interviews
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.10 interview_feedback
-- ---------------------------------------------------------------------------
create table public.interview_feedback (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  interview_id uuid not null,
  author_user_id uuid not null references public.users (id),
  on_behalf_of_name text,
  recommendation text
    check (recommendation is null or recommendation in (
      'strong_yes', 'yes', 'neutral', 'no', 'strong_no'
    )),
  score int check (score is null or (score between 1 and 5)),
  notes text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (interview_id, author_user_id),
  foreign key (interview_id, tenant_id)
    references public.interviews (id, tenant_id)
);

create trigger interview_feedback_set_updated_at
  before update on public.interview_feedback
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.11 offers
-- ---------------------------------------------------------------------------
create table public.offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  status text not null default 'draft'
    check (status in (
      'draft', 'sent', 'accepted', 'declined', 'rescinded', 'expired'
    )),
  compensation_summary text,
  currency text,
  base_salary numeric,
  offer_date date,
  expiry_date date,
  accepted_at timestamptz,
  start_date_proposed date,
  letter_file_id uuid,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id),
  foreign key (letter_file_id, tenant_id)
    references public.files (id, tenant_id)
);

create index offers_application_idx on public.offers (application_id);
create index offers_tenant_status_idx on public.offers (tenant_id, status);

create trigger offers_set_updated_at
  before update on public.offers
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.12 application_checklist_items
-- ---------------------------------------------------------------------------
create table public.application_checklist_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  key text not null,
  label text not null,
  item_type text not null
    check (item_type in (
      'document_upload', 'acknowledgment', 'manual_confirm'
    )),
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'waived')),
  file_id uuid,
  completed_at timestamptz,
  completed_by uuid references public.users (id),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (application_id, key),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id),
  foreign key (file_id, tenant_id)
    references public.files (id, tenant_id)
);

create trigger application_checklist_items_set_updated_at
  before update on public.application_checklist_items
  for each row execute function public.set_updated_at();

create or replace function public.seed_pre_hire_checklist(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id
  from public.applications
  where id = p_application_id;

  if v_tenant_id is null then
    raise exception 'application % not found', p_application_id;
  end if;

  insert into public.application_checklist_items (
    tenant_id, application_id, key, label, item_type, sort_order
  )
  values
    (v_tenant_id, p_application_id, 'id_document', 'Identity / right-to-work document', 'document_upload', 1),
    (v_tenant_id, p_application_id, 'signed_offer', 'Signed offer acknowledgment', 'acknowledgment', 2),
    (v_tenant_id, p_application_id, 'signed_jd', 'Signed job description acknowledgment', 'acknowledgment', 3)
  on conflict (application_id, key) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3.13 communications
-- ---------------------------------------------------------------------------
create table public.communications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  type text not null
    check (type in ('regret_letter', 'offer_letter', 'general')),
  channel text not null default 'email_manual'
    check (channel in ('email_manual', 'email_system', 'other')),
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'failed')),
  template_key text,
  subject text,
  body text,
  sent_at timestamptz,
  sent_by uuid references public.users (id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id)
);

create index communications_app_type_idx
  on public.communications (application_id, type);
create index communications_tenant_sent_idx
  on public.communications (tenant_id, sent_at desc);

create trigger communications_set_updated_at
  before update on public.communications
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.14 reference_checks
-- ---------------------------------------------------------------------------
create table public.reference_checks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  application_id uuid not null,
  contact_name text not null,
  relationship text,
  email text,
  phone text,
  outcome text
    check (outcome is null or outcome in (
      'positive', 'neutral', 'negative', 'unable_to_reach'
    )),
  notes text,
  checked_at timestamptz,
  checked_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (application_id, tenant_id)
    references public.applications (id, tenant_id)
);

create index reference_checks_application_idx
  on public.reference_checks (application_id);

create trigger reference_checks_set_updated_at
  before update on public.reference_checks
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3.16 audit_events
-- ---------------------------------------------------------------------------
create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  actor_user_id uuid references public.users (id),
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  ip_address inet,
  occurred_at timestamptz not null default now()
);

create index audit_events_tenant_occurred_idx
  on public.audit_events (tenant_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Tenant provisioning helper
-- ---------------------------------------------------------------------------
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

  insert into public.tenant_memberships (tenant_id, user_id, role, status)
  values (v_tenant_id, p_owner_user_id, 'tenant_owner', 'active');

  insert into public.audit_events (tenant_id, actor_user_id, action, entity_type, entity_id)
  values (v_tenant_id, p_owner_user_id, 'tenant.created', 'tenant', v_tenant_id);

  return v_tenant_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.tenants enable row level security;
alter table public.users enable row level security;
alter table public.tenant_memberships enable row level security;
alter table public.pipeline_stages enable row level security;
alter table public.jobs enable row level security;
alter table public.candidates enable row level security;
alter table public.applications enable row level security;
alter table public.application_stage_events enable row level security;
alter table public.files enable row level security;
alter table public.interviews enable row level security;
alter table public.interview_feedback enable row level security;
alter table public.offers enable row level security;
alter table public.application_checklist_items enable row level security;
alter table public.communications enable row level security;
alter table public.reference_checks enable row level security;
alter table public.audit_events enable row level security;

-- tenants: members can read their tenants
create policy tenants_select_member on public.tenants
  for select to authenticated
  using (id in (select public.current_tenant_ids()));

-- users: can read self; members of shared tenants can read each other later via memberships
create policy users_select_self on public.users
  for select to authenticated
  using (id = auth.uid());

create policy users_update_self on public.users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- memberships
create policy tenant_memberships_select_member on public.tenant_memberships
  for select to authenticated
  using (tenant_id in (select public.current_tenant_ids()) or user_id = auth.uid());

-- Generic tenant-scoped policies for business tables
create policy pipeline_stages_tenant_all on public.pipeline_stages
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy jobs_tenant_all on public.jobs
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy candidates_tenant_all on public.candidates
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy applications_tenant_all on public.applications
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy application_stage_events_tenant_select on public.application_stage_events
  for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy application_stage_events_tenant_insert on public.application_stage_events
  for insert to authenticated
  with check (public.is_tenant_member(tenant_id));

create policy files_tenant_all on public.files
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy interviews_tenant_all on public.interviews
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy interview_feedback_tenant_all on public.interview_feedback
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy offers_tenant_all on public.offers
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy application_checklist_items_tenant_all on public.application_checklist_items
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy communications_tenant_all on public.communications
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy reference_checks_tenant_all on public.reference_checks
  for all to authenticated
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy audit_events_tenant_select on public.audit_events
  for select to authenticated
  using (tenant_id is null or public.is_tenant_member(tenant_id));

create policy audit_events_tenant_insert on public.audit_events
  for insert to authenticated
  with check (tenant_id is null or public.is_tenant_member(tenant_id));

-- Public apply needs anon read of open jobs by token (token acts as capability).
create policy jobs_anon_public_apply_select on public.jobs
  for select to anon
  using (
    status = 'open'
    and apply_enabled = true
    and public_apply_token is not null
    and archived_at is null
  );

-- ---------------------------------------------------------------------------
-- Grants (Supabase roles)
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;

grant select on public.jobs to anon;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to authenticated, service_role;
