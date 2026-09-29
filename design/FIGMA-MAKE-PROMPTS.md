# Figma Make prompts — Cray Salon, every screen

Paste these into **one** Figma Make file, **in order**, one prompt per message. Prompt 0 sets up the
design system and the rules; every later prompt builds on it. Wait for each to finish before
sending the next. If Figma Make drifts from a rule in Prompt 0, reply with: *"Re-read the rules in
the first prompt — [the rule it broke]."*

Screens are phone frames at **360 × 800** (a mid-range Android), except the console (Prompts 8–9),
which is desktop at **1440 × 900**.

---

## PROMPT 0 — Product, design system and rules (send first)

```
You are designing "Cray Salon": a white-labelled Android app that local hair salons in India give
to their customers, plus the same app's owner mode for the salon owner, plus a desktop admin
console used by Crayora (the company that sells and sets up each salon).

WHAT THE PRODUCT DOES
- A customer joins ONE salon by scanning the salon's QR code or typing its salon code, then logs
  in with their phone number and an SMS code. From then on the app looks like THAT salon's app:
  its name, logo, colours and fonts. The customer never sees "Cray Salon" or "Crayora" inside the
  app (only one small line in Settings: "App by Crayora").
- Customers: book services and optional add-ons, keep a prepaid wallet at the salon (top up with
  UPI, get a bonus), get reminded when their next haircut is due, refer friends, pay their bill
  from the app.
- A visit: the customer arrives, shows a 4-digit START CODE from their app, the stylist types it
  and taps Start. When the work is finished the stylist taps "Mark complete". The customer's app
  then ASKS "How would you like to pay?" — Wallet, UPI, or At the counter.
- The owner runs the day from the phone: today's bookings, Start, Mark complete, Take payment,
  walk-ins, customers, a simple dashboard, and the service menu.
- Users: owners standing between customers, one-handed, wet hands, bright room, cheap Android,
  unreliable network. Customers who open the app once a month for two minutes. Many read Hindi.

THIS IS A WHITE-LABEL CHASSIS, NOT ONE LOOK
Design every app screen so that ONLY these things change per salon: brand primary colour, brand
accent colour, heading font family, body font family, logo/wordmark, one corner-radius number,
and the salon's display name. Everything else is fixed for every salon.
Build all colours as variables (Figma variables / tokens), never raw hex on layers, with 3 modes:
- Brand A (default for all screens): "Studio Nine Salon" — primary #1F6F5C (deep teal), accent
  #C8A24A (muted gold), heading font "Tiro Devanagari Hindi", body font "Mukta", radius 14.
- Brand B: "Kesar Unisex Salon" — primary #7A1F3D (maroon), accent #E0A96D, heading "Poppins",
  body "Hind", radius 6.
- Neutral default: "Your salon" — primary #3D4A5C (slate), accent #8A94A3, heading and body
  "Noto Sans", radius 12. (Used when a salon's branding cannot load.)
Every mode also needs a DARK variant (brand light/dark: A #1F6F5C/#7FD3BC, accent #C8A24A/#E3C378).

COLOUR ROLES (make each a variable)
- brand: primary, onPrimary, primaryContainer, onPrimaryContainer, accent, onAccent, brandInk
  - onPrimary is black or white, whichever has ≥4.5:1 contrast on primary.
  - brandInk = the brand hue darkened until it has ≥4.5:1 on the surface; the ONLY way brand
    colour is used for text.
- surface: surface, surfaceAlt, surfaceSunken, overlay — FIXED neutrals with a very slight warm
  hue (e.g. surface #FAF9F6, surfaceAlt #F3F2EE, surfaceSunken #ECEAE5). Never pure #FFFFFF.
- ink: textPrimary (#1C1B19), textSecondary (#4A4843), textMuted (#6E6B64). Never pure #000000.
- line: border, borderStrong, divider.
- status (FIXED for every salon, never brand-coloured): success #0CA30C, warning #FAB219,
  danger #D03B3B, info #2563A8. Status is ALWAYS shown with an icon + a word, never colour alone.
- chart (FIXED): series1 #2A78D6 blue, series2 #EB6834 orange, series3 #1BAF7A aqua. Max 3 series.

HARD RULES — a screen that breaks one is wrong
1. Never tint backgrounds or cards with the brand colour. Surfaces stay neutral. Brand colour is
   only for filled buttons, the selected state, chips, small accents and the app bar wordmark.
2. Never put body text on the brand colour. Never grey text on a coloured background.
3. Salon logo appears once per screen, in the top app bar. Not in cards.
4. Money: Indian rupee with Indian digit grouping (₹1,20,500 not ₹120,500), whole rupees
   (₹550 not ₹550.00), tabular (monospaced) figures so amounts line up, a real minus sign
   (−₹200). Zero is "₹0". Money is never tiny: no money below 15px.
5. A wallet balance is NEVER shown alone. It always has, right under it: "Usable only at
   <Salon name>. Cannot be withdrawn as cash."
6. Nothing that costs money is ever pre-selected. Add-on checkboxes always start unticked.
   Payment choices start with nothing chosen.
7. Unavailable slots/add-ons are removed, not greyed out or struck through.
8. Touch targets ≥48×48 px, 8px apart. The owner's Start and Mark complete buttons are ≥56px tall.
9. One column on phones. Always. 16px side padding. Spacing only from: 4, 8, 12, 16, 20, 24, 32,
   40, 48, 64.
10. Primary actions live in the bottom third (thumb zone). Destructive actions (cancel booking,
    erase my data) are never in the thumb's resting spot and always open a confirm sheet.
11. No confirm dialog on Mark complete. It is one tap.
12. Every screen needs 4 states: content, EMPTY (says what will appear + the one action that
    fills it), LOADING (static grey skeleton blocks shaped like the content — NO shimmer
    animation), ERROR (plain words + Try again; never "Something went wrong", never an error
    code), and OFFLINE (a quiet persistent banner, not a popup, saying what is waiting to sync).
13. Text must survive 200% system font size with nothing clipped: no fixed-height cards, labels
    wrap.
14. Hindi (Devanagari) text needs +2px line height and zero letter-spacing. Hinglish runs ~15%
    longer than English. Numbers stay 0-9 in every language.
15. Icons: ONE outline icon set (Material Symbols Outlined or Lucide), 24px, 2px stroke, always
    with a text label except back / close / overflow. No emoji as icons.
16. Motion: none on money (no counting up). No bounce/elastic. Sheets slide up. Keep it calm.

DO NOT DESIGN (these features deliberately do not exist)
- Any control that adds to or removes from a customer's wallet balance by hand, for owner or
  staff. The owner sees balances read-only.
- Any refund-to-bank or cash-withdrawal of wallet money.
- Any screen where the owner enters or sees payment-gateway / SMS keys or credentials.
- "Switch salon" or joining a second salon from the customer app.
- Changing the phone's app icon.
- The SMS text of the login code.
- Crayora logos or "Powered by" banners inside the app.
- Purple-blue gradients, glassmorphism, decorative gradients, cards inside cards, icon tiles above
  every heading, centred body text, stock photos of models.

TYPE SCALE (sizes/line heights; heading font for display–h2, body font for the rest)
display 32/38 · h1 24/30 · h2 20/26 · h3 17/24 semibold · body 15/22 · bodyStrong 15/22
semibold · caption 13/18 · micro 11/16 medium (chips only, never money or legal text) ·
moneyXL 34/38 semibold tabular · moneyL 22/26 · moneyM 17/22.

PAGE FRAME
Top app bar 56px with the salon wordmark/logo (left) and at most 2 icon actions (right) →
scrolling single column → optional sticky primary button 56px at the bottom above the safe area.
Customer app bottom navigation: Home · Book · Wallet · Me (icons + labels).
Owner app bottom navigation: Today · Customers · Dashboard · More (icons + labels).

FIRST, BUILD THE FOUNDATION ONLY
Create a "Foundations" page with: the colour variables in all modes (A, B, Neutral × light/dark),
the type scale, spacing scale, and a component library:
buttons (filled / tonal / outlined / text; 48 and 56 heights; disabled), text field with label
above + helper + error, 4-digit code field, OTP 6-box field, checkbox row, radio/choice card,
chip, list row, money display (Balance with its mandatory line / Amount with label / Delta with
+ or − and a status icon), stat tile (label on top, big number, optional "▲ 18% vs last Tue"),
bottom sheet, snackbar, offline banner, empty state, skeleton block, needs-attention row
(warning/danger icon + label + one action), app bar, bottom nav, badge.
Do not design screens yet. I will send them in the next messages.
```

---

## PROMPT 1 — Joining a salon (before login)

```
Using the foundation and rules from my first message, design the JOIN FLOW. Until screen 3 the
app is in the Neutral default mode (no salon known yet). From screen 3 onward it wears Brand A
("Studio Nine Salon") — this switch is the moment the white-label promise is kept, so make it
visible.

1. Splash / bootstrap — neutral, a simple centred mark and a thin progress indicator.
2. Enter your salon code
   - Title "Join your salon". A large "Scan the salon's QR code" button (opens camera) and, equal
     in weight below it, "Or type the code" with a code field formatted like CRAY-7KQ2MX.
   - States: typing; checking; "That code didn't match a salon. Check the card at the counter."
     (never "Invalid code"); "This salon isn't taking new customers in the app yet."; too many
     tries ("Try again in a few minutes").
   - Camera screen: viewfinder with a square guide, torch toggle, "Type the code instead" link.
     Camera permission refused → a friendly panel: "No camera? No problem." + code field. Typing
     is a first-class path, not an error.
3. Salon confirmation — now in Brand A: large salon logo, "You're joining Studio Nine Salon",
   area/address line, "Continue" (primary) and "Not your salon? Enter another code".
4. Phone number + consent notice (branded)
   - ABOVE the phone field, at body size, not collapsed, an itemised notice:
     "Studio Nine Salon will use your phone number to: • log you in • send your booking and
     visit updates • remind you when a service is due. Studio Nine Salon is responsible for your
     data. Questions: privacy@studionine.in"
     Then separate UNTICKED checkboxes per optional purpose: "Reminders when a service is due",
     "Offers from Studio Nine Salon". Required purposes are stated, not ticked.
   - Phone field with +91 prefix, 10 digits. Not auto-focused (focus would scroll the notice
     away). "Send code" sticky at the bottom.
5. Enter the code — branded; "We sent a 6-digit code to +91 98xxx x4821"; 6 OTP boxes; "Resend
   in 0:28" countdown then "Resend code"; states: wrong code ("That code didn't match. 2 tries
   left."), expired, "This number is already registered with a salon." (never name the other
   salon).
6. Welcome — "You're in. Welcome to Studio Nine Salon." + a card offering "Add Studio Nine Salon
   to your home screen" with "Add to home screen" and "Not now". (Android only — also show the
   iPhone variant where this card is simply absent.)
```

---

## PROMPT 2 — Customer: home, the visit, paying the bill, wallet

```
Customer app, Brand A, bottom nav (Home · Book · Wallet · Me). Follow all rules from my first
message, especially the money rules.

1. Home — ordinary day
   - App bar: salon logo/wordmark; right: a shield icon "Your data".
   - "Hi Asha" heading. A "Next haircut due around 14 Oct" card with "Book now".
   - Wallet summary card: balance ₹1,250 (moneyXL) with the mandatory line "Usable only at Studio
     Nine Salon. Cannot be withdrawn as cash." and buttons "Add money" and "View wallet".
   - Refer & Earn entry row. Active offer card (optional).
   - Empty variant for a brand-new customer (no visits, ₹0 wallet): explain what the app is for
     in two sentences + "Book your first visit".
2. Home — booking today (show the START CODE)
   - At the top: card "Your visit today · 4:30 PM · Haircut + Beard trim · with Suresh".
   - "Show this code to your stylist when you sit down." and the code 4 8 2 1 displayed VERY
     large (at least 48px, tabular, generous letter spacing), readable from arm's length.
   - Variant after the stylist starts: the code disappears; the card says "Your service is in
     progress." with a calm status chip.
3. "How would you like to pay?" bottom sheet — opens by itself when the work is finished
   (the customer also gets a push notification "Your bill is ready").
   - Title "How would you like to pay?", subtitle "To pay: ₹1,000".
   - Three large choice cards, NONE pre-selected, each a full-width row (icon, title, one line of
     explanation, chevron):
     • Wallet — "Pay ₹1,000 from your balance of ₹1,250. That is ₹750 you paid in and ₹250 bonus."
     • UPI — "Pay ₹1,000 with any UPI app."
     • At the counter — "Pay ₹1,000 in cash or by card at reception."
   - Variant: wallet SHORT of the bill (₹1,000 bill, ₹550 wallet = ₹500 paid + ₹50 bonus):
     Wallet card reads "Use all ₹550 in your wallet, then pay the other ₹450 by UPI or at the
     counter. That is ₹500 you paid in and ₹50 bonus."
   - Step 2 after the wallet is used: title "₹450 left to pay", subtitle "Your wallet has been
     used. How would you like to pay the rest?", only UPI and At the counter remain.
   - Result states inside the sheet: "Paid from your wallet." (then closes); UPI: "Payment sent.
     Your bill will show as paid once the bank confirms it." (never say "Paid" for UPI here);
     counter: "The counter knows. Your bill shows as paid once they take the money." + Close.
     Cancelled/failed UPI: "Payment cancelled. Nothing was charged." with the choices still there.
   - The bill also sits on Home as a card "Your bill is ready · ₹1,000 · Pay your bill"; variant
     "You said you will pay at the counter."
4. Wallet
   - Balance ₹1,250 + mandatory line. Breakdown shown separately: "Paid credit ₹1,000 — Money you
     pay never expires." and "Bonus credit ₹250 — ₹250 of bonus expires on 14 Nov 2026."
   - "Add money" primary button.
   - History list: date, description ("Top-up", "Bonus", "Used at the salon", "Bonus expired"),
     signed amount with + / − and a status icon (never colour alone): +₹1,000, −₹300.
   - Error state: never show a stale balance from cache — show "Couldn't load your wallet" + Try
     again.
5. Add money (the highest-risk screen — be plain and honest)
   - Amount chips: ₹500 · ₹1,000 · ₹2,000 · Other amount (nothing pre-selected until the customer
     taps, or ₹1,000 selected by the customer in the main mock).
   - Live line: "You get ₹100 extra." or "No bonus on this amount."
   - A "Before you pay" block ABOVE the pay button, at normal body size, not collapsed, listing:
     • You pay ₹1,000 → you get ₹1,100 in your wallet.
     • The ₹100 bonus expires on 28 Oct 2026.
     • Money you pay never expires.
     • Usable only at Studio Nine Salon. Cannot be withdrawn as cash.
     • A top-up cannot be refunded or taken out as cash.
   - Sticky button "Pay ₹1,000" (disabled while the offer is loading).
   - Result states on this same screen: sent ("Payment sent. Your credit appears as soon as the
     bank confirms it."), cancelled, failed, "This salon cannot take payments yet. Ask at the
     counter.", below minimum ("The smallest top-up here is ₹100.").
```

---

## PROMPT 3 — Customer: booking, visits, referrals, settings, your data

```
Customer app, Brand A. Same rules.

1. Book ① Choose a service — list grouped by category (Hair, Beard, Colour, Skin): name,
   duration, price. Tapping selects (brand-filled radio).
2. Book ② Add-ons — "Add anything?" Each row: checkbox (ALWAYS unticked at start), name,
   "+₹150", "+15 min". A running total and total duration at the bottom update instantly.
   "Skip" and "Continue" equally easy.
3. Book ③ Stylist and time — stylist chips ("Anyone", "Suresh", "Priya") then a date strip (next
   14 days) and a grid of available times only (no greyed-out times). A note when add-ons changed
   the length: "Times shown fit 60 minutes." Selected slot = brand filled, onPrimary text.
   Empty: "No free times on this day. Try another day."
4. Book ④ Review — service, add-ons, stylist, date/time, total (moneyL), cancellation policy in
   plain words, "Confirm booking". Error: "This slot was just taken. Pick another?"
5. Booking confirmed / Booking detail — date, time, services, stylist, total, status chip,
   "Reschedule" and "Cancel booking" (cancel opens a confirm sheet with the policy).
6. Visit history — list of past visits: date, services, stylist, amount paid, payment method.
7. Refer & Earn — the reward condition ABOVE the code: "Your friend gets ₹100 on their first
   paid visit. You get ₹100 when that visit is paid." Referral code big, Share button (WhatsApp
   share sheet), counts "2 pending · 3 earned", list of friends with status chips.
8. Me / Settings — name, phone (masked), Language (English / हिन्दी / Hinglish), Notifications,
   Your data, Help, and one small line at the bottom "App by Crayora".
9. Your data (privacy rights; plain, boring, trustworthy)
   - Per-purpose consent toggles (Reminders, Offers) — withdrawing is one tap, as easy as giving.
   - "Get a copy of your data" → shows the request and when it is due ("Ready by 12 Oct").
   - "Erase my data" — BEFORE asking, says what is kept: "Your bills and wallet records are kept
     for 8 years because the law requires it; your name and number are removed." Confirm sheet
     with a typed confirmation.
   - The salon's privacy contact (email/phone). Variant when the salon has none: "Studio Nine
     Salon hasn't added a privacy contact yet. Ask at the counter."
10. Language demo: render screens 1, 2 and Home from Prompt 2 in Hindi (Devanagari) and in
    Hinglish to prove nothing clips.
```

---

## PROMPT 4 — Owner: the day (the most important screens)

```
Owner app, Brand A, bottom nav (Today · Customers · Dashboard · More). The owner is standing,
one-handed, between customers. Big targets, bottom-reachable, zero confirmation dialogs on the
common actions. Same rules.

1. Today (day view)
   - App bar: salon wordmark, date "Tue 29 Sep" with ‹ › day arrows; right: a "Needs attention"
     icon with a red count badge, and a "+" for walk-in.
   - A quiet sync line when offline: "Offline · 1 change waiting to sync" (not an error style).
   - A list of booking rows. Each row: time (tabular), customer name, services, stylist, price on
     the right. The row's action depends on its state — show all five in one mock:
     a) Booked → a full-width 56px "Start" button + a small ✕ "Cancel booking" icon button.
     b) In progress → label "In progress" + a full-width 56px "Mark complete" button (ONE tap,
        no dialog).
     c) Done, unpaid → "✓ Done" + an outlined "Take payment" button.
     d) Done, customer said counter → "✓ Done · Paying at the counter" + "Take payment".
     e) Done, paid → "✓ Done · Paid" (success icon + word). Partly paid → "Done · Part paid".
     Also: a row with a small "waiting to sync" icon, and a Walk-in customer row.
   - Empty: "Nothing booked today." + "Add a walk-in".
2. Start sheet (bottom sheet from "Start")
   - "Start" title, "Ask the customer for the 4-digit code in their app.", a large 4-digit
     numeric field (centred digits), "Start with this code" (56px, disabled until 4 digits).
   - Wrong code: "That is not their code. 2 tries left."
   - Locked: "Too many wrong tries, so this code is locked. Start without it - the owner will see
     why." + "Start without the code".
   - Offline: "No connection, so the code cannot be checked. You can start without it - the
     owner will see why." + "Start without the code".
   - Customer has no app: no code field at all; "This customer does not have the app, so there is
     no code. Start without one - the owner will see it was started this way." + "Start without
     the code".
3. Take payment sheet
   - "Take payment · Asha · ₹1,000". Server-computed split shown as lines: "Already paid in the
     app ₹550", "From wallet ₹0", "Collect ₹450" (moneyL).
   - Toggle "Use wallet balance (₹X available)" when there is balance.
   - "The rest by": segmented Cash · UPI · Card (nothing pre-selected), "Record payment".
   - Offline state: "No connection, so the wallet balance cannot be checked. Collect the full
     amount, or wait until you are online to use the wallet." Queued: "Payment recorded. It will
     show as paid once it reaches the server."
4. Add walk-in — customer search/new (name + phone), service, add-ons (UNTICKED), stylist,
   next available times, "Book walk-in". Offline message: "Will book when you are online."
5. Needs attention — rows for actions the server refused: what ("Mark complete · Asha 4:30"),
   why in words ("That appointment was already finished or cancelled."), and "Try again" /
   "Discard". Empty: "Nothing needs attention."
```

---

## PROMPT 5 — Owner: customers, dashboard, menu, team, settings

```
Owner app, Brand A. Same rules.

1. Customers — search field (name or full phone number), list rows: name, last visit ("12 days
   ago"), visits count, wallet balance on the right (read-only). "As of 10:42" label when shown
   from cache. Empty and offline states.
2. Customer detail — name, masked phone, visits, last visit, wallet balance (read-only, with the
   mandatory line) and a clear note "Balances can't be changed here." Visit history list. There
   is NO adjust-balance control, no edit-balance field, nothing disabled pretending to be one —
   it is simply absent.
3. Dashboard (stat tiles first, charts only where shape matters)
   - 2×2 stat tiles: Today's revenue ₹12,450 (▲ 18% vs last Tue), Visits today 23, New
     customers this month 14, Outstanding wallet credit ₹38,200 ("Customers' prepaid money. It
     can't be changed here.").
   - "Starts without the code" tile: "This month 3 · with code 41" with a breakdown (code locked,
     no app, never started) — a trust signal for the owner.
   - Reminders card: sent, booked from a reminder, conversion %, spend — in ONE card.
   - Cohort retention chart: return rate at 30/60/90 days, two series only (Wallet customers =
     series1 blue, Non-wallet = series2 orange), legend AND direct labels, y-axis 0-100%, "n = 42"
     per cohort, a young cohort reads "not yet" (never 0%), and a table of the same numbers
     below.
   - A "numbers didn't match" warning row variant (drift alert).
4. Services (menu) — list by category with price and duration, "Add service"; edit form (name,
   category, price in ₹, duration, repeat cycle in days, Visible toggle — hidden instead of
   delete).
5. Add-ons — list with "+₹" and "+min", which services each applies to, add/edit form.
6. Team — staff list (name, active), add/edit; working hours per day.
7. Salon hours & holidays — weekly hours grid, holiday list, add holiday.
8. Rules — Wallet bonus rule shown plainly ("Every ₹500 topped up earns ₹50 bonus"), BONUS
   EXPIRY in days (owner can change it; note: "Changes apply to new bonus only. Bonus already
   given keeps its date."), reminder cycles per service (e.g. Haircut 25-35 days), cancellation
   policy text.
9. Billing (salon's subscription) — plan, status, next invoice, and messaging spend per channel
   (Push free, WhatsApp ₹, SMS ₹) ALWAYS beside reminder conversion; marketing-escalation setting
   (SMS default / WhatsApp opt-in).
10. Salon profile — display name, logo, colours shown read-only: "Branding is set up by Crayora.
    Contact support to change it."
11. More menu — Services, Add-ons, Team, Hours, Rules, Billing, Salon profile, Language, Log out.
```

---

## PROMPT 6 — Staff mode (later phase; design lighter)

```
Staff (stylist) app, Brand A, same chassis as the owner app but only their own work.
1. My schedule — today's assigned bookings with the same row states as the owner's day view
   (Start / In progress + Mark complete / Done).
2. Booking detail — services, add a service or add-on to the bill, tip entry, Mark complete.
3. My earnings — commission from completed visits this week/month as stat tiles and a list.
```

---

## PROMPT 7 — Proving the white-label and the states

```
Take these screens: Join ③ Salon confirmation, Customer Home (with start code), the "How would you
like to pay?" sheet, Wallet, Add money, and the Owner Today view. Render each:
(a) in Brand B "Kesar Unisex Salon" (maroon, Poppins/Hind, radius 6),
(b) in the Neutral default,
(c) in dark mode for Brand A,
(d) in Hindi (Devanagari) for Brand A,
(e) at 200% text size for Brand A,
and for Wallet and Today also the Empty, Loading (static skeleton, no shimmer), Error and Offline
states. Nothing may clip, overlap or become unreadable; surfaces must stay neutral in every brand.
```

---

## PROMPT 8 — Crayora console, part 1 (desktop, 1440 × 900)

```
Now the Crayora admin console, a desktop web app for Crayora's own operators who set up and run
salons. It wears CRAYORA's identity (not a salon's): a restrained dark-ink-on-warm-neutral look,
a single brand accent (use #2F4B8A), the same fixed status colours, body 14px, dense tables,
compact 36-40px rows, labels above fields, keyboard-friendly, left sidebar navigation (Salons,
New salon, Customers: binding, Wallet correction, Data-rights requests, Metrics, Flags, Audit
log). No decorative imagery.

1. Login (email + password) and MFA code step ("Enter the 6-digit code from your authenticator").
2. Salons list — table: name, city, status chip (Draft / Active / Suspended), plan, bind rate %,
   customers, last active; search and filters; "New salon".
3. Provision wizard — steps in a left rail: Identity → Branding → Catalogue → Rules →
   Integrations → Commercials → Owner. Each step a clean form with a persistent "Saved" state.
   Last step "Activate" is a separate, deliberate action (not automatic).
4. Salon overview — status, activation info, key numbers, quick links to each section.
5. Branding studio — left: fields (display name, primary, accent — max 4 colours, heading and
   body font from a curated list split into "Latin" and "Latin + Devanagari" sets, radius
   slider 0-24, logo/wordmark/splash uploads). Right: a LIVE PHONE PREVIEW of the customer home
   and a button, in light and dark. A contrast report with pass/fail per pairing (body ≥4.5:1,
   large/borders ≥3:1). "Publish" is BLOCKED with a clear reason when any check fails, or when
   the salon serves Hindi and the chosen font has no Devanagari.
6. Catalogue — services, add-ons (with which services they apply to), staff, rules tabs.
7. Credentials (Message Central, Razorpay, WhatsApp, RCS) — WRITE-ONLY: each shows
   "•••• 4821 · set 12 Sep by Rahul" and a status (Tested ✓ / Untested / Failed), "Replace" and
   "Test connection". There is NO reveal / show / copy button anywhere, because nothing can be
   read back.
8. QR pack — preview of the counter card (salon logo, QR, salon code CRAY-7KQ2MX, one line of
   instruction), "Regenerate" (typed-reason dialog) and "Download PDF".
9. Privacy settings for the salon — the salon's privacy contact (email/phone) shown to its
   customers, and the notice preview.
```

---

## PROMPT 9 — Crayora console, part 2

```
Continue the console. Same style.

1. Messaging — per salon: WhatsApp template status, RCS agent status, send and delivery-ack
   rates, COST PER CHANNEL, and OTP fallback count (times Crayora's own SMS account was used
   because the salon's failed) with an alert chip.
2. Billing & activation — record the offline setup fee, "Activate salon" (a deliberate action
   with a typed-reason dialog), subscription status, dunning timeline.
3. Support mode — start a time-boxed session with a required reason; while active a strong
   banner "Support mode · ends in 14:32 · reason: …", customer data MASKED.
4. Customer binding desk (super-admin only) — look up by EXACT full phone number + reason;
   result card; "Unbind" offered only if the customer has no history; "Transfer" needs the
   destination salon, a typed reason, the balance AS DISCLOSED (must match), and a tick "The
   customer was told". Every action audited.
5. Wallet correction — the only human path to a balance: lookup, current balance, correction
   amount (signed), mandatory typed reason, second-person approval note. Shown as a new ledger
   row, never an edit.
6. Data-rights requests — queue of copy/erasure requests per salon with due dates (red when
   overdue), status, and "Carry out erasure" (typed confirmation, explains that financial records
   are anonymised, not deleted).
7. Metrics — MRR, churn, activations, push : WhatsApp ratio, time to first bind (stat tiles +
   at most 3-series line charts, fixed chart palette).
8. Feature flags — per-salon toggles table.
9. Audit log — filterable table: time, actor, salon, action, reason, before/after diff drawer.
10. Destructive-action dialog pattern (suspend, unbind, transfer, correction): typed reason
    field (the reason becomes the audit entry), never a bare "Are you sure?".
```

---

## After Figma Make finishes

Export or share the file, and send me:

1. The Figma file link (view access), **or** screenshots of each screen named with its code
   (U2, C1, O1, K5 …).
2. The variables/tokens export if Figma Make produced one.

I will build from them, but `DESIGN.md` still governs anything the mocks get wrong — a
pre-ticked add-on, a brand-tinted card, or a missing wallet line will be built the correct way,
and I will tell you where the mock and the rules disagree.
