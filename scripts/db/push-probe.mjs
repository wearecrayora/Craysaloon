// Send one real push, and watch what the ack does to the bill.
//
//   node scripts/db/push-probe.mjs            report only - no message sent
//   node scripts/db/push-probe.mjs --send     create a notification and dispatch it
//   node scripts/db/push-probe.mjs --watch    report the state of the last probe
//
// This exists because the push path has four places to fail silently and none
// of them raises anything:
//
//   1. no device token          - the app never called register_push_token
//   2. a token, no permission   - Android 13+ delivers and drops it
//   3. a push sent, no ack      - the sweep escalates at the window, and the
//                                 SALON pays for the WhatsApp or SMS
//   4. an ack, and nothing else - which is the outcome worth confirming
//
// It sends a REAL message to a REAL phone, so it is opt-in per run.

import postgres from 'postgres';
import { requireDatabaseUrl, connect, loadEnv } from './env.mjs';

const send = process.argv.includes('--send');
const sql = connect(postgres, await requireDatabaseUrl());

try {
  const tokens = await sql`
    select t.salon_id, t.customer_id, t.platform, t.dead_at,
           s.display_name as salon, c.name as customer,
           right(t.token, 6) as token_tail, t.updated_at
      from public.notification_tokens t
      join public.salons s on s.id = t.salon_id
      join public.customers c on c.id = t.customer_id
     order by t.updated_at desc
     limit 10`;

  if (tokens.length === 0) {
    console.log('No device tokens registered.\n');
    console.log('Nothing has called register_push_token yet. That happens when the app');
    console.log('reaches the customer home screen while signed in - so: install the APK,');
    console.log('enter the salon code, log in by OTP, and allow notifications.');
    process.exit(0);
  }

  console.log('Registered devices:\n');
  for (const t of tokens) {
    console.log(
      `  ${t.salon} / ${t.customer ?? '(anonymised)'} · ${t.platform} · ...${t.token_tail}` +
        `${t.dead_at ? '  DEAD' : ''}  (${t.updated_at.toISOString()})`,
    );
  }

  const target = tokens.find((t) => !t.dead_at);
  if (!target) {
    console.error('\nEvery token is marked dead. FCM said UNREGISTERED for all of them.');
    process.exit(1);
  }

  if (!send) {
    console.log('\nRe-run with --send to deliver one real push to the device above.');
    process.exit(0);
  }

  // A transactional message, so consent cannot be the reason it does not arrive
  // - service_communication is the service itself and cannot be withdrawn.
  const [created] = await sql`
    select app.notify(
      ${target.salon_id}::uuid, ${target.customer_id}::uuid,
      'booking_confirmed', 'transactional', 'booking_confirmed',
      ${JSON.stringify({ when: 'this is a test from the Crayora console' })}::jsonb
    ) as id`;

  console.log(`\nNotification ${created.id} created (pending).`);

  const { SUPABASE_URL, CRAY_SECRET_KEY, SUPABASE_SECRET_KEY } = await loadEnv();
  const key = CRAY_SECRET_KEY ?? SUPABASE_SECRET_KEY;
  if (!SUPABASE_URL || !key) {
    console.error('SUPABASE_URL or the secret key is missing from .env - cannot dispatch.');
    process.exit(1);
  }

  const response = await fetch(`${SUPABASE_URL}/functions/v1/dispatch-notifications`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ salon_id: target.salon_id, limit: 10 }),
  });

  console.log(`dispatcher: ${response.status} ${await response.text()}`);

  const deliveries = await sql`
    select d.channel, d.provider_status, d.failure_reason,
           d.sent_at, d.acked_at, d.cost_paise
      from public.notification_deliveries d
     where d.notification_id = ${created.id}::uuid
     order by d.created_at`;

  console.log('\nDeliveries:');
  for (const d of deliveries) {
    console.log(
      `  ${d.channel} · ${d.provider_status}${d.failure_reason ? ` (${d.failure_reason})` : ''}` +
        ` · sent ${d.sent_at?.toISOString() ?? '-'} · acked ${d.acked_at?.toISOString() ?? 'NOT YET'}` +
        ` · ${d.cost_paise} paise`,
    );
  }

  console.log(
    '\nNow look at the phone. When the app acknowledges it, acked_at fills in and the\n' +
      'sweep leaves it alone. Un-acked, the window expires and the next rung is queued -\n' +
      'and that one costs the salon money. Re-run with --watch to see which happened.',
  );
} finally {
  await sql.end({ timeout: 5 });
}
