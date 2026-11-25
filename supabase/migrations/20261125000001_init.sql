-- wow-chat initial schema
-- Multi-tenant, end-to-end encrypted messenger.
-- The database is ZERO-KNOWLEDGE for message content: it stores ciphertext + routing
-- metadata + public keys only. Private keys never leave the user's device.
--
-- Every table carries tenant_id and is guarded by Row-Level Security so one tenant can
-- never read another tenant's rows, even with a leaked anon key.

-- ───────────────────────── extensions ─────────────────────────
create extension if not exists "pgcrypto";

-- ───────────────────────── tenants ─────────────────────────
create table public.tenants (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,              -- short tenant code
  name        text not null,
  created_at  timestamptz not null default now()
);

-- Maps an auth user to a tenant + their in-app profile.
-- No plaintext name/phone is required; display_name is user-chosen and may be a handle.
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  handle        text not null,                   -- unique within a tenant
  display_name  text,
  avatar_path   text,                            -- path to ciphertext blob in Storage
  created_at    timestamptz not null default now(),
  unique (tenant_id, handle)
);

-- ───────────────────────── device keys (for E2E) ─────────────────────────
-- Public identity + signed prekey + one-time prekeys for X3DH. PUBLIC keys only.
create table public.device_keys (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  user_id            uuid not null references auth.users(id) on delete cascade,
  device_id          text not null,
  registration_id    integer not null,
  identity_key       text not null,              -- base64 public identity key
  signed_prekey_id   integer not null,
  signed_prekey_pub  text not null,
  signed_prekey_sig  text not null,
  created_at         timestamptz not null default now(),
  unique (user_id, device_id)
);

create table public.one_time_prekeys (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  device_id   text not null,
  prekey_id   integer not null,
  prekey_pub  text not null,                     -- base64 public one-time prekey
  consumed    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ───────────────────────── conversations ─────────────────────────
create table public.conversations (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  is_group    boolean not null default false,
  title_enc   text,                              -- ciphertext (group title), nullable
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  role            text not null default 'member',   -- member | admin
  joined_at       timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ───────────────────────── messages (ciphertext) ─────────────────────────
-- body_enc holds the Double-Ratchet ciphertext. The server cannot read it.
-- expires_at supports disappearing messages (deleted by a scheduled job + client).
create table public.messages (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  conversation_id  uuid not null references public.conversations(id) on delete cascade,
  sender_id        uuid not null references auth.users(id) on delete cascade,
  body_enc         text not null,                -- ciphertext envelope (base64)
  media_path       text,                         -- Storage path to ciphertext media, nullable
  media_meta_enc   text,                         -- ciphertext of media metadata (name/type/key)
  created_at       timestamptz not null default now(),
  expires_at       timestamptz                   -- disappearing message TTL, nullable
);
create index on public.messages (conversation_id, created_at desc);
create index on public.messages (expires_at) where expires_at is not null;

-- ───────────────────────── call signaling ─────────────────────────
-- Short-lived WebRTC signaling rows. SDP/ICE are also E2E-encrypted client-side.
create table public.call_signals (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  conversation_id  uuid not null references public.conversations(id) on delete cascade,
  from_user        uuid not null references auth.users(id) on delete cascade,
  to_user          uuid not null references auth.users(id) on delete cascade,
  kind             text not null,                -- offer | answer | ice | hangup
  payload_enc      text not null,                -- ciphertext SDP/ICE
  created_at       timestamptz not null default now()
);
create index on public.call_signals (to_user, created_at desc);

-- ───────────────────────── privacy settings ─────────────────────────
-- Per-user privacy controls surfaced on the Settings page. Values are small flags/enums;
-- nothing sensitive, but still tenant-isolated.
create table public.privacy_settings (
  user_id              uuid primary key references auth.users(id) on delete cascade,
  tenant_id            uuid not null references public.tenants(id) on delete cascade,
  last_seen_visible    boolean not null default false,
  read_receipts        boolean not null default false,
  typing_indicators    boolean not null default false,
  profile_photo_scope  text not null default 'contacts',  -- everyone|contacts|nobody
  default_msg_ttl_sec  integer not null default 0,        -- 0 = off (disappearing msgs)
  block_screenshots    boolean not null default true,     -- FLAG_SECURE
  app_lock             boolean not null default true,     -- biometric/PIN to open
  updated_at           timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────
--                          ROW-LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────────────────
-- Helper: the caller's tenant, read from their profile.
create or replace function public.current_tenant_id()
returns uuid language sql stable security definer set search_path = public as $$
  select tenant_id from public.profiles where id = auth.uid()
$$;

-- Helper: is the caller a member of a conversation?
create or replace function public.is_member(conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv and user_id = auth.uid()
  )
$$;

alter table public.tenants              enable row level security;
alter table public.profiles             enable row level security;
alter table public.device_keys          enable row level security;
alter table public.one_time_prekeys     enable row level security;
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;
alter table public.call_signals         enable row level security;
alter table public.privacy_settings     enable row level security;

-- tenants: a user may read only their own tenant.
create policy tenant_read on public.tenants
  for select using (id = public.current_tenant_id());

-- profiles: read profiles within your tenant; write only your own row.
create policy profiles_read on public.profiles
  for select using (tenant_id = public.current_tenant_id());
create policy profiles_write_self on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid() and tenant_id = public.current_tenant_id());

-- device_keys / one_time_prekeys: readable within tenant (needed to start a session);
-- writable only by the owner.
create policy keys_read on public.device_keys
  for select using (tenant_id = public.current_tenant_id());
create policy keys_write_self on public.device_keys
  for all using (user_id = auth.uid()) with check (user_id = auth.uid() and tenant_id = public.current_tenant_id());

create policy prekeys_read on public.one_time_prekeys
  for select using (tenant_id = public.current_tenant_id());
create policy prekeys_write_self on public.one_time_prekeys
  for all using (user_id = auth.uid()) with check (user_id = auth.uid() and tenant_id = public.current_tenant_id());

-- conversations: only members can see; creator must be in-tenant.
create policy conv_read on public.conversations
  for select using (tenant_id = public.current_tenant_id() and public.is_member(id));
create policy conv_insert on public.conversations
  for insert with check (tenant_id = public.current_tenant_id() and created_by = auth.uid());

-- members: a member can read the roster; inserts are constrained to your tenant.
create policy members_read on public.conversation_members
  for select using (tenant_id = public.current_tenant_id() and public.is_member(conversation_id));
create policy members_write on public.conversation_members
  for all using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

-- messages: only members of the conversation can read; sender must be the caller.
create policy messages_read on public.messages
  for select using (tenant_id = public.current_tenant_id() and public.is_member(conversation_id));
create policy messages_insert on public.messages
  for insert with check (
    tenant_id = public.current_tenant_id()
    and sender_id = auth.uid()
    and public.is_member(conversation_id)
  );
-- senders may delete their own messages (and TTL job deletes expired ones).
create policy messages_delete_own on public.messages
  for delete using (tenant_id = public.current_tenant_id() and sender_id = auth.uid());

-- call signals: visible to the two parties only.
create policy signals_rw on public.call_signals
  for select using (tenant_id = public.current_tenant_id() and (to_user = auth.uid() or from_user = auth.uid()));
create policy signals_insert on public.call_signals
  for insert with check (tenant_id = public.current_tenant_id() and from_user = auth.uid());

-- privacy settings: a user reads/writes only their own.
create policy privacy_self on public.privacy_settings
  for all using (user_id = auth.uid()) with check (user_id = auth.uid() and tenant_id = public.current_tenant_id());
