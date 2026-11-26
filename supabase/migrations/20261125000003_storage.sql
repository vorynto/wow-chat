-- Private Storage bucket for end-to-end-encrypted media. Only CIPHERTEXT is ever uploaded
-- here (files are encrypted client-side before upload). Objects are namespaced by tenant:
--   <tenant_id>/<conversation_id>/<file>.bin
-- and RLS restricts access to the uploader's own tenant.

insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;

-- Read objects only within your own tenant's folder.
create policy "media tenant read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = public.current_tenant_id()::text
  );

-- Upload only into your own tenant's folder.
create policy "media tenant insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = public.current_tenant_id()::text
  );

-- Allow deleting your own tenant's objects (e.g. disappearing-media cleanup).
create policy "media tenant delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = public.current_tenant_id()::text
  );
