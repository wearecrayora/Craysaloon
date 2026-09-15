-- 0027 Attributable asset generation
--
-- The QR pack is written to R2, not to Postgres, so strictly it is not a
-- database mutation and RULES 6.5 would not reach it. It is audited anyway,
-- for a reason that is specific to this artifact: the pack is the salon's
-- PUBLIC face. It carries the join code, it gets printed and stuck to mirrors,
-- and if a code ever needs to be investigated - a leaked QR, a pack printed
-- for the wrong salon, a dispute about when a salon was set up - "who generated
-- this, and when" has to have an answer that does not depend on anyone's
-- memory.
--
-- The object key is recorded, the object itself is not: audit_log is not the
-- place for binary content, and R2 keeps it.

create or replace function app_admin.record_asset(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_kind           text,
  p_object_key     text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_kind not in ('qr_pack') then
    raise exception 'app_admin: unknown asset kind %', p_kind;
  end if;

  if not exists (select 1 from public.salons where id = p_salon_id) then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  -- The key must sit under this salon's own prefix. A key naming another
  -- salon's folder is either a bug or an attempt to attribute one salon's
  -- artifact to another, and neither should produce an audit row that looks
  -- legitimate.
  if p_object_key not like ('salons/' || p_salon_id::text || '/%') then
    raise exception 'app_admin: object key is not under this salon''s prefix';
  end if;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'asset.generated', 'r2', p_object_key, null, null,
    jsonb_build_object('kind', p_kind, 'object_key', p_object_key));
end;
$$;

select app_admin.close_privileges();
