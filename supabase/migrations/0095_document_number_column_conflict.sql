-- 0095 app.next_document_number could not run (0094).
--
-- It RETURNS TABLE (number, fy, seq), and in plpgsql those output columns are
-- variables - so `on conflict (salon_id, series, fy)` named an ambiguous `fy`
-- and every call failed with "column reference fy is ambiguous". Caught by the
-- documents gate on its first run, before any receipt was issued: the header of
-- CLAUDE.md's "do not add a function without running it", working.
--
-- `#variable_conflict use_column` makes a bare name mean the column. The
-- signature is unchanged, so the two issuing functions need nothing.

create or replace function app.next_document_number(
  p_salon_id uuid,
  p_series   text,
  p_at       timestamptz
)
returns table (number text, fy text, seq integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_fy  text := app.financial_year(p_at);
  v_seq integer;
begin
  -- Row-locked increment in the caller's transaction: two documents issued at
  -- once queue on the row, and a rollback returns the number.
  insert into public.document_series as s (salon_id, series, fy, last_number)
  values (p_salon_id, p_series, v_fy, 1)
  on conflict (salon_id, series, fy)
  do update set last_number = s.last_number + 1
  returning s.last_number into v_seq;

  return query select p_series || '/' || v_fy || '/' || to_char(v_seq, 'FM00000'), v_fy, v_seq;
end;
$$;

revoke all on function app.next_document_number(uuid, text, timestamptz) from public, anon, authenticated;
