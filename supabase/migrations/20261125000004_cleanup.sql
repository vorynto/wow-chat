-- Disappearing messages: server-side cleanup of expired rows.
--
-- Messages with expires_at in the past are deleted. Clients also hide expired messages
-- immediately (so they disappear even between cleanup runs).

create or replace function public.delete_expired_messages()
returns integer language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from public.messages
  where expires_at is not null and expires_at < now();
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Schedule it every 5 minutes IF pg_cron is available on this project. If not, run
-- delete_expired_messages() from an Edge Function on a schedule, or call it from the client.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'wowchat-expire-messages',
      '*/5 * * * *',
      $cron$ select public.delete_expired_messages(); $cron$
    );
  end if;
exception when others then
  -- pg_cron not usable; ignore. Cleanup can be scheduled another way.
  null;
end;
$$;

-- NOTE: expired media objects in Storage are not removed by this SQL (Storage deletion isn't
-- transactional with SQL). Delete them from an Edge Function that lists the tenant/conversation
-- prefix and removes objects whose message row no longer exists, or on a schedule.
