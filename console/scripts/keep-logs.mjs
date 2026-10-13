// Runs after every `npm run deploy`: switches Workers Logs back on for the
// console. A deploy resets the Worker's observability settings, and the
// config (cloudflare.config.ts) has no field for it - on 13 Oct 2026 the
// console threw "Error 1101" with nothing recorded anywhere, because logs were
// off. They must never be off again.
//
// Needs CLOUDFLARE_API_TOKEN (the Crayoratech token, as for the deploy itself).

const token = process.env.CLOUDFLARE_API_TOKEN;
if (!token) {
  console.error('keep-logs: CLOUDFLARE_API_TOKEN is not set - Workers Logs NOT re-enabled.');
  process.exit(1);
}

const h = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const accounts = await (await fetch('https://api.cloudflare.com/client/v4/accounts', { headers: h })).json();
const account = accounts.result?.[0]?.id;
if (!account) {
  console.error('keep-logs: no Cloudflare account visible to this token.');
  process.exit(1);
}

const res = await fetch(
  `https://api.cloudflare.com/client/v4/accounts/${account}/workers/scripts/craysalon-console/script-settings`,
  {
    method: 'PATCH',
    headers: h,
    body: JSON.stringify({ observability: { enabled: true, head_sampling_rate: 1 } }),
  },
);
const body = await res.json();
if (!body.success) {
  console.error(`keep-logs: could not enable Workers Logs: ${JSON.stringify(body.errors)}`);
  process.exit(1);
}
console.log('keep-logs: Workers Logs are on for craysalon-console.');
