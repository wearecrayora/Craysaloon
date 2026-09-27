-- 0037 Branding is published RESOLVED, or not at all
--
-- ARCHITECTURE 7.2 says the app and the console's preview share one token
-- definition, so the preview cannot lie about what the customer sees. The
-- console is TypeScript and the app is Dart, so "shared" cannot mean shared
-- code for the maths: packages/design-tokens derives onPrimary, brandInk,
-- primaryContainer, the radius ladder and the Devanagari line-height bonus, and
-- a Dart port of that would be a second implementation free to drift. The first
-- palette where the two disagreed would make the preview a liar again - the
-- exact failure ADR-22 exists to prevent.
--
-- So derivation happens once, at publish, in the console (RULES 12A.5, and
-- CLAUDE.md: "computed at publish"), and the published document carries the
-- resolved light and dark sets alongside the operator's input. The app reads
-- values; it computes nothing and therefore cannot disagree.
--
-- This function is where that becomes a rule rather than a habit: branding
-- without both resolved sets is refused, so no future route, script or manual
-- call can store a document the app cannot theme from.

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
  v_mode    text;
  v_set     jsonb;
  v_key     text;
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

  -- Resolved, both modes. The app theming itself from an unresolved document
  -- would have to derive these colours, and a second implementation of the
  -- derivation is how the preview starts lying (ADR-22).
  foreach v_mode in array array['light', 'dark'] loop
    v_set := p_tokens -> 'resolved' -> v_mode;
    if v_set is null or jsonb_typeof(v_set) <> 'object' then
      raise exception
        'app_admin: branding must carry resolved.% - the console derives it at publish, the app never computes it', v_mode;
    end if;
    foreach v_key in array array['primary', 'onPrimary', 'surface', 'textPrimary'] loop
      if coalesce(v_set -> 'color' ->> v_key, '') = '' then
        raise exception 'app_admin: resolved.%.color.% is missing', v_mode, v_key;
      end if;
    end loop;
    if v_set -> 'radius' ->> 'base' is null then
      raise exception 'app_admin: resolved.%.radius.base is missing', v_mode;
    end if;
  end loop;

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
  'Writes tokens and bumps salon_branding.version in one statement. The contrast gate that decides WHETHER a palette may be published runs in the console server action against packages/design-tokens; that same package resolves the light and dark token sets, which this function requires (0037), so the Flutter app reads derived values instead of deriving its own (ADR-22, ADR-40).';

select app_admin.close_privileges();
