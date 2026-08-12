-- Architecture Hardening Step 1: Application lifecycle foundation
-- - Normalize lifecycle status (system-level; separate from pipeline stage)
-- - Allow multiple historical applications per tenant + candidate + job
-- - Enforce at most one ACTIVE application per tenant + candidate + job
-- - Freeze identity fields after insert: tenant_id, candidate_id, job_id
-- - Preserve every existing application row

-- ---------------------------------------------------------------------------
-- 1) Remap legacy coarse status 'terminal' using only existing timestamps
--    Do not invent disqualification/business narrative text.
-- ---------------------------------------------------------------------------
update public.applications
set status = 'hired'
where status = 'terminal'
  and hired_at is not null;

update public.applications
set status = 'withdrawn'
where status = 'terminal'
  and withdrawn_at is not null;

update public.applications
set status = 'disqualified'
where status = 'terminal'
  and rejected_at is not null;

do $$
begin
  if exists (
    select 1
    from public.applications
    where status = 'terminal'
  ) then
    raise exception
      'Cannot migrate applications.status: residual terminal rows lack hired_at/withdrawn_at/rejected_at for deterministic remapping';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Lifecycle status check: active | hired | disqualified | withdrawn | transferred
--    Pipeline stage remains on current_stage (current_job_stage_id in a later step).
-- ---------------------------------------------------------------------------
alter table public.applications
  drop constraint applications_status_check;

alter table public.applications
  add constraint applications_status_check
  check (status in (
    'active',
    'hired',
    'disqualified',
    'withdrawn',
    'transferred'
  ));

comment on column public.applications.status is
  'Application lifecycle state (system-level). Not derived from pipeline stage names. Values: active, hired, disqualified, withdrawn, transferred.';

-- ---------------------------------------------------------------------------
-- 3) Replace hard uniqueness with one-active-per-(tenant, job, candidate)
-- ---------------------------------------------------------------------------
alter table public.applications
  drop constraint applications_tenant_id_job_id_candidate_id_key;

create unique index applications_one_active_per_candidate_job_uidx
  on public.applications (tenant_id, job_id, candidate_id)
  where status = 'active';

-- ---------------------------------------------------------------------------
-- 4) Freeze identity fields after creation
-- ---------------------------------------------------------------------------
create or replace function public.applications_freeze_identity_fields()
returns trigger
language plpgsql
as $$
begin
  if new.tenant_id is distinct from old.tenant_id then
    raise exception 'applications.tenant_id is immutable after creation';
  end if;

  if new.candidate_id is distinct from old.candidate_id then
    raise exception 'applications.candidate_id is immutable after creation';
  end if;

  if new.job_id is distinct from old.job_id then
    raise exception 'applications.job_id is immutable after creation';
  end if;

  return new;
end;
$$;

drop trigger if exists applications_freeze_identity_fields on public.applications;

create trigger applications_freeze_identity_fields
  before update on public.applications
  for each row
  execute function public.applications_freeze_identity_fields();
