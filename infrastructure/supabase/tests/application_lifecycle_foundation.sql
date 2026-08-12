-- Focused tests: Architecture Hardening Step 1 — application lifecycle foundation
-- Compatible with Step 2+ schema (current_job_stage_id + Applied entry stages).

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
  v_stage_a uuid := gen_random_uuid();
  v_stage_a2 uuid := gen_random_uuid();
  v_stage_b uuid := gen_random_uuid();
  v_app_active uuid;
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

  insert into public.job_stages (
    id, tenant_id, job_id, key, name, sort_order, color, category, is_applied_entry
  ) values
    (v_stage_a, v_tenant_a, v_job_a, 'applied', 'Applied', 1, '#64748B', 'intake', true),
    (v_stage_a2, v_tenant_a, v_job_a2, 'applied', 'Applied', 1, '#64748B', 'intake', true),
    (v_stage_b, v_tenant_b, v_job_b, 'applied', 'Applied', 1, '#64748B', 'intake', true);

  insert into public.candidates (id, tenant_id, full_name, email)
  values
    (v_candidate_a, v_tenant_a, 'Step1 Candidate A', 'step1-a-' || replace(v_candidate_a::text, '-', '') || '@example.test'),
    (v_candidate_a2, v_tenant_a, 'Step1 Candidate A2', 'step1-a2-' || replace(v_candidate_a2::text, '-', '') || '@example.test'),
    (v_candidate_b, v_tenant_b, 'Step1 Candidate B', 'step1-b-' || replace(v_candidate_b::text, '-', '') || '@example.test');

  insert into public.applications (
    tenant_id, job_id, candidate_id, status
  ) values (
    v_tenant_a, v_job_a, v_candidate_a, 'withdrawn'
  );

  insert into public.applications (
    tenant_id, job_id, candidate_id, status
  ) values (
    v_tenant_a, v_job_a, v_candidate_a, 'disqualified'
  );

  insert into public.applications (
    tenant_id, job_id, candidate_id, status
  ) values (
    v_tenant_a, v_job_a, v_candidate_a, 'active'
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

  begin
    insert into public.applications (
      tenant_id, job_id, candidate_id, status
    ) values (
      v_tenant_a, v_job_a, v_candidate_a, 'active'
    );
    raise exception 'FAIL: second active application should have been rejected';
  exception
    when unique_violation then
      null;
  end;

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

  begin
    insert into public.applications (
      tenant_id, job_id, candidate_id, status
    ) values (
      v_tenant_a, v_job_b, v_candidate_a, 'active'
    );
    raise exception 'FAIL: cross-tenant job FK should have been rejected';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into public.applications (
      tenant_id, job_id, candidate_id, status
    ) values (
      v_tenant_a, v_job_a, v_candidate_b, 'active'
    );
    raise exception 'FAIL: cross-tenant candidate FK should have been rejected';
  exception
    when foreign_key_violation then
      null;
  end;

  insert into public.applications (
    tenant_id, job_id, candidate_id, status
  ) values (
    v_tenant_a, v_job_a2, v_candidate_a, 'active'
  );

  v_ok := true;

  perform set_config('hireflow.allow_event_maintenance', '1', true);

  delete from public.application_stage_events
  where tenant_id in (v_tenant_a, v_tenant_b);

  delete from public.applications
  where tenant_id in (v_tenant_a, v_tenant_b);

  delete from public.candidates
  where tenant_id in (v_tenant_a, v_tenant_b);

  delete from public.job_stages
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
