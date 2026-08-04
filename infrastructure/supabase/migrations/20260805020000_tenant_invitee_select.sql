-- Allow invited users to read the organization name for their pending invite.

drop policy if exists tenants_select_member on public.tenants;

create policy tenants_select_member on public.tenants
  for select to authenticated
  using (
    id in (select public.current_tenant_ids())
    or exists (
      select 1
      from public.tenant_invites ti
      where ti.tenant_id = tenants.id
        and ti.status = 'pending'
        and ti.email = (select u.email from public.users u where u.id = auth.uid())
    )
  );
