-- 0067 A malformed params blob stopped every message for the salon
--
-- The first real push failed with `cannot call jsonb_each on a non-object`.
-- The immediate cause was mine: a probe script double-encoded its params, so
-- `params` held a JSON *string* rather than an object.
--
-- The important part is what that did. `render_template` is called inside
-- `claim_notification_batch`'s RETURN QUERY, once per queued delivery - so one
-- malformed row did not fail its own message, it **threw out of the whole
-- batch** and stopped every other notification for that salon. One bad row
-- stalling a tenant is exactly the failure mode ARCHITECTURE 11.2 designs
-- against, and the per-salon exception block in the sweep does not help here:
-- the salon fails as a unit, every minute, until someone notices.
--
-- `params` is a free-shaped jsonb column. Anything that can put a scalar in it
-- eventually will - an Edge Function, a backfill, a migration. The renderer
-- treats a non-object as no params, which is the honest reading: there are no
-- key-value pairs to substitute.

create or replace function app.render_template(
  p_salon_id     uuid,
  p_template_key text,
  p_locale       text,
  p_channel      public.message_channel,
  p_params       jsonb default '{}'::jsonb
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_body   text;
  v_salon  text;
  v_params jsonb;
  v_key    text;
  v_val    text;
begin
  select t.body into v_body
    from public.message_templates t
   where t.template_key = p_template_key
     and t.channel = p_channel
     and t.locale in (p_locale, 'en')
     and (t.salon_id = p_salon_id or t.salon_id is null)
   order by (t.salon_id is not null) desc, (t.locale = p_locale) desc
   limit 1;

  if v_body is null then
    return null;
  end if;

  select s.display_name into v_salon from public.salons s where s.id = p_salon_id;
  v_body := replace(v_body, '{{salon}}', coalesce(v_salon, ''));

  -- A scalar, an array or a null is "no substitutions", not an exception. The
  -- message still goes out with its template text; a message that renders
  -- plainly beats a salon whose queue stops.
  v_params := case when jsonb_typeof(p_params) = 'object' then p_params else '{}'::jsonb end;

  for v_key, v_val in select key, value #>> '{}' from jsonb_each(v_params)
  loop
    v_body := replace(v_body, '{{' || v_key || '}}', coalesce(v_val, ''));
  end loop;

  return v_body;
end;
$$;

comment on function app.render_template is
  'Server-side rendering (ARCHITECTURE 12.5). A non-object `params` renders as no substitutions rather than throwing: this function runs inside the dispatcher''s batch query, so one malformed row used to take down every message for that salon (0067).';
