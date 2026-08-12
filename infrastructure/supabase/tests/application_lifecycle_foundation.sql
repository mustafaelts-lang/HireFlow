-- Focused tests: Architecture Hardening Step 1 — application lifecycle foundation
-- Single-statement DO block; creates temporary fixtures and cleans them up.
-- Run only after migration 20260805050000_application_lifecycle_foundation.sql is applied.

do $$
declare
  v_tenant_a uuid := gen_random_uuid();
  v_tenant_b uuid := gen_random_uuid();
  v_job_a uuid := gen_random_uuid();
  v_job_a2 uuid := gen_random_uuid();
  v_job_b uuid := gen_random_uuid();
  v_candidate_a uuid := gen_random_uuid();
  v_candidate_a2 uuid := gen_random_uuid();
  v_candidate_b uuid := gen_random_uuid();
  v_app_active uuid;
  v_app_historical uuid;
  v_app_second_historical uuid;
  v_ok boolean;
begin
  insert into public.tenants (id, name, slug)
  values
    (v_tenant_a, 'HF Step1 Test A', 'hf-step1-a-' || replace(v_tenant_a::text, '-', '')),
    (v_tenant_b, 'HF Step1 Test B', 'hf-step1-b-' || replace(v_tenant_b::text, '-', ''));

  insert into public.jobs (id, tenant_id, title, status)
  values
    (v_job_a, v_tenant_a, 'Step1 Job A', 'open'),
    (v_job_a2, v_tenant_a, 'Step1 Job A2', 'open'),
    (v_job_b, v_tenant_b, 'Step1 Job B', 'open');

  insert into public.candidates (id, tenant_id, full_name, email)
  values
    (v_candidate_a, v_tenant_a, 'Step1 Candidate A', 'step1-a-' || replace(v_candidate_a::text, '-', '') || '@example.test'),
    (v_candidate_a2, v_tenant_a, 'Step1 Candidate A2', 'step1-a2-' || replace(v_candidate_a2::text, '-', '') || '@example.test'),
    (v_candidate_b, v_tenant_b, 'Step1 Candidate B', 'step1-b-' || replace(v_candidate_b::text, '-', '') || '@example.test');

  -- -----------------------------------------------------------------------
  -- multiple historical applications allowed for same candidate + job
  -- -----------------------------------------------------------------------
  insert into public.applications (
    id, tenant_id, job_id, candidate_id, current_stage, status
  ) values (
    gen_random_uuid(), v_tenant_a, v_job_a, v_candidate_a, 'applied', 'withdrawn'
  )
  returning id into v_app_historical;

  insert into public.applications (
    id, tenant_id, job_id, candidate_id, current_stage, status
  ) values (
    gen_random_uuid(), v_tenant_a, v_job_a, v_candidate_a, 'applied', 'disqualified'
  )
  returning id into v_app_second_historical;

  insert into public.applications (
    id, tenant_id, job_id, candidate_id, current_stage, status
  ) values (
    gen_random_uuid(), v_tenant_a, v_job_a, v_candidate_a, 'applied', 'active'
  )
  returning id into v_app_active;

  if (
    select count(*)
    from public.applications
    where tenant_id = v_tenant_a
      and job_id = v_job_a
      and candidate_id = v_candidate_a
  ) <> 3 then
    raise exception 'FAIL: expected 3 historical/active applications for same candidate+job';
  end if;

  -- -----------------------------------------------------------------------
  -- second active application for same candidate+job rejected
  -- -----------------------------------------------------------------------
  begin
    insert into public.applications (
      tenant_id, job_id, candidate_id, current_stage, status
    ) values (
      v_tenant_a, v_job_a, v_candidate_a, 'applied', 'active'
    );
    raise exception 'FAIL: second active application should have been rejected';
  exception
    when unique_violation then
      null;
  end;

  -- -----------------------------------------------------------------------
  -- application job_id cannot be changed
  -- -----------------------------------------------------------------------
  begin
    update public.applications
    set job_id = v_job_a2
    where id = v_app_active;
    raise exception 'FAIL: job_id mutation should have been rejected';
  exception
    when others then
      if sqlerrm not like '%job_id is immutable%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- application candidate_id cannot be changed
  -- -----------------------------------------------------------------------
  begin
    update public.applications
    set candidate_id = v_candidate_a2
    where id = v_app_active;
    raise exception 'FAIL: candidate_id mutation should have been rejected';
  exception
    when others then
      if sqlerrm not like '%candidate_id is immutable%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- application tenant_id cannot be changed
  -- -----------------------------------------------------------------------
  begin
    update public.applications
    set tenant_id = v_tenant_b
    where id = v_app_active;
    raise exception 'FAIL: tenant_id mutation should have been rejected';
  exception
    when others then
      if sqlerrm not like '%tenant_id is immutable%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- cross-tenant integrity remains enforced
  -- -----------------------------------------------------------------------
  begin
    insert into public.applications (
      tenant_id, job_id, candidate_id, current_stage, status
    ) values (
      v_tenant_a, v_job_b, v_candidate_a, 'applied', 'active'
    );
    raise exception 'FAIL: cross-tenant job FK should have been rejected';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into public.applications (
      tenant_id, job_id, candidate_id, current_stage, status
    ) values (
      v_tenant_a, v_job_a, v_candidate_b, 'applied', 'active'
    );
    raise exception 'FAIL: cross-tenant candidate FK should have been rejected';
  exception
    when foreign_key_violation then
      null;
  end;

  -- Allowed: same candidate active on a different job
  insert into public.applications (
    tenant_id, job_id, candidate_id, current_stage, status
  ) values (
    v_tenant_a, v_job_a2, v_candidate_a, 'applied', 'active'
  );

  v_ok := true;

  -- cleanup (order matters for FKs)
  delete from public.applications
  where tenant_id in (v_tenant_a, v_tenant_b);

  delete from public.candidates
  where tenant_id in (v_tenant_a, v_tenant_b);

  delete from public.jobs
  where tenant_id in (v_tenant_a, v_tenant_b);

  delete from public.tenants
  where id in (v_tenant_a, v_tenant_b);

  if not v_ok then
    raise exception 'FAIL: unexpected state';
  end if;

  raise notice 'PASS: application_lifecycle_foundation tests';
end;
$$;
