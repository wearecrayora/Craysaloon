-- 0021 Branding publish
--
-- `salon_branding.version` is the number the app watches: bumping it is what
-- pushes a re-theme to every installed copy (PRD 8.1). So publishing is not an
-- UPDATE the console composes - it is one function that writes the tokens and
-- bumps the version together, and records who did it.
--
-- WHERE THE CONTRAST GATE LIVES, AND WHY NOT HERE.
--
-- DESIGN 3.3 and ARCHITECTURE 14.2 require publish to be BLOCKED when the
-- palette fails contrast. That check is real colour maths - sRGB to linear,
-- relative luminance, OKLCH lightness search for the derived steps - and it
-- already exists, tested, in packages/design-tokens, shared by the app and the
-- console so that the operator's preview cannot disagree with what a customer
-- sees (ADR-22).
--
-- Reimplementing it in PL/pgSQL would mean two implementations of the same
-- rule, which is how a rule quietly dies: the copies drift and nobody notices
-- which one is authoritative. So the gate runs once, in the console's SERVER
-- action - not in the browser, where it would be a courtesy - and this function
-- enforces the part SQL can actually enforce: that a published version records
-- the tokens it published and the human who published them.
--
-- What that leaves: a caller holding the service role could write tokens that
-- fail contrast by calling this directly. That caller is Crayora's own server,
-- not a tenant, and it is the same trust boundary that lets it provision
-- salons at all.

create or replace function app_admin.publish_branding(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_tokens         jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before  jsonb;
  v_version integer;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_tokens is null or jsonb_typeof(p_tokens) <> 'object' then
    raise exception 'app_admin: branding tokens must be a JSON object';
  end if;

  -- The two fields the app cannot render without. Everything else is the
  -- token package's business, not this function's.
  if coalesce(p_tokens ->> 'displayName', '') = '' then
    raise exception 'app_admin: branding must carry displayName';
  end if;
  if p_tokens -> 'brand' is null then
    raise exception 'app_admin: branding must carry a brand palette';
  end if;

  if not exists (select 1 from public.salons where id = p_salon_id) then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  select tokens, version into v_before, v_version
    from public.salon_branding
   where salon_id = p_salon_id
   for update;

  if v_version is null then
    v_version := 1;
    insert into public.salon_branding (salon_id, version, tokens)
    values (p_salon_id, v_version, p_tokens);
  else
    -- Monotonic. An app that has seen version 7 must never be handed a
    -- different version 7.
    v_version := v_version + 1;
    update public.salon_branding
       set version = v_version, tokens = p_tokens, updated_at = now()
     where salon_id = p_salon_id;
  end if;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'branding.published', 'salon_branding',
    p_salon_id::text, null,
    jsonb_build_object('version', v_version - 1, 'tokens', v_before),
    jsonb_build_object('version', v_version, 'tokens', p_tokens)
  );

  return v_version;
end;
$$;

comment on function app_admin.publish_branding is
  'Writes tokens and bumps salon_branding.version in one statement. The contrast gate that decides WHETHER a palette may be published runs in the console server action against packages/design-tokens - one implementation, shared with the app (ADR-22).';

-- 0020: a function added to app_admin is PUBLIC-executable until this is
-- called. Not optional.
select app_admin.close_privileges();
