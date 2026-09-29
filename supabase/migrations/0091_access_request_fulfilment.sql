-- 0091 A copy of their data: the right of access can now actually be met.
--
-- DPDP s.11: a customer may ask for a summary of their personal data and what
-- is done with it. Since 0051 the request could be MADE (request_data_right
-- 'access', with a 30-day due date) but nobody could produce the copy: the
-- console said "the salon answers this one" and the salon's app has no export.
-- A right with a request button and no answer is a queue of breaches waiting
-- for their due dates.
--
-- The copy is produced by REQUEST id, never by customer id or phone: the console
-- is never handed a way to look a person up (0081), only to answer a request the
-- person made themselves. Crayora produces it as the processor, on the salon's
-- behalf; the salon remains the fiduciary that answers.

create or replace function app_admin.access_request_export(
  p_actor_admin_id uuid,
  p_request_id     uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req record;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  select r.id, r.salon_id, r.customer_id, r.kind, r.requested_at
    into v_req
    from public.data_rights_requests r where r.id = p_request_id;

  if v_req.id is null then
    raise exception 'app_admin: no such request';
  end if;
  if v_req.kind <> 'access' then
    raise exception 'app_admin: this is not a request for a copy of their data';
  end if;

  return jsonb_build_object(
    'format', 'cray-salon-personal-data/1',
    'generated_at', now(),
    'request', jsonb_build_object('id', v_req.id, 'requested_at', v_req.requested_at),
    'salon', (select jsonb_build_object(
                'name', s.display_name,
                'privacy_contact', jsonb_build_object('name', s.grievance_name,
                                                      'email', s.grievance_email,
                                                      'phone', s.grievance_phone))
                from public.salons s where s.id = v_req.salon_id),
    'purposes', jsonb_build_array(
       'Logging you in to the app',
       'Your bookings, visits and bills',
       'Reminders when a service is due, if you agreed',
       'Offers from the salon, if you agreed'),
    'you', (select jsonb_build_object(
              'name', c.name, 'phone', c.phone, 'birthday', c.birthday,
              'anniversary', c.anniversary, 'language', c.language,
              'joined_at', c.created_at, 'last_visit_at', c.last_visit_at,
              'loyalty_points', c.loyalty_points)
              from public.customers c where c.id = v_req.customer_id),
    'consents', coalesce((select jsonb_agg(jsonb_build_object(
                  'purpose', x.purpose, 'granted', x.granted, 'source', x.source,
                  'at', x.occurred_at) order by x.occurred_at)
                  from public.consents x where x.customer_id = v_req.customer_id), '[]'),
    'bookings', coalesce((select jsonb_agg(jsonb_build_object(
                  'starts_at', b.starts_at, 'status', b.status, 'total_paise', b.total_paise,
                  'services', (select string_agg(i.name_snapshot, ', ')
                                 from public.booking_items i where i.booking_id = b.id))
                  order by b.starts_at)
                  from public.bookings b where b.customer_id = v_req.customer_id), '[]'),
    'visits', coalesce((select jsonb_agg(jsonb_build_object(
                  'completed_at', v.completed_at, 'amount_paise', v.final_amount_paise,
                  'tip_paise', v.tip_paise, 'payment_status', v.payment_status)
                  order by v.completed_at)
                  from public.visits v where v.customer_id = v_req.customer_id), '[]'),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
                  'method', p.method, 'amount_paise', p.amount_paise, 'status', p.status,
                  'at', coalesce(p.captured_at, p.created_at)) order by p.created_at)
                  from public.payments p where p.customer_id = v_req.customer_id), '[]'),
    'wallet', jsonb_build_object(
       'balance_paise', coalesce((select w.balance_paise from public.wallet_accounts w
                                   where w.customer_id = v_req.customer_id), 0),
       'history', coalesce((select jsonb_agg(jsonb_build_object(
                    'kind', t.kind, 'amount_paise', t.amount_paise,
                    'balance_after', t.balance_after, 'at', t.created_at) order by t.id)
                    from public.wallet_transactions t
                   where t.customer_id = v_req.customer_id), '[]')),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object(
                  'purpose', n.purpose, 'at', n.created_at, 'status', n.status)
                  order by n.created_at)
                  from public.notifications n where n.customer_id = v_req.customer_id), '[]'),
    'requests', coalesce((select jsonb_agg(jsonb_build_object(
                  'kind', d.kind, 'status', d.status, 'requested_at', d.requested_at,
                  'outcome', d.outcome) order by d.requested_at)
                  from public.data_rights_requests d where d.customer_id = v_req.customer_id), '[]')
  );
end;
$$;

-- Closing the request, with how the copy reached the person. The customer sees
-- the outcome under "Your data".
create or replace function app_admin.complete_access_request(
  p_actor_admin_id uuid,
  p_request_id     uuid,
  p_how_sent       text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req record;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_how_sent), '') = '' then
    raise exception 'app_admin: say how the copy reached the customer - "emailed on 3 Jan"';
  end if;

  select r.id, r.salon_id, r.kind, r.status into v_req
    from public.data_rights_requests r where r.id = p_request_id for update;

  if v_req.id is null then
    raise exception 'app_admin: no such request';
  end if;
  if v_req.kind <> 'access' then
    raise exception 'app_admin: this is not a request for a copy of their data';
  end if;
  if v_req.status not in ('open', 'in_progress') then
    raise exception 'app_admin: this request is already closed';
  end if;

  update public.data_rights_requests
     set status = 'completed', completed_at = now(), handled_by = p_actor_admin_id,
         outcome = 'A copy of your data was sent to you: ' || btrim(p_how_sent)
   where id = p_request_id;

  perform app_admin.audit(v_req.salon_id, p_actor_admin_id, 'data_rights.access_fulfilled',
                          'data_rights_requests', p_request_id::text, p_how_sent, null, null);
end;
$$;

select app_admin.close_privileges();
