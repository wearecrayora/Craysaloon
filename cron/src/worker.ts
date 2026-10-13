// craysalon-cron: every minute, ask the dispatcher to send each active salon's
// queue (migration 0100; wrangler.jsonc says why this lives on Cloudflare).
//
// What it sends is decided in the database and the Edge Function - this is only
// the clock. Overlapping ticks are safe: a claim is a five-minute lease (0100),
// so a slow tick and the next one never send the same message twice.
//
// It logs COUNTS and salon ids only - never a message body or a recipient.

interface Env {
  SUPABASE_URL: string;
  CRAY_SECRET_KEY: string;
}

interface ScheduledController {
  scheduledTime: number;
}

// The Free plan allows 50 outbound requests per invocation; one goes to
// dispatch_salons. Past this many salons, each tick takes the next slice in
// turn, so every salon is still served - once every ceil(n / PER_TICK) minutes
// - instead of the tick failing outright. Workers Paid lifts the limit; raise
// this then.
const PER_TICK = 40;

// The batch per salon per tick. A minute cadence needs no big batches, and a
// small one keeps a tick well inside the lease.
const BATCH = 50;

const LIST_SALONS = 'dispatch_salons';

export default {
  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    if (!env.SUPABASE_URL || !env.CRAY_SECRET_KEY) {
      // Thrown, not returned: a clock that silently does nothing is the failure
      // this Worker replaced (the GitHub dispatcher, 5-13 Oct 2026).
      throw new Error('SUPABASE_URL or CRAY_SECRET_KEY is not set - nothing is being sent');
    }

    const auth = {
      apikey: env.CRAY_SECRET_KEY,
      Authorization: `Bearer ${env.CRAY_SECRET_KEY}`,
      'Content-Type': 'application/json',
    };

    const list = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${LIST_SALONS}`, {
      method: 'POST',
      headers: auth,
      body: '{}',
    });
    if (!list.ok) throw new Error(`dispatch_salons -> HTTP ${list.status}`);
    const salons = (await list.json()) as string[];
    if (salons.length === 0) return;

    const slices = Math.ceil(salons.length / PER_TICK);
    const slice = Math.floor(controller.scheduledTime / 60_000) % slices;
    const mine = salons.slice(slice * PER_TICK, (slice + 1) * PER_TICK);

    const results = await Promise.allSettled(
      mine.map(async (salon) => {
        const res = await fetch(`${env.SUPABASE_URL}/functions/v1/dispatch-notifications`, {
          method: 'POST',
          headers: { Authorization: auth.Authorization, 'Content-Type': 'application/json' },
          body: JSON.stringify({ salon_id: salon, limit: BATCH }),
        });
        const text = await res.text();
        if (!res.ok) throw new Error(`${salon} -> HTTP ${res.status}`);
        return { salon, counts: text };
      }),
    );

    let failed = 0;
    for (const r of results) {
      if (r.status === 'fulfilled') {
        // Quiet when there was nothing to do; a line per salon that sent.
        if (!r.value.counts.includes('"claimed":0')) console.log(`${r.value.salon} ${r.value.counts}`);
      } else {
        failed++;
        console.error(String(r.reason instanceof Error ? r.reason.message : r.reason));
      }
    }
    // A failed salon fails the tick, so it shows as an error in the Worker's
    // cron events - and the watchdog (dispatch.yml) goes red if it persists.
    if (failed > 0) throw new Error(`${failed} of ${mine.length} salons failed to dispatch`);
  },
};
