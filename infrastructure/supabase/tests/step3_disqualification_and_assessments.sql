-- Focused tests: Step 3 — disqualification, skip-ack Move Stage, assessments
-- Run after 20260805070000_step3_disqualification_and_assessments.sql is applied.
--
-- Self-cleaning harness: entire fixture + assertions run inside one transaction.
-- Assertion failure → exception → non-zero exit (transaction aborts).
-- All assertions pass → ROLLBACK discards fixtures (no privileged cleanup,
-- no session_replication_role, no hireflow.* maintenance bypasses).
--
-- Run with a multi-statement SQL client on one connection, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f step3_disqualification_and_assessments.sql
-- Note: `supabase db query` uses prepared statements and cannot run this script.

begin;

do $$
declare
  v_tenant uuid := gen_random_uuid();
  v_user uuid := gen_random_uuid();
  v_job uuid := gen_random_uuid();
  v_candidate uuid := gen_random_uuid();
  v_candidate_2 uuid := gen_random_uuid();
  v_applied uuid := gen_random_uuid();
  v_review uuid := gen_random_uuid();
  v_filter uuid := gen_random_uuid();
  v_interview uuid := gen_random_uuid();
  v_hired_stage uuid := gen_random_uuid();
  v_app_id uuid;
  v_app public.applications;
  v_stage_id uuid;
  v_category_id uuid;
  v_dq_id uuid;
  v_template_id uuid;
  v_version_1 uuid;
  v_version_2 uuid;
  v_field_v1 uuid;
  v_field_v2 uuid;
  v_assessment_id uuid;
  v_answer public.interview_assessment_answers;
  v_meta jsonb;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user,
    'authenticated',
    'authenticated',
    'hf-step3-' || replace(v_user::text, '-', '') || '@example.test',
    crypt('not-used', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

  insert into public.tenants (id, name, slug)
  values (v_tenant, 'HF Step3', 'hf-step3-' || replace(v_tenant::text, '-', ''));

  perform public.seed_disqualification_categories(v_tenant);

  insert into public.tenant_memberships (tenant_id, user_id, role, status)
  values (v_tenant, v_user, 'recruiter', 'active');

  insert into public.jobs (id, tenant_id, title, status)
  values (v_job, v_tenant, 'Step3 Job', 'open');

  insert into public.job_stages (
    id, tenant_id, job_id, key, name, sort_order, color, category, is_applied_entry
  ) values
    (v_applied, v_tenant, v_job, 'applied', 'Applied', 1, '#64748B', 'intake', true),
    (v_review, v_tenant, v_job, 'review', 'Review', 2, '#0EA5E9', 'screening', false),
    (v_filter, v_tenant, v_job, 'filter', 'Filter', 3, '#06B6D4', 'screening', false),
    (v_interview, v_tenant, v_job, 'interview', 'Interview', 4, '#8B5CF6', 'interview', false),
    (v_hired_stage, v_tenant, v_job, 'hired', 'Hired', 5, '#0F6B4C', 'hired', false);

  insert into public.candidates (id, tenant_id, full_name, email)
  values
    (
      v_candidate, v_tenant, 'Step3 Cand',
      'step3-' || replace(v_candidate::text, '-', '') || '@example.test'
    ),
    (
      v_candidate_2, v_tenant, 'Step3 Cand 2',
      'step3b-' || replace(v_candidate_2::text, '-', '') || '@example.test'
    );

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );

  insert into public.applications (tenant_id, job_id, candidate_id, status)
  values (v_tenant, v_job, v_candidate, 'active')
  returning id into v_app_id;

  -- -----------------------------------------------------------------------
  -- forward skip without ack rejected; with ack succeeds + metadata
  -- -----------------------------------------------------------------------
  begin
    perform public.transition_application_stage(
      v_tenant, v_app_id, v_interview, null, null, false
    );
    raise exception 'FAIL: forward skip without ack should be rejected';
  exception
    when others then
      if sqlerrm not like '%skip acknowledgement required%' then
        raise;
      end if;
  end;

  v_app := public.transition_application_stage(
    v_tenant, v_app_id, v_interview, 'Skip ahead', null, true
  );

  if v_app.current_job_stage_id is distinct from v_interview then
    raise exception 'FAIL: skip-ack transition should land on Interview';
  end if;

  select metadata into v_meta
  from public.application_stage_events
  where application_id = v_app_id
    and event_type = 'transition'
  order by occurred_at desc
  limit 1;

  if coalesce(v_meta->>'movement', '') is distinct from 'forward_skip'
    or jsonb_array_length(v_meta->'skipped_stages') < 1
    or coalesce((v_meta->>'skip_acknowledged')::boolean, false) is not true
  then
    raise exception 'FAIL: skip metadata missing/incorrect: %', v_meta;
  end if;

  -- -----------------------------------------------------------------------
  -- backward move does not require skip ack
  -- -----------------------------------------------------------------------
  v_app := public.transition_application_stage(
    v_tenant, v_app_id, v_applied, null, null, false
  );

  if v_app.current_job_stage_id is distinct from v_applied then
    raise exception 'FAIL: backward move should succeed without skip ack';
  end if;

  select metadata into v_meta
  from public.application_stage_events
  where application_id = v_app_id
    and event_type = 'transition'
  order by occurred_at desc
  limit 1;

  if coalesce(v_meta->>'movement', '') is distinct from 'backward' then
    raise exception 'FAIL: expected backward movement metadata';
  end if;

  v_app := public.transition_application_stage(
    v_tenant, v_app_id, v_interview, null, null, true
  );

  begin
    perform public.transition_application_stage(
      v_tenant, v_app_id, v_hired_stage, null, null, true
    );
    raise exception 'FAIL: hired stage via Move Stage should be rejected';
  exception
    when others then
      if sqlerrm not like '%lifecycle-terminal%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- disqualify: require reason; retain stage; set status
  -- -----------------------------------------------------------------------
  select id into v_category_id
  from public.disqualification_categories
  where tenant_id = v_tenant
    and key = 'skills_mismatch';

  begin
    perform public.disqualify_application(
      v_tenant, v_app_id, v_category_id, '   '
    );
    raise exception 'FAIL: empty DQ reason should be rejected';
  exception
    when others then
      if sqlerrm not like '%Detailed disqualification reason%' then
        raise;
      end if;
  end;

  v_stage_id := v_app.current_job_stage_id;

  v_app := public.disqualify_application(
    v_tenant, v_app_id, v_category_id, 'Missing required React experience'
  );

  if v_app.status is distinct from 'disqualified'
    or v_app.current_job_stage_id is distinct from v_stage_id
    or v_app.current_job_stage_id is distinct from v_interview
  then
    raise exception 'FAIL: DQ should set status and retain last stage';
  end if;

  select id into v_dq_id
  from public.application_disqualifications
  where application_id = v_app_id;

  if v_dq_id is null then
    raise exception 'FAIL: DQ fact row missing';
  end if;

  begin
    update public.application_disqualifications
    set detailed_reason = 'tamper'
    where id = v_dq_id;
    raise exception 'FAIL: DQ update should be append-only rejected';
  exception
    when others then
      if sqlerrm not like '%append-only%' then
        raise;
      end if;
  end;

  begin
    perform public.transition_application_stage(
      v_tenant, v_app_id, v_review, null, null, true
    );
    raise exception 'FAIL: Move Stage on disqualified app should fail';
  exception
    when others then
      if sqlerrm not like '%Only active applications%' then
        raise;
      end if;
  end;

  begin
    perform public.disqualify_application(
      v_tenant, v_app_id, v_category_id, 'Again'
    );
    raise exception 'FAIL: second DQ on non-active should fail';
  exception
    when others then
      if sqlerrm not like '%Only active applications%' then
        raise;
      end if;
  end;

  -- -----------------------------------------------------------------------
  -- Assessment draft editable → publish immutable → V2 draft → publish
  -- Finalized V1 snapshots preserved (History Never Lies)
  -- -----------------------------------------------------------------------
  insert into public.applications (tenant_id, job_id, candidate_id, status)
  values (v_tenant, v_job, v_candidate_2, 'active')
  returning id into v_app_id;

  insert into public.assessment_templates (id, tenant_id, name, created_by)
  values (gen_random_uuid(), v_tenant, 'Interview assessment', v_user)
  returning id into v_template_id;

  -- Create V1 as DRAFT
  insert into public.assessment_template_versions (
    id, tenant_id, template_id, version_number, status
  ) values (
    gen_random_uuid(), v_tenant, v_template_id, 1, 'draft'
  )
  returning id into v_version_1;

  insert into public.assessment_template_fields (
    id, tenant_id, template_version_id, key, label, field_type, field_config, sort_order, is_required
  ) values (
    gen_random_uuid(),
    v_tenant,
    v_version_1,
    'strength',
    'Primary strength',
    'single_select',
    '{"options":[{"key":"comm","label":"Communication"},{"key":"tech","label":"Technical"}]}'::jsonb,
    1,
    true
  )
  returning id into v_field_v1;

  -- Edit V1 draft field successfully
  update public.assessment_template_fields
  set label = 'Core strength',
      field_config = '{"options":[{"key":"comm","label":"Communication"},{"key":"tech","label":"Technical depth"}]}'::jsonb
  where id = v_field_v1;

  -- Add / remove / reorder while V1 is draft
  insert into public.assessment_template_fields (
    id, tenant_id, template_version_id, key, label, field_type, field_config, sort_order, is_required
  ) values (
    gen_random_uuid(), v_tenant, v_version_1, 'notes', 'Notes', 'long_text', '{}'::jsonb, 2, false
  );

  delete from public.assessment_template_fields
  where template_version_id = v_version_1
    and key = 'notes';

  -- Reorder: move strength to sort_order 2 via temp unique dodge
  update public.assessment_template_fields
  set sort_order = 99
  where id = v_field_v1;

  insert into public.assessment_template_fields (
    id, tenant_id, template_version_id, key, label, field_type, field_config, sort_order, is_required
  ) values (
    gen_random_uuid(), v_tenant, v_version_1, 'warmup', 'Warm-up', 'text', '{}'::jsonb, 1, false
  );

  update public.assessment_template_fields
  set sort_order = 2
  where id = v_field_v1;

  -- Assessments cannot be created from a draft version
  begin
    perform public.create_interview_assessment(v_tenant, v_app_id, v_version_1, null);
    raise exception 'FAIL: create assessment from draft V1 should fail';
  exception
    when others then
      if sqlerrm not like '%published%' then
        raise;
      end if;
  end;

  -- Publish V1
  perform public.publish_assessment_template_version(v_tenant, v_version_1);

  -- Published V1 UPDATE/DELETE must fail
  begin
    update public.assessment_template_fields
    set label = 'Should fail'
    where id = v_field_v1;
    raise exception 'FAIL: published V1 field update should fail';
  exception
    when others then
      if sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  begin
    delete from public.assessment_template_fields where id = v_field_v1;
    raise exception 'FAIL: published V1 field delete should fail';
  exception
    when others then
      if sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  begin
    update public.assessment_template_versions
    set notes = 'tamper'
    where id = v_version_1;
    raise exception 'FAIL: published V1 version update should fail';
  exception
    when others then
      if sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  begin
    delete from public.assessment_template_versions where id = v_version_1;
    raise exception 'FAIL: published V1 version delete should fail';
  exception
    when others then
      if sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  -- Complete + finalize assessment from published V1
  v_assessment_id := (
    public.create_interview_assessment(v_tenant, v_app_id, v_version_1, null)
  ).id;

  perform public.save_interview_assessment_answers(
    v_tenant,
    v_assessment_id,
    jsonb_build_array(
      jsonb_build_object(
        'template_field_id', v_field_v1,
        'value', '"comm"'::jsonb
      )
    )
  );

  perform public.finalize_interview_assessment(v_tenant, v_assessment_id);

  select * into v_answer
  from public.interview_assessment_answers
  where assessment_id = v_assessment_id
    and field_key = 'strength';

  if v_answer.field_label is distinct from 'Core strength'
    or v_answer.field_config->'options'->1->>'label' is distinct from 'Technical depth'
    or v_answer.value #>> '{}' is distinct from 'comm'
  then
    raise exception 'FAIL: V1 finalized snapshots incomplete: %', v_answer;
  end if;

  -- Create V2 as a NEW draft; edit successfully; publish
  insert into public.assessment_template_versions (
    id, tenant_id, template_id, version_number, status
  ) values (
    gen_random_uuid(), v_tenant, v_template_id, 2, 'draft'
  )
  returning id into v_version_2;

  insert into public.assessment_template_fields (
    id, tenant_id, template_version_id, key, label, field_type, field_config, sort_order, is_required
  ) values (
    gen_random_uuid(),
    v_tenant,
    v_version_2,
    'strength',
    'V2 draft label',
    'single_select',
    '{"options":[{"key":"comm","label":"Communication"}]}'::jsonb,
    1,
    true
  )
  returning id into v_field_v2;

  update public.assessment_template_fields
  set label = 'Renamed strength (V2)',
      field_config = '{"options":[{"key":"comm","label":"CHANGED"},{"key":"lead","label":"Leadership"}]}'::jsonb
  where id = v_field_v2;

  perform public.publish_assessment_template_version(v_tenant, v_version_2);

  begin
    update public.assessment_template_fields
    set label = 'post-publish edit'
    where id = v_field_v2;
    raise exception 'FAIL: published V2 field update should fail';
  exception
    when others then
      if sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  -- Finalized V1 assessment still preserves V1 snapshots
  select field_label, field_config, value
  into v_answer.field_label, v_answer.field_config, v_answer.value
  from public.interview_assessment_answers
  where assessment_id = v_assessment_id
    and field_key = 'strength';

  if v_answer.field_label is distinct from 'Core strength'
    or v_answer.field_config->'options'->1->>'label' is distinct from 'Technical depth'
    or v_answer.value #>> '{}' is distinct from 'comm'
  then
    raise exception 'FAIL: finalized V1 snapshots must survive V2 publish';
  end if;

  if exists (
    select 1
    from public.interview_assessments
    where id = v_assessment_id
      and template_version_id is distinct from v_version_1
  ) then
    raise exception 'FAIL: finalized assessment must remain bound to V1';
  end if;

  begin
    perform public.save_interview_assessment_answers(
      v_tenant,
      v_assessment_id,
      jsonb_build_array(
        jsonb_build_object('template_field_id', v_field_v1, 'value', '"tech"'::jsonb)
      )
    );
    raise exception 'FAIL: editing finalized assessment answers should fail';
  exception
    when others then
      if sqlerrm not like '%draft%' and sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  begin
    update public.interview_assessments
    set status = 'draft'
    where id = v_assessment_id;
    raise exception 'FAIL: finalized assessment row should be immutable';
  exception
    when others then
      if sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  raise notice 'PASS: step3_disqualification_and_assessments tests';
end;
$$;

rollback;
