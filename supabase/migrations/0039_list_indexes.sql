-- 0039 What the owner's lists actually run (M5)
--
-- Lists are keyset-paginated, never OFFSET: OFFSET re-reads and discards every
-- skipped row, and it silently skips real rows when something is inserted while
-- someone is scrolling (ARCHITECTURE 6.8). Keyset needs the ORDER BY columns in
-- the index, INCLUDING the tiebreaker, or the last page costs a sort of the
-- whole tenant.
--
-- Every index leads with salon_id (RULES 3.1), so it is useless to a query that
-- forgot to scope itself - the index-scope gate asserts exactly that.

-- The customer list: most recently seen first, with id as the tiebreaker so a
-- cursor is total. NULLS LAST because a customer who has never visited still
-- belongs in the list, at the end.
create index customers_salon_keyset_idx
  on public.customers (salon_id, last_visit_at desc nulls last, id desc)
  where deleted_at is null;

-- Searching the list. Two searches, two shapes:
--   * by name - the owner types the first few letters. text_pattern_ops because
--     the query is `lower(name) like 'ay%'`, and the default collation's index
--     cannot serve a prefix LIKE.
--   * by number - EXACT, on the hash. A partial phone search would mean storing
--     or scanning plaintext numbers, and the number is only ever known in full
--     anyway: the customer reads it out (RULES 4.7).
create index customers_salon_name_prefix_idx
  on public.customers (salon_id, lower(name) text_pattern_ops)
  where deleted_at is null;

-- Visit history on a customer's record, newest first.
create index visits_customer_keyset_idx
  on public.visits (salon_id, customer_id, completed_at desc, id desc);

-- The catalogue lists, in the order they are shown: active first, then by name.
create index services_salon_list_idx
  on public.services (salon_id, active, name);

create index add_ons_salon_list_idx
  on public.add_ons (salon_id, active, name);

create index staff_salon_list_idx
  on public.staff (salon_id, active, name);
