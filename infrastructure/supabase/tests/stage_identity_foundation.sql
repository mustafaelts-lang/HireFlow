-- Focused tests: Architecture Hardening Step 2 — stage identity foundation
-- Run only after migration 20260805060000_stage_identity_foundation.sql is applied.

do $$
declare
  v_tenant uuid := gen_random_uuid();
  v_tenant_b uuid := gen_random_uuid();
  v_user uuid := gen_random_uuid();
  v_job uuid := gen_random_uuid();
  v_job_b uuid := gen_random_uuid();
  v_candidate uuid := gen_random_uuid();
  v_applied uuid := gen_random_uuid();
  v_review uuid := gen_random_uuid();
  v_hired uuid := gen_random_uuid();
  v_withdrawn uuid := gen_random_uuid();
  v_other_job_stage uuid := gen_random_uuid();
  v_app public.applications;
  v_app_id uuid;
  v_event public.application_stage_events;
  v_event_name text;
  v_status text;
  v_occurred_at timestamptz;
  v_created_at timestamptz;
begin
  -- Auth user for transition RPC (has_tenant_role uses auth.uid())
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user,
    'authenticated',
    'authenticated',
    'hf-step2-' || replace(v_user::text, '-', '') || '@example.test',
    crypt('not-used', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

  insert into public.tenants (id, name, slug)
  values
    (v_tenant, 'HF Step2 Tenant', 'hf-step2-' || replace(v_tenant::text, '-', '')),
    (v_tenant_b, 'HF Step2 Tenant B', 'hf-step2b-' || replace(v_tenant_b::text, '-', ''));

  insert into public.tenant_memberships (tenant_id, user_id, role, status)
  values (v_tenant, v_user, 'recruiter', 'active');

  insert into public.jobs (id, tenant_id, title, status)
  values
    (v_job, v_tenant, 'Step2 Job', 'open'),
    (v_job_b, v_tenant_b, 'Step2 Job B', 'open');

  insert into public.job_stages (
    id, tenant_id, job_id, key, name, sort_order, color, category, is_applied_entry
  ) values
    (v_applied, v_tenant, v_job, 'applied', 'Applied', 1, '#64748B', 'intake', true),
    (v_review, v_tenant, v_job, 'review', 'Review', 2, '#0EA5E9', 'screening', false),
    (v_hired, v_tenant, v_job, 'hired', 'Hired', 3, '#0F6B4C', 'hired', false),
    (v_withdrawn, v_tenant, v_job, 'withdrawn', 'Withdrawn', 4, '#78716C', 'closed', false),
    (v_other_job_stage, v_tenant_b, v_job_b, 'applied', 'Applied', 1, '#64748B', 'intake', true);

  insert into public.candidates (id, tenant_id, full_name, email)
  values (
    v_candidate,
    v_tenant,
    'Step2 Candidate',
    'step2-' || replace(v_candidate::text, '-', '') || '@example.test'
  );

  perform set_config(
    'request.jwt.claim.sub',
    v_user::text,
    true
  );
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );

  -- -----------------------------------------------------------------------
  -- create application → Applied entry + initial event snapshots
  -- -----------------------------------------------------------------------
  insert into public.applications (
    tenant_id, job_id, candidate_id, status, submitted_via
  ) values (
    v_tenant, v_job, v_candidate, 'active', 'manual'
  )
  returning * into v_app;

  v_app_id := v_app.id;
  v_created_at := v_app.created_at;

  if v_app.current_job_stage_id is distinct from v_applied then
    raise exception 'FAIL: new application must land on Applied entry stage';
  end if;

  select * into v_event
  from public.application_stage_events
  where application_id = v_app_id;

  if v_event.event_type is distinct from 'initial'
    or v_event.to_job_stage_id is distinct from v_applied
    or v_event.to_stage_key is distinct from 'applied'
    or v_event.to_stage_name is distinct from 'Applied'
    or v_event.job_id is distinct from v_job
  then
    raise exception 'FAIL: initial event missing/incorrect snapshots';
  end if;

  -- -----------------------------------------------------------------------
  -- second applied-entry unique + create in non-applied rejected
  -- -----------------------------------------------------------------------
  begin
    insert into public.job_stages (
      tenant_id, job_id, key, name, sort_order, color, category, is_applied_entry
    ) values (
      v_tenant, v_job, 'applied_dup', 'Applied Dup', 9, '#64748B', 'intake', true
    );
    raise exception 'FAIL: second is_applied_entry should be rejected';
  exception
    when unique_violation then
      null;
  end;

  begin
    insert into public.applications (
      tenant_id, job_id, candidate_id, current_job_stage_id, status
    ) values (
      v_tenant, v_job, v_candidate, v_review, 'withdrawn'
    );
    raise exception 'FAIL: insert into non-Applied stage should be rejected';
  exception
    when others then
      if sqlerrm not like '%Applied entry stage%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- transition Applied → Review success; lifecycle unchanged
  -- -----------------------------------------------------------------------
  v_app := public.transition_application_stage(
    v_tenant,
    v_app_id,
    v_review,
    'Move to review',
    null
  );

  -- RPC sets hireflow.stage_transition locally for its UPDATE; clear so later
  -- direct-update assertions in this same transaction are meaningful.
  perform set_config('hireflow.stage_transition', '', true);

  if v_app.current_job_stage_id is distinct from v_review then
    raise exception 'FAIL: transition did not update current_job_stage_id';
  end if;

  select status into v_status
  from public.applications
  where id = v_app_id;

  if v_status is distinct from 'active' then
    raise exception 'FAIL: lifecycle status must not change on stage transition';
  end if;

  select * into v_event
  from public.application_stage_events
  where application_id = v_app_id
    and event_type = 'transition'
  order by occurred_at desc
  limit 1;

  if v_event.from_stage_key is distinct from 'applied'
    or v_event.to_stage_key is distinct from 'review'
    or v_event.to_stage_name is distinct from 'Review'
  then
    raise exception 'FAIL: transition snapshots incorrect';
  end if;

  -- -----------------------------------------------------------------------
  -- rename live stage; historical event name unchanged
  -- -----------------------------------------------------------------------
  v_event_name := v_event.to_stage_name;

  update public.job_stages
  set name = 'Review Renamed'
  where id = v_review;

  select to_stage_name into v_event_name
  from public.application_stage_events
  where id = v_event.id;

  if v_event_name is distinct from 'Review' then
    raise exception 'FAIL: event snapshot name must survive live rename';
  end if;

  -- -----------------------------------------------------------------------
  -- reject other-job stage, terminal stages, direct stage id update
  -- -----------------------------------------------------------------------
  begin
    perform public.transition_application_stage(
      v_tenant, v_app_id, v_other_job_stage, null, null
    );
    raise exception 'FAIL: cross-job stage transition should be rejected';
  exception
    when others then
      if sqlerrm not like '%Destination stage not found%' then
        raise;
      end if;
  end;

  begin
    perform public.transition_application_stage(
      v_tenant, v_app_id, v_hired, null, null
    );
    raise exception 'FAIL: hired terminal stage transition should be rejected';
  exception
    when others then
      if sqlerrm not like '%lifecycle-terminal%' then
        raise;
      end if;
  end;

  begin
    perform public.transition_application_stage(
      v_tenant, v_app_id, v_withdrawn, null, null
    );
    raise exception 'FAIL: withdrawn terminal stage transition should be rejected';
  exception
    when others then
      if sqlerrm not like '%lifecycle-terminal%' then
        raise;
      end if;
  end;

  begin
    update public.applications
    set current_job_stage_id = v_applied
    where id = v_app_id;
    raise exception 'FAIL: direct current_job_stage_id update should be rejected';
  exception
    when others then
      if sqlerrm not like '%transition_application_stage%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- append-only
  -- -----------------------------------------------------------------------
  begin
    update public.application_stage_events
    set note = 'tamper'
    where application_id = v_app_id;
    raise exception 'FAIL: event update should be rejected';
  exception
    when others then
      if sqlerrm not like '%append-only%' then
        raise;
      end if;
  end;

  begin
    delete from public.application_stage_events
    where application_id = v_app_id;
    raise exception 'FAIL: event delete should be rejected';
  exception
    when others then
      if sqlerrm not like '%append-only%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- migration_backfill timestamp semantics (explicit fixture)
  -- -----------------------------------------------------------------------
  perform set_config('hireflow.skip_initial_stage_event', '1', true);
  perform set_config('hireflow.allow_non_applied_insert', '1', true);

  insert into public.applications (
    tenant_id, job_id, candidate_id, current_job_stage_id, status
  ) values (
    v_tenant, v_job, v_candidate, v_applied, 'withdrawn'
  )
  returning id, created_at into v_app_id, v_created_at;

  v_occurred_at := clock_timestamp();

  insert into public.application_stage_events (
    tenant_id, application_id, job_id, event_type,
    to_job_stage_id, to_stage_key, to_stage_name, to_stage_category,
    reason_code, occurred_at, metadata
  ) values (
    v_tenant, v_app_id, v_job, 'migration_backfill',
    v_applied, 'applied', 'Applied', 'intake',
    'migration_snapshot', v_occurred_at,
    jsonb_build_object('application_created_at', v_created_at)
  );

  if exists (
    select 1
    from public.application_stage_events
    where application_id = v_app_id
      and event_type = 'migration_backfill'
      and occurred_at = v_created_at
  ) then
    raise exception 'FAIL: migration_backfill occurred_at must not equal application.created_at';
  end if;

  if not exists (
    select 1
    from public.application_stage_events
    where application_id = v_app_id
      and event_type = 'migration_backfill'
      and occurred_at = v_occurred_at
      and (metadata->>'application_created_at') is not null
  ) then
    raise exception 'FAIL: migration_backfill should keep created_at in metadata only';
  end if;

  -- -----------------------------------------------------------------------
  -- cleanup
  -- -----------------------------------------------------------------------
  perform set_config('hireflow.allow_event_maintenance', '1', true);

  delete from public.application_stage_events
  where tenant_id in (v_tenant, v_tenant_b);

  delete from public.applications
  where tenant_id in (v_tenant, v_tenant_b);

  delete from public.candidates
  where tenant_id in (v_tenant, v_tenant_b);

  delete from public.job_stages
  where tenant_id in (v_tenant, v_tenant_b);

  delete from public.jobs
  where tenant_id in (v_tenant, v_tenant_b);

  delete from public.tenant_memberships
  where tenant_id in (v_tenant, v_tenant_b);

  delete from public.tenants
  where id in (v_tenant, v_tenant_b);

  delete from auth.users
  where id = v_user;

  raise notice 'PASS: stage_identity_foundation tests';
end;
$$;
