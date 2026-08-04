-- HireFlow Sprint 2: multi-tenant foundation (invites + tenant admin RLS)

-- ---------------------------------------------------------------------------
-- Role / permission helpers
-- ---------------------------------------------------------------------------
create or replace function public.has_tenant_role(
  p_tenant_id uuid,
  p_roles text[]
)
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
      and tm.role = any (p_roles)
  );
$$;

create or replace function public.can_manage_tenant_users(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin']::text[]
  );
$$;

create or replace function public.can_write_tenant_settings(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_tenant_role(
    p_tenant_id,
    array['tenant_owner', 'company_admin']::text[]
  );
$$;

-- ---------------------------------------------------------------------------
-- Organization invites (email-based; user linked on accept)
-- ---------------------------------------------------------------------------
create table public.tenant_invites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  email extensions.citext not null,
  role text not null
    check (role in (
      'tenant_owner',
      'company_admin',
      'recruiter',
      'hiring_manager'
    )),
  token text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  invited_by uuid not null references public.users (id),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_user_id uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index tenant_invites_pending_email_uidx
  on public.tenant_invites (tenant_id, email)
  where status = 'pending';

create index tenant_invites_tenant_idx
  on public.tenant_invites (tenant_id, created_at desc);

create trigger tenant_invites_set_updated_at
  before update on public.tenant_invites
  for each row execute function public.set_updated_at();

alter table public.tenant_invites enable row level security;

create policy tenant_invites_select_managers on public.tenant_invites
  for select to authenticated
  using (public.can_manage_tenant_users(tenant_id));

create policy tenant_invites_select_own_email on public.tenant_invites
  for select to authenticated
  using (
    email = (select u.email from public.users u where u.id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- Tenant update policy (settings)
-- ---------------------------------------------------------------------------
create policy tenants_update_admins on public.tenants
  for update to authenticated
  using (public.can_write_tenant_settings(id))
  with check (public.can_write_tenant_settings(id));

-- Allow reading teammate profiles within shared tenants
drop policy if exists users_select_self on public.users;

create policy users_select_self on public.users
  for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.tenant_memberships mine
      join public.tenant_memberships theirs
        on mine.tenant_id = theirs.tenant_id
      where mine.user_id = auth.uid()
        and mine.status = 'active'
        and theirs.user_id = users.id
        and theirs.status in ('active', 'invited')
    )
  );

-- ---------------------------------------------------------------------------
-- Membership visibility for managers + self
-- ---------------------------------------------------------------------------
drop policy if exists tenant_memberships_select_member on public.tenant_memberships;

create policy tenant_memberships_select_member on public.tenant_memberships
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_tenant_member(tenant_id)
  );

-- ---------------------------------------------------------------------------
-- Invite team member (Owner / Admin)
-- ---------------------------------------------------------------------------
create or replace function public.invite_team_member(
  p_tenant_id uuid,
  p_email text,
  p_role text
)
returns public.tenant_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email extensions.citext;
  v_invite public.tenant_invites;
  v_existing_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.can_manage_tenant_users(p_tenant_id) then
    raise exception 'Not allowed to invite members for this organization';
  end if;

  if p_role not in ('company_admin', 'recruiter', 'hiring_manager') then
    raise exception 'Invalid invite role';
  end if;

  v_email := lower(trim(p_email));
  if v_email is null or length(v_email::text) = 0 then
    raise exception 'Email is required';
  end if;

  select id into v_existing_user_id
  from public.users
  where email = v_email;

  if v_existing_user_id is not null then
    if exists (
      select 1
      from public.tenant_memberships tm
      where tm.tenant_id = p_tenant_id
        and tm.user_id = v_existing_user_id
        and tm.status in ('active', 'invited')
    ) then
      raise exception 'User is already a member of this organization';
    end if;
  end if;

  update public.tenant_invites
  set status = 'revoked',
      updated_at = now()
  where tenant_id = p_tenant_id
    and email = v_email
    and status = 'pending';

  insert into public.tenant_invites (
    tenant_id,
    email,
    role,
    token,
    invited_by,
    expires_at,
    status
  )
  values (
    p_tenant_id,
    v_email,
    p_role,
    replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
    auth.uid(),
    now() + interval '14 days',
    'pending'
  )
  returning * into v_invite;

  insert into public.audit_events (
    tenant_id, actor_user_id, action, entity_type, entity_id, metadata
  )
  values (
    p_tenant_id,
    auth.uid(),
    'tenant.member.invited',
    'tenant_invite',
    v_invite.id,
    jsonb_build_object('email', v_email::text, 'role', p_role)
  );

  return v_invite;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accept invite (authenticated user; email must match)
-- ---------------------------------------------------------------------------
create or replace function public.accept_tenant_invite(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.tenant_invites;
  v_user_email extensions.citext;
  v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select email into v_user_email
  from public.users
  where id = auth.uid();

  if v_user_email is null then
    raise exception 'User profile not found';
  end if;

  select * into v_invite
  from public.tenant_invites
  where token = p_token
  for update;

  if v_invite.id is null then
    raise exception 'Invite not found';
  end if;

  if v_invite.status <> 'pending' then
    raise exception 'Invite is no longer pending';
  end if;

  if v_invite.expires_at < now() then
    update public.tenant_invites
    set status = 'expired', updated_at = now()
    where id = v_invite.id;
    raise exception 'Invite has expired';
  end if;

  if v_invite.email <> v_user_email then
    raise exception 'Invite email does not match the signed-in user';
  end if;

  insert into public.tenant_memberships (tenant_id, user_id, role, status)
  values (v_invite.tenant_id, auth.uid(), v_invite.role, 'active')
  on conflict (tenant_id, user_id) do update
    set role = excluded.role,
        status = 'active',
        updated_at = now()
  returning id into v_membership_id;

  update public.tenant_invites
  set status = 'accepted',
      accepted_at = now(),
      accepted_user_id = auth.uid(),
      updated_at = now()
  where id = v_invite.id;

  insert into public.audit_events (
    tenant_id, actor_user_id, action, entity_type, entity_id
  )
  values (
    v_invite.tenant_id,
    auth.uid(),
    'tenant.member.joined',
    'tenant_membership',
    v_membership_id
  );

  return v_invite.tenant_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Revoke invite / membership
-- ---------------------------------------------------------------------------
create or replace function public.revoke_tenant_invite(
  p_tenant_id uuid,
  p_invite_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_tenant_users(p_tenant_id) then
    raise exception 'Not allowed';
  end if;

  update public.tenant_invites
  set status = 'revoked', updated_at = now()
  where id = p_invite_id
    and tenant_id = p_tenant_id
    and status = 'pending';
end;
$$;

create or replace function public.update_member_role(
  p_tenant_id uuid,
  p_membership_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.tenant_memberships;
  v_owner_count int;
begin
  if not public.can_manage_tenant_users(p_tenant_id) then
    raise exception 'Not allowed';
  end if;

  if p_role not in ('tenant_owner', 'company_admin', 'recruiter', 'hiring_manager') then
    raise exception 'Invalid role';
  end if;

  select * into v_target
  from public.tenant_memberships
  where id = p_membership_id
    and tenant_id = p_tenant_id
  for update;

  if v_target.id is null then
    raise exception 'Membership not found';
  end if;

  if v_target.user_id = auth.uid() and p_role <> 'tenant_owner' and v_target.role = 'tenant_owner' then
    select count(*) into v_owner_count
    from public.tenant_memberships
    where tenant_id = p_tenant_id
      and role = 'tenant_owner'
      and status = 'active';
    if v_owner_count <= 1 then
      raise exception 'Cannot demote the only owner';
    end if;
  end if;

  update public.tenant_memberships
  set role = p_role,
      updated_at = now()
  where id = p_membership_id;
end;
$$;

create or replace function public.revoke_member(
  p_tenant_id uuid,
  p_membership_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.tenant_memberships;
  v_owner_count int;
begin
  if not public.can_manage_tenant_users(p_tenant_id) then
    raise exception 'Not allowed';
  end if;

  select * into v_target
  from public.tenant_memberships
  where id = p_membership_id
    and tenant_id = p_tenant_id
  for update;

  if v_target.id is null then
    raise exception 'Membership not found';
  end if;

  if v_target.user_id = auth.uid() then
    raise exception 'Cannot remove yourself';
  end if;

  if v_target.role = 'tenant_owner' then
    select count(*) into v_owner_count
    from public.tenant_memberships
    where tenant_id = p_tenant_id
      and role = 'tenant_owner'
      and status = 'active';
    if v_owner_count <= 1 then
      raise exception 'Cannot remove the only owner';
    end if;
  end if;

  update public.tenant_memberships
  set status = 'revoked',
      updated_at = now()
  where id = p_membership_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Update organization settings
-- ---------------------------------------------------------------------------
create or replace function public.update_tenant_settings(
  p_tenant_id uuid,
  p_name text,
  p_timezone text,
  p_locale text
)
returns public.tenants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant public.tenants;
begin
  if not public.can_write_tenant_settings(p_tenant_id) then
    raise exception 'Not allowed';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Organization name is required';
  end if;

  update public.tenants
  set name = trim(p_name),
      timezone = coalesce(nullif(trim(p_timezone), ''), timezone),
      locale = coalesce(nullif(trim(p_locale), ''), locale),
      updated_at = now()
  where id = p_tenant_id
  returning * into v_tenant;

  return v_tenant;
end;
$$;

grant execute on function public.has_tenant_role(uuid, text[]) to authenticated, service_role;
grant execute on function public.can_manage_tenant_users(uuid) to authenticated, service_role;
grant execute on function public.can_write_tenant_settings(uuid) to authenticated, service_role;
grant execute on function public.invite_team_member(uuid, text, text) to authenticated, service_role;
grant execute on function public.accept_tenant_invite(text) to authenticated, service_role;
grant execute on function public.revoke_tenant_invite(uuid, uuid) to authenticated, service_role;
grant execute on function public.update_member_role(uuid, uuid, text) to authenticated, service_role;
grant execute on function public.revoke_member(uuid, uuid) to authenticated, service_role;
grant execute on function public.update_tenant_settings(uuid, text, text, text) to authenticated, service_role;

grant select on public.tenant_invites to authenticated;
grant all on public.tenant_invites to service_role;
