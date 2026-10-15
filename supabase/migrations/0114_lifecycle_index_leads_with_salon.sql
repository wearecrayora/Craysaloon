-- 0114 The index-scope gate caught 0113: lifecycle_messages' once-a-year
-- constraint led with customer_id. Every composite index on a tenant table
-- leads with salon_id (RULES 3; rls/index_scope_test.sql), so it is rebuilt
-- that way, and the birthday scan's conflict target follows it.

alter table public.lifecycle_messages drop constraint if exists lifecycle_messages_once;
alter table public.lifecycle_messages
  add constraint lifecycle_messages_once unique (salon_id, customer_id, kind, period);

do $patch$
declare
  v_def text := pg_get_functiondef('app.queue_birthday_offers(uuid)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def, 'on conflict (customer_id, kind, period) do nothing',
                          'on conflict (salon_id, customer_id, kind, period) do nothing');
  if v_new = v_def then
    raise exception '0114: queue_birthday_offers moved - the conflict target was not updated';
  end if;
  execute v_new;
end;
$patch$;
