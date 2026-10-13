-- 0103 One customer's missing or malformed number never stops a salon's batch.
--
-- Found by the negative control on 0102, 13 Oct 2026: claim_notification_batch
-- called app.canonical_phone() on every SMS and WhatsApp row, and
-- canonical_phone RAISES on an empty or malformed number. One customer with no
-- phone on file - a customer bound before phones were kept, a staff row - made
-- the whole RETURN QUERY fail, so every message queued for that salon, push
-- included, stopped going out.
--
-- Now a number that will not canonicalise is NO number for that row: the
-- dispatcher records `no_phone` against that one delivery and sends the rest.

create or replace function app.phone_or_null(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_phone is null or btrim(p_phone) = '' then
    return null;
  end if;
  return app.canonical_phone(p_phone);
exception when others then
  -- Malformed. Not this function's job to say why - the delivery records
  -- `no_phone`, and the batch carries on.
  return null;
end;
$$;

comment on function app.phone_or_null(text) is
  'canonical_phone that answers NULL instead of raising, for the dispatch batch - one bad number must not stop a salon''s messages (0103).';

revoke all on function app.phone_or_null(text) from public, anon, authenticated;

do $$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('app.claim_notification_batch(uuid, integer)'::regprocedure);
  v_new := replace(v_def,
    'then app.canonical_phone(coalesce(cu.phone, us.phone)) end',
    'then app.phone_or_null(coalesce(cu.phone, us.phone)) end');
  if v_new = v_def then
    raise exception '0103: claim_notification_batch did not change';
  end if;
  execute v_new;
end;
$$;
