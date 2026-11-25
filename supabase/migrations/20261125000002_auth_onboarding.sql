-- Auth & tenant onboarding.
--
-- Tenant assignment MUST NOT be client-controlled: a user may not simply claim any
-- tenant_id. We route profile creation through SECURITY DEFINER RPCs that validate an
-- invite code and create the profile + default privacy settings atomically.

-- ───────────────────────── tenant invites ─────────────────────────
create table public.tenant_invites (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  code        text not null,
  max_uses    integer,                       -- null = unlimited
  uses        integer not null default 0,
  expires_at  timestamptz,                   -- null = never
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  unique (tenant_id, code)
);
alter table public.tenant_invites enable row level security;

-- Only members of the tenant can see/manage its invites (admins in practice).
create policy invites_read on public.tenant_invites
  for select using (tenant_id = public.current_tenant_id());
create policy invites_write on public.tenant_invites
  for all using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

-- ───────────────────────── create a new tenant (workspace) ─────────────────────────
-- Any signed-in user with no profile yet can create a tenant and become its first member.
create or replace function public.create_tenant(
  p_slug text,
  p_name text,
  p_handle text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'profile already exists';
  end if;

  insert into public.tenants (slug, name)
  values (lower(p_slug), p_name)
  returning id into v_tenant;

  insert into public.profiles (id, tenant_id, handle)
  values (v_uid, v_tenant, p_handle);

  insert into public.privacy_settings (user_id, tenant_id)
  values (v_uid, v_tenant);

  return v_tenant;
end;
$$;

-- ───────────────────────── join an existing tenant by invite ─────────────────────────
create or replace function public.join_tenant(
  p_slug text,
  p_invite_code text,
  p_handle text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_invite public.tenant_invites%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'profile already exists';
  end if;

  select id into v_tenant from public.tenants where slug = lower(p_slug);
  if v_tenant is null then
    raise exception 'unknown tenant';
  end if;

  select * into v_invite
  from public.tenant_invites
  where tenant_id = v_tenant and code = p_invite_code
  for update;

  if v_invite.id is null then
    raise exception 'invalid invite';
  end if;
  if v_invite.expires_at is not null and v_invite.expires_at < now() then
    raise exception 'invite expired';
  end if;
  if v_invite.max_uses is not null and v_invite.uses >= v_invite.max_uses then
    raise exception 'invite exhausted';
  end if;

  insert into public.profiles (id, tenant_id, handle)
  values (v_uid, v_tenant, p_handle);

  insert into public.privacy_settings (user_id, tenant_id)
  values (v_uid, v_tenant);

  update public.tenant_invites set uses = uses + 1 where id = v_invite.id;

  return v_tenant;
end;
$$;

-- Create an invite for the caller's tenant (handy for admins). Returns the code.
create or replace function public.create_invite(
  p_code text,
  p_max_uses integer default null,
  p_expires_at timestamptz default null
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid := public.current_tenant_id();
begin
  if v_tenant is null then
    raise exception 'no tenant';
  end if;
  insert into public.tenant_invites (tenant_id, code, max_uses, expires_at, created_by)
  values (v_tenant, p_code, p_max_uses, p_expires_at, v_uid);
  return p_code;
end;
$$;

grant execute on function public.create_tenant(text, text, text) to authenticated;
grant execute on function public.join_tenant(text, text, text) to authenticated;
grant execute on function public.create_invite(text, integer, timestamptz) to authenticated;
