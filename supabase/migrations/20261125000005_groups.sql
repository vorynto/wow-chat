-- Group messaging with Signal "sender keys".
--
-- Each sender has a per-group sender key. The sender distributes a SenderKeyDistributionMessage
-- (SKDM) to every member over the existing pairwise (1:1) encrypted channel, then encrypts each
-- group message ONCE with its sender key. The server stores only group ciphertext + metadata.

-- The sending device, needed to address the sender key on the receiving side. Non-secret
-- (a random per-install id). Harmless for 1:1 messages.
alter table public.messages add column if not exists sender_device text;

-- Pairwise-encrypted delivery of SKDMs to each member.
create table public.sender_key_distributions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  conversation_id  uuid not null references public.conversations(id) on delete cascade,
  from_user        uuid not null references auth.users(id) on delete cascade,
  from_device      text not null,
  to_user          uuid not null references auth.users(id) on delete cascade,
  skdm_enc         text not null,                -- 1:1 ciphertext of the serialized SKDM
  created_at       timestamptz not null default now()
);
create index on public.sender_key_distributions (to_user, created_at desc);

alter table public.sender_key_distributions enable row level security;

-- Visible to the two parties; insert only as yourself, within your tenant + a group you're in.
create policy skdm_read on public.sender_key_distributions
  for select using (
    tenant_id = public.current_tenant_id() and (to_user = auth.uid() or from_user = auth.uid())
  );
create policy skdm_insert on public.sender_key_distributions
  for insert with check (
    tenant_id = public.current_tenant_id()
    and from_user = auth.uid()
    and public.is_member(conversation_id)
  );
