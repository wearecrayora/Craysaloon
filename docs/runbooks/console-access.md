# Console access (Cloudflare Access)

The console has **two locks**, and a person needs both:

1. **Cloudflare Access** in front of the whole site - team domain
   `withered-river-195a.cloudflareaccess.com`, application **"Crayora console"**, policy
   **"Crayora console admins"**: an email on the list gets a one-time code by email; a 12-hour
   session. Everyone else is stopped before a single console page loads.
2. **The console's own login** - email, password and an authenticator code, against
   `platform_admins`.

## Adding a console admin

1. Add them to `platform_admins` (how every admin has always been added).
2. **Also** add their email to the Access policy: Cloudflare dashboard (Crayoratech account) →
   Zero Trust → Access → Applications → *Crayora console* → Policies → *Crayora console admins* →
   Include → Emails. Without this they are stopped at the door, with a Cloudflare page, not a
   console error.

## Removing one

Both, the same day: deactivate the `platform_admins` row **and** take the email off the Access
policy. Then revoke their Access sessions (Zero Trust → Access → Applications → *Crayora console*
→ Revoke existing tokens) - removing an email does not end a session already open.

## If the console ever gets its own domain

Not planned: no domain is being bought (30 Sep 2026), and the `workers.dev` address is the
console's address.

The Access application protects `craysalon-console.crayoratech.workers.dev`. Add the new
hostname to the same application **before** pointing DNS at the Worker, then turn the
`workers.dev` address off (`workersDev: false` in `console/cloudflare.config.ts`). A second
address without Access is a second door.

## Never

- Add a group or a whole email domain "for convenience". This console creates salons and holds
  their payment keys; the list is people, by name.
- Turn preview URLs back on (`previewUrls: false` in `console/cloudflare.config.ts`): each is a
  separate public address.
