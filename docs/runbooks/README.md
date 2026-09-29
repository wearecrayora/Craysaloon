# Runbooks

For Crayora operators. Each one: **what you will notice → what to check → what to do → how
you know it worked → what never to do.** If a runbook and the code disagree, the code is right
and the runbook is a bug - fix it the same day.

| Runbook | When |
|---|---|
| [restore.md](restore.md) | The database is lost or damaged; and the monthly restore drill |
| [billing-lapse.md](billing-lapse.md) | A salon's subscription payment is late; a lapse notice fired |
| [offboarding.md](offboarding.md) | A salon is leaving, or purge is due |
| [emergency-suspend.md](emergency-suspend.md) | A salon must stop operating now (fraud, abuse, a legal order) |
| [console-access.md](console-access.md) | Adding or removing a console admin (two locks: Cloudflare Access and the console login) |
| [support-mode.md](support-mode.md) | A salon or customer needs help that means looking at their data |
| [data-rights.md](data-rights.md) | A customer asked for a copy of their data, or to be erased |
| [mistaken-binding.md](mistaken-binding.md) | A customer is bound to the wrong salon |
| [credential-rotation.md](credential-rotation.md) | A key leaked, a person left, or it is launch day |
| [provider-outage.md](provider-outage.md) | Message Central, Razorpay or FCM is down |
| [stuck-dispatch.md](stuck-dispatch.md) | Reminders or "bill ready" pushes are not going out |
| [wallet-drift.md](wallet-drift.md) | A balance, or a dashboard number, looks wrong |

A personal-data breach has its own runbook with two legal clocks: [`RUNBOOK-BREACH.md`](../../RUNBOOK-BREACH.md).
