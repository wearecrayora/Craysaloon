// CONCURRENT WALLET DEBITS CANNOT OVERDRAW (PRD 20, RULES 5) - tested with real
// concurrency, on separate connections.
//
//   node scripts/db/concurrency-test.mjs            the gate
//   node scripts/db/concurrency-test.mjs --canary   its negative control
//
// The money gate (ledger_test.sql) spends twice IN ONE SESSION and says "the
// row lock decides" - but one session cannot race itself, so that assertion
// would pass with no lock at all. This one opens separate connections:
//
//   1. STAGED. Checkout A debits Rs 900 of Rs 1,100 and holds its transaction
//      open. Checkout B asks for Rs 900 too. B must WAIT for A, and when A
//      commits, B must be refused cleanly - insufficient_credit - not succeed,
//      and not fall over inside the lot arithmetic.
//   2. A BURST. Twenty Rs 100 debits at once against Rs 1,100: exactly eleven
//      succeed, nine are refused, none errors, and the balance lands on zero -
//      equal to the ledger's own sum.
//
// --canary takes the lock out of wallet_debit_at_checkout (`for update` on the
// wallet account) and requires this test to FAIL. Without the lock, B reads the
// balance A has not committed yet, carries on, and dies in the lots instead of
// being refused - the second line of defence holds the money, but the gate must
// notice the first one is gone. A gate seen only passing is not known to be one.
//
// It COMMITS its fixtures - a race needs two transactions that see the same
// rows - into ledgers that are append-only and can never be cleaned up. So it
// runs only against a throwaway database: CI's container. It refuses anything
// else, the shared hosted project above all.

import postgres from 'postgres';
import { randomUUID } from 'node:crypto';
import { requireDatabaseUrl } from './env.mjs';

const CANARY = process.argv.includes('--canary');
const url = await requireDatabaseUrl();
const host = new URL(url).hostname;
if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)) {
  console.error(
    'REFUSED: this test commits rows to append-only ledgers. It runs only against a\n' +
      "throwaway local database (CI's container), never the shared hosted project.",
  );
  process.exit(2);
}

const sql = postgres(url, { max: 24, prepare: false, idle_timeout: 20, onnotice: () => {} });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const failures = [];
const check = (ok, what) => {
  console.log(`  ${ok ? 'ok' : 'NOT OK'} - ${what}`);
  if (!ok) failures.push(what);
};

const LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const joinCode = () =>
  'CRAY-' + Array.from({ length: 6 }, () => LETTERS[Math.floor(Math.random() * LETTERS.length)]).join('');

/** A salon and a customer holding Rs 1,000 paid + Rs 100 bonus, committed. */
async function fixture() {
  const admin = randomUUID();
  const salon = randomUUID();
  const customer = randomUUID();
  const payment = randomUUID();
  const phone = `98${String(Math.floor(Math.random() * 1e8)).padStart(8, '0')}`;
  await sql.begin(async (tx) => {
    await tx`select set_config('app.phone_hash_pepper', 'concurrency-test-pepper', true)`;
    await tx`insert into auth.users (id) values (${admin})`;
    await tx`insert into public.platform_admins (id, email, name, is_super, active)
             values (${admin}, ${`race-${admin}@crayora.test`}, 'Race Super', true, true)`;
    await tx`insert into public.salons (id, legal_name, display_name, join_code, status,
                                        wallet_rule, activated_by, activated_at)
             values (${salon}, 'Race Salon Ltd', 'Race Salon', ${joinCode()}, 'active',
                     ${sql.json({ topup_paise: 100000, bonus_paise: 10000, min_topup_paise: 50000 })},
                     ${admin}, now())`;
    await tx`insert into public.customers (id, salon_id, name, phone, phone_hash)
             values (${customer}, ${salon}, 'Racer', ${phone}, app.phone_hash(${phone}))`;
    await tx`insert into public.payments (id, salon_id, customer_id, method, amount_paise, status, captured_at)
             values (${payment}, ${salon}, ${customer}, 'upi', 100000, 'captured', now())`;
    await tx`select app.wallet_credit_from_payment(${payment})`;
  });
  const [{ balance }] = await sql`
    select balance_paise::int as balance from public.wallet_accounts where customer_id = ${customer}`;
  return { salon, customer, balance };
}

async function books(customer) {
  const [r] = await sql`
    select (select balance_paise from public.wallet_accounts where customer_id = ${customer})::int as balance,
           (select coalesce(sum(amount_paise), 0) from public.wallet_transactions
             where customer_id = ${customer})::int as ledger,
           (select coalesce(sum(remaining_paise), 0) from public.wallet_lots
             where customer_id = ${customer} and expired_at is null)::int as lots`;
  return r;
}

const debit = (tx, f, paise) =>
  tx`select app.wallet_debit_at_checkout(${f.salon}, ${f.customer}, ${paise}::bigint) as r`.then(
    ([row]) => row.r,
  );

let restore = null;
try {
  if (CANARY) {
    const [{ def }] = await sql`
      select pg_get_functiondef('app.wallet_debit_at_checkout(uuid,uuid,bigint,uuid,uuid)'::regprocedure) as def`;
    const lockless = def.replace(
      /(where w\.customer_id = p_customer_id\s*)\n\s*for update;/,
      '$1;',
    );
    if (lockless === def) throw new Error('canary: could not find the wallet-account lock to remove');
    await sql.unsafe(lockless);
    restore = def;
    console.log('CANARY: wallet_debit_at_checkout no longer locks the wallet account.\n');
  }

  console.log('Staged race: A holds Rs 900 of Rs 1,100 open; B asks for Rs 900.');
  const f1 = await fixture();
  check(f1.balance === 110000, 'the fixture holds Rs 1,100 (Rs 1,000 paid + Rs 100 bonus)');

  const a = await sql.reserve();
  const b = await sql.reserve();
  let bResult;
  let bError = null;
  let bDone = false;
  try {
    await a`begin`;
    const ra = await debit(a, f1, 90000);
    check(ra.ok === true, 'A debits Rs 900 inside an open transaction');

    await b`begin`;
    const bPromise = debit(b, f1, 90000)
      .then((r) => { bResult = r; })
      .catch((e) => { bError = e; })
      .finally(() => { bDone = true; });

    await sleep(1500);
    check(!bDone, 'B WAITS while A holds the wallet - it does not read the balance A is spending');

    await a`commit`;
    await bPromise;
    check(bError === null, `B is refused cleanly, not by an error${bError ? ` (got: ${bError.message})` : ''}`);
    check(bResult?.ok === false && bResult?.reason === 'insufficient_credit',
      'B sees A\'s debit and is refused: insufficient_credit');
    await b`rollback`;
  } finally {
    await a`rollback`.catch(() => {});
    a.release();
    b.release();
  }

  const s1 = await books(f1.customer);
  check(s1.balance === 20000, `the balance is Rs 200 (got ${s1.balance / 100})`);
  check(s1.ledger === s1.balance && s1.lots === s1.balance,
    'the ledger sum, the lots and the cached balance all agree');

  console.log('\nBurst: twenty Rs 100 debits at once against Rs 1,100.');
  const f2 = await fixture();
  const results = await Promise.allSettled(
    Array.from({ length: 20 }, () => sql.begin((tx) => debit(tx, f2, 10000))),
  );
  const ok = results.filter((r) => r.status === 'fulfilled' && r.value.ok === true).length;
  const refused = results.filter(
    (r) => r.status === 'fulfilled' && r.value.ok === false && r.value.reason === 'insufficient_credit',
  ).length;
  const errored = results.filter((r) => r.status === 'rejected');
  check(ok === 11, `exactly eleven succeed (got ${ok})`);
  check(refused === 9, `the other nine are refused (got ${refused})`);
  check(errored.length === 0,
    `none errors${errored.length ? ` (got ${errored.length}: ${errored[0].reason?.message})` : ''}`);
  const s2 = await books(f2.customer);
  check(s2.balance === 0 && s2.ledger === 0 && s2.lots === 0,
    `the wallet is exactly empty and the books agree (balance ${s2.balance}, ledger ${s2.ledger}, lots ${s2.lots})`);
} finally {
  if (restore) {
    await sql.unsafe(restore);
    console.log('\nCANARY: the lock is restored.');
  }
  await sql.end({ timeout: 5 });
}

if (CANARY) {
  if (failures.length > 0) {
    console.log(`\nNEGATIVE CONTROL PASSED - with the lock removed, ${failures.length} check(s) went red.`);
    process.exit(0);
  }
  console.error('\nNEGATIVE CONTROL FAILED - the lock was removed and every check stayed green. This gate tests nothing.');
  process.exit(1);
}
if (failures.length > 0) {
  console.error(`\nCONCURRENCY GATE FAILED - ${failures.length} check(s). Concurrent checkouts can mis-spend a wallet.`);
  process.exit(1);
}
console.log('\nCONCURRENCY GATE PASSED - concurrent debits serialise and cannot overdraw.');
