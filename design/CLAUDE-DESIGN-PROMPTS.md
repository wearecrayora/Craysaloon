# Claude Design prompts — Cray Salon, every screen

## How to use this

1. Start **one** Claude Design project called "Cray Salon".
2. If the project lets you attach files, attach **`DESIGN.md`** from this repo. It is the full design
   rulebook; the prompts below summarise it, but the file wins on anything they leave out.
3. Send **Prompt 0** first. It builds the design system and the prototype shell. Check it before
   going on; everything after builds on it.
4. Send Prompts 1–8 **one at a time, in order**, in the same project. Each adds screens to the same
   prototype.
5. When Claude Design gets a rule wrong, reply with just the rule, for example: *"Rule 6: add-ons
   must start unticked."* Fixing it early beats fixing it on sixty screens.

Phone screens are **360 × 800** (a mid-range Android). The console (Prompts 7–8) is desktop,
**1440 × 900**.

---

## PROMPT 0 — The brief, the design system, and the prototype shell

```
I need you to design every screen of "Cray Salon" as ONE clickable, high-fidelity prototype.
This first message is the brief, the design system and the rules. Build only the design system
and the prototype shell now; I will send the screens in the next messages.

═══ WHAT THE PRODUCT IS ═══
Cray Salon is a white-labelled Android app that local hair salons in India give to their
customers, plus an owner mode of the same app for the salon owner, plus a desktop admin console
for Crayora, the company that sells and sets up each salon.

- A customer joins ONE salon by scanning the salon's QR code or typing its salon code, then logs
  in with their phone number and an SMS code. From then on the app IS that salon's app: its name,
  logo, colours and fonts. The customer never sees "Cray Salon" or "Crayora" in the app, except
  one small line in Settings: "App by Crayora".
- Customers book services and optional add-ons, keep a prepaid wallet at the salon (top up by
  UPI, get a bonus), are reminded when their next haircut is due, refer friends, and pay their
  bill from the app.
- A visit: the customer arrives and shows a 4-digit START CODE from their app. The stylist types
  it and taps Start. When the work is done the stylist taps "Mark complete". The customer's app
  then asks "How would you like to pay?": Wallet, UPI, or At the counter.
- The owner runs the day from their phone: today's bookings, Start, Mark complete, Take payment,
  walk-ins, customers, a simple dashboard, and the service menu.
- Who uses it: owners standing between customers, one-handed, wet hands, a bright room, a cheap
  Android phone, an unreliable network. Customers who open the app once a month for two minutes.
  Many read Hindi.

═══ THE WHITE-LABEL CHASSIS ═══
This is not one look; it is a chassis that must survive whatever branding a salon picks. ONLY
these change per salon: brand primary colour, brand accent colour, heading font family, body font
family, logo/wordmark, one corner-radius number, and the display name. Everything else (layout,
spacing, type sizes, neutral surfaces, text colours, status colours, chart colours, icons) is
fixed for every salon.

Build every colour, font and radius as a CSS custom property. Never a raw colour on an element.
Three brands, each with light and dark:
- Brand A (default everywhere): "Studio Nine Salon". Primary #1F6F5C (deep teal; dark #7FD3BC),
  accent #C8A24A (muted gold; dark #E3C378), heading font "Tiro Devanagari Hindi", body font
  "Mukta", radius 14px.
- Brand B: "Kesar Unisex Salon". Primary #7A1F3D (maroon; dark #E7A0B8), accent #E0A96D (dark
  #F0C497), heading "Poppins", body "Hind", radius 6px.
- Neutral default: "Your salon". Primary #3D4A5C (slate; dark #A9B8CC), accent #8A94A3, heading
  and body "Noto Sans", radius 12px. Used when a salon's branding cannot load, and before the
  customer has joined a salon.
All fonts are on Google Fonts and all of them render Devanagari.

Colour roles (one CSS variable each):
- brand: --primary, --on-primary, --primary-container, --on-primary-container, --accent,
  --on-accent, --brand-ink.
  · --on-primary is black or white, whichever reaches 4.5:1 contrast on --primary. Compute it.
  · --brand-ink is the brand hue darkened (light mode) or lightened (dark mode) until it reaches
    4.5:1 on the surface. It is the ONLY way brand colour is ever used as text.
- surface (fixed, NOT themed): --surface #FAF9F6, --surface-alt #F3F2EE, --surface-sunken
  #ECEAE5, --overlay. Dark: --surface #161614, --surface-alt #1F1E1B, --surface-sunken #0F0F0E.
  Neutrals carry a slight warm hue: never pure #FFFFFF or #000000.
- ink (fixed): --text-primary #1C1B19, --text-secondary #4A4843, --text-muted #6E6B64 (dark
  mode: #EDEBE6, #C4C1BA, #9A968E).
- line (fixed): --border, --border-strong, --divider.
- status (fixed for EVERY salon, never brand-coloured): --success #0CA30C, --warning #FAB219,
  --danger #D03B3B, --info #2563A8. Status is always an icon PLUS a word, never colour alone.
- chart (fixed): --series-1 #2A78D6 blue, --series-2 #EB6834 orange, --series-3 #1BAF7A aqua.
  At most three series in any chart, ever.

Type scale (fixed; the heading font for display to h2, the body font for everything else):
display 32/38 · h1 24/30 · h2 20/26 · h3 17/24 semibold · body 15/22 · body-strong 15/22
semibold · caption 13/18 · micro 11/16 medium (chips and badges only) · money-xl 34/38 semibold ·
money-l 22/26 semibold · money-m 17/22 semibold. All money uses tabular figures
(font-variant-numeric: tabular-nums).
Devanagari text gets +2px line height and letter-spacing 0. Numbers are 0-9 in every language.

Spacing: 4px grid, only 4, 8, 12, 16, 20, 24, 32, 40, 48, 64. Screen side padding 16. Between
cards 12. Between sections 24.

Page frame (phone): top app bar 56px with the salon's logo/wordmark on the left and at most two
icon actions on the right, then a single scrolling column, then an optional sticky primary
button (56px) above the bottom safe area.
Customer app bottom navigation: Home · Book · Wallet · Me.
Owner app bottom navigation: Today · Customers · Dashboard · More.
Icons: one outline set only (Lucide or Material Symbols Outlined), 24px, 2px stroke, always with
a text label except back, close and overflow. No emoji as icons.

═══ HARD RULES (a screen that breaks one is wrong) ═══
1. Never tint backgrounds or cards with the brand colour. Surfaces stay neutral in every brand.
   Brand colour is only for filled buttons, the selected state, chips, small accents and the app
   bar wordmark.
2. Never put body text on the brand colour. Never grey text on a coloured background.
3. The salon logo appears once per screen, in the app bar. Not in cards.
4. Money: Indian grouping (₹1,20,500, not ₹120,500), whole rupees (₹550, not ₹550.00), tabular
   figures, a real minus sign (−₹200), zero is "₹0", and money is never smaller than 15px.
5. A wallet balance is NEVER shown alone. Directly under it, always: "Usable only at <Salon
   name>. Cannot be withdrawn as cash."
6. Nothing that costs money is pre-selected. Add-on checkboxes always start unticked. Payment
   choices start with nothing chosen.
7. Unavailable time slots and add-ons are removed, not greyed out or struck through.
8. Touch targets at least 48×48px and 8px apart. The owner's Start and Mark complete buttons are
   at least 56px tall.
9. One column on phones. Always.
10. Primary actions sit in the bottom third of the screen, where the thumb is. Destructive
    actions (cancel a booking, erase my data) never sit where the thumb rests, and always open a
    confirmation sheet first.
11. Mark complete is ONE tap. No confirmation dialog.
12. Every screen has five states: content; EMPTY (what will appear here, plus the one action that
    fills it); LOADING (static grey skeleton blocks shaped like the content, with NO shimmer or
    pulse animation); ERROR (plain words plus "Try again", never "Something went wrong", never an
    error code); OFFLINE (a quiet persistent banner, not a popup, saying what is waiting to sync).
13. Everything survives 200% text size: nothing clips, no fixed-height cards, labels wrap.
14. Motion: never animate a money value (no counting up). No bounce or elastic easing. Sheets
    slide up in about 220ms with a decelerating curve. Keep it calm.
15. Copy: short sentences with verbs. Never blame the user ("That code didn't match a salon", not
    "Invalid code"). Money copy is literal ("₹50 bonus expires 4 March 2027", never "Hurry!").
    Hindi must be natural and gender-neutral (no "करूँगा"/"करूँगी" forms). Hinglish runs about 15%
    longer than English; design for the longest.

═══ DO NOT DESIGN (these deliberately do not exist) ═══
- Any control for the owner or staff to add to or remove from a customer's wallet balance.
  Owners see balances read-only. Not even a disabled one.
- Any refund-to-bank or cash withdrawal of wallet money.
- Any screen in the app where the owner enters or sees payment-gateway or SMS keys.
- "Switch salon", or joining a second salon, from the customer app.
- Changing the phone's app icon.
- The SMS message of the login code.
- Crayora logos or "Powered by" banners inside the app.
- Purple-blue gradients, glassmorphism, decorative gradients, cards inside cards, an icon tile
  above every heading, centred body text, stock photos of models.

═══ WHAT TO BUILD NOW ═══
A. A design-system page: every colour variable in all six modes (A, B, Neutral × light, dark)
   with contrast ratios printed next to text pairs; the type scale in Latin and Devanagari; the
   spacing scale; and these components, each with its states: buttons (filled, tonal, outlined,
   text; 48 and 56px; disabled; busy), text field (label above, helper, error), 4-digit code
   field, 6-box OTP field, checkbox row, choice card (icon, title, one line of explanation,
   chevron), chip, list row, money displays (Balance with its mandatory line; Amount with a
   label; Delta with + or − and a status icon), stat tile (label on top, big number, optional
   "▲ 18% vs last Tue"), bottom sheet, snackbar, offline banner, empty state, skeleton block,
   needs-attention row (warning/danger icon, label, one action), app bar, bottom navigation,
   badge.
B. The prototype shell: a phone frame (360×800) in the middle; a left sidebar listing every
   screen by its code and name (I will send the list screen by screen: U1-U6, C1-C14, O1-O13,
   S1-S3, K1-K16); and a top control bar with switchers for:
   Brand (A / B / Neutral) · Light / Dark · Language (English / हिन्दी / Hinglish) ·
   Text size (100% / 200%) · State (Content / Empty / Loading / Error / Offline).
   Every switch must re-render the current screen live. This is how I will check the white-label
   promise and every state, so the switchers must work on every screen you add later.
Stop after A and B.
```

---

## PROMPT 1 — Joining a salon (U1–U6)

```
Add the join flow to the prototype. Until U3 the app uses the Neutral brand, because no salon is
known yet. From U3 onward it wears Brand A. That switch is the moment the white-label promise is
kept, so make it visible. Link the screens so I can click through.

U1 Splash: neutral, a simple centred mark and a thin progress bar.

U2 Join your salon
- Title "Join your salon". A large "Scan the salon's QR code" button, and equal in weight below
  it, "Or type the code" with a code field shaped like CRAY-7KQ2MX.
- States: typing; checking; "That code didn't match a salon. Check the card at the counter.";
  "This salon isn't taking new customers in the app yet."; "Too many tries. Try again in a few
  minutes."
- Camera view: viewfinder with a square guide, torch toggle, "Type the code instead".
- Camera permission refused: a friendly panel, "No camera? No problem.", with the code field.
  Typing is a first-class path, not an error.

U3 Salon confirmation (Brand A from here): the salon's logo large, "You're joining Studio Nine
Salon", the area line ("Indiranagar, Bengaluru"), "Continue" (primary), and "Not your salon?
Enter another code".

U4 Your phone number
- ABOVE the phone field, at body size, never collapsed, an itemised notice:
  "Studio Nine Salon will use your phone number to:
   • log you in
   • send your booking and visit updates
   • remind you when a service is due
   Studio Nine Salon is responsible for your data. Questions: privacy@studionine.in"
- Then separate UNTICKED checkboxes for the optional purposes: "Reminders when a service is due"
  and "Offers from Studio Nine Salon". Required purposes are stated, not ticked.
- Phone field with a fixed +91 prefix and 10 digits. NOT auto-focused, because focus would scroll
  the notice out of view. Sticky "Send code" button.

U5 Enter the code: "We sent a 6-digit code to +91 98xxx x4821", six boxes, "Resend in 0:28"
counting down, then "Resend code". States: "That code didn't match. 2 tries left."; "That code
has expired. We can send a new one."; "This number is already registered with a salon." (never
name the other salon).

U6 Welcome: "You're in. Welcome to Studio Nine Salon." and a card offering "Add Studio Nine
Salon to your home screen" with "Add to home screen" and "Not now". This card is Android-only:
add a small toggle to show the iPhone version, where the card is simply absent.
```

---

## PROMPT 2 — Customer: home, the visit, the bill, the wallet (C1–C4)

```
Add the customer app: Brand A, bottom navigation Home · Book · Wallet · Me. The money rules from
my first message matter most here.

C1 Home. Build these variants (a variant picker inside the screen is fine):
(a) Ordinary day
    - App bar: the salon's wordmark; on the right a shield icon labelled "Your data".
    - "Hi Asha". A card "Your next haircut is due around 14 Oct" with "Book now".
    - Wallet card: ₹1,250 (money-xl) with the mandatory line "Usable only at Studio Nine Salon.
      Cannot be withdrawn as cash.", and buttons "Add money" and "View wallet".
    - A "Refer & Earn" row. An optional offer card.
(b) Brand-new customer (no visits, ₹0 wallet): two sentences on what this app does for them, and
    "Book your first visit".
(c) Booking today, with the START CODE
    - First on the screen: a card "Your visit today · 4:30 PM · Haircut + Beard trim · with
      Suresh", then "Show this code to your stylist when you sit down." and the code
      4 8 2 1, VERY large (at least 48px, tabular, wide letter-spacing), readable at arm's length
      across a salon floor. A screen reader reads it as "Your start code: 4 8 2 1".
    - After the stylist starts: the code is gone, and the card reads "Your service is in
      progress."
(d) Bill ready: a card first on the screen, "Your bill is ready · Haircut + Beard trim · ₹1,000"
    with "Pay your bill". Variant: "You said you will pay at the counter."

The pay sheet: "How would you like to pay?" (a bottom sheet over C1)
It opens BY ITSELF when the work is finished; the customer also gets a push notification "Your
bill is ready". Build every step:
- Step 1. Title "How would you like to pay?", subtitle "To pay: ₹1,000". Three full-width choice
  cards (icon, title, one line of explanation, chevron), NONE pre-selected:
  · Wallet: "Pay ₹1,000 from your balance of ₹1,250. That is ₹750 you paid in and ₹250 bonus."
  · UPI: "Pay ₹1,000 with any UPI app."
  · At the counter: "Pay ₹1,000 in cash or by card at reception."
- Step 1, wallet SHORT of the bill (₹1,000 bill; ₹550 in the wallet = ₹500 paid + ₹50 bonus).
  The Wallet card reads "Use all ₹550 in your wallet, then pay the other ₹450 by UPI or at the
  counter. That is ₹500 you paid in and ₹50 bonus." If the wallet is ₹0, the Wallet card is
  not shown at all.
- Step 2, after the wallet is used: title "₹450 left to pay", subtitle "Your wallet has been
  used. How would you like to pay the rest?", and only UPI and At the counter.
- Results inside the sheet:
  · wallet covered it all: "Paid from your wallet." as a snackbar, and the sheet closes;
  · UPI: "Payment sent. Your bill will show as paid once the bank confirms it." and a Close
    button. Never say "Paid" here; the bank has not confirmed yet;
  · counter: "The counter knows. Your bill shows as paid once they take the money." and Close;
  · UPI cancelled: "Payment cancelled. Nothing was charged.", with the choices still there;
  · no connection: "No connection. Check your internet and try again."

C2 Wallet
- ₹1,250 with the mandatory line. Below, shown separately:
  "Paid credit ₹1,000: money you pay never expires." and "Bonus credit ₹250: ₹250 of bonus
  expires on 14 Nov 2026."
- "Add money" as the primary button.
- History: date, what it was ("Top-up", "Bonus", "Used at the salon", "Bonus expired") and the
  signed amount with + or − and a status icon, never colour alone: +₹1,000, −₹300.
- Error state: never show an old balance. "Couldn't load your wallet." and "Try again".

C3 Add money: the highest-risk screen in the product. Plain and honest.
- Amount choices ₹500 · ₹1,000 · ₹2,000 · ₹5,000, with ₹1,000 selected when the screen opens.
- A live line: "You get ₹100 extra." or "No bonus on this amount."
- A block headed "Before you pay", ABOVE the pay button, at body size, never collapsed, never
  behind a link:
  • You pay ₹1,000. You get ₹1,100 in your wallet.
  • The ₹100 bonus expires on 28 Oct 2026.
  • Money you pay never expires.
  • Usable only at Studio Nine Salon. Cannot be withdrawn as cash.
  • A top-up cannot be refunded or taken out as cash.
- A sticky "Pay ₹1,000" button, disabled while the offer is loading.

C4 Payment result (shown on C3 itself, not a new screen):
"Payment sent. Your credit appears as soon as the bank confirms it." · "Payment cancelled.
Nothing was charged." · "That payment did not go through. Nothing was charged." · "This salon
cannot take payments yet. Ask at the counter." · "The smallest top-up here is ₹100."
```

---

## PROMPT 3 — Customer: booking, history, referrals, settings, your data (C5–C13)

```
Continue the customer app, Brand A.

C5 Book ① Choose a service: grouped by category (Hair, Beard, Colour, Skin); each row has name,
   duration and price. Tapping selects it (brand-filled radio).
C6 Book ② Add-ons: "Add anything?" Each row has a checkbox that ALWAYS starts unticked, the name,
   "+₹150" and "+15 min". A running total and total time at the bottom change on the same tap,
   with no spinner. "Skip" and "Continue" are equally easy.
C7 Book ③ Stylist and time: stylist chips (Anyone, Suresh, Priya), a date strip for the next 14
   days, then a grid of AVAILABLE times only (never greyed-out times). When the add-ons changed
   the length, say so: "Times shown fit 60 minutes." Selected time: brand-filled with
   --on-primary text. Empty: "No free times on this day. Try another day."
C8 Book ④ Review: service, add-ons, stylist, date and time, total (money-l), the cancellation
   policy in plain words, "Confirm booking". Error: "This slot was just taken. Pick another?"
C9 Booking detail: date, time, services, stylist, total, a status chip, "Reschedule" and
   "Cancel booking". Cancelling opens a confirmation sheet that repeats the policy.
C10 Visit history: date, services, stylist, amount paid and how it was paid.
C11 Refer & Earn
   - Headline "Give ₹100, get ₹100". ABOVE the code, the condition: "Share your code. When your
     friend joins Studio Nine Salon and finishes their first paid visit, you both get credit in
     your wallets."
   - The code, large, with "Copy" and "Share" (the phone's share sheet).
   - "1 friend has joined and not visited yet · 3 earned", and a list of friends with status
     chips (Joined / Visited / Rewarded).
C12 Me (settings): name, phone (masked, 98xxx x4821), Language (English / हिन्दी / Hinglish),
   Notifications, Your data, Help, and at the very bottom one small line, "App by Crayora".
C13 Your data: plain, calm, trustworthy.
   - A toggle for each optional purpose (Reminders, Offers). Turning one off is one tap: exactly
     as easy as turning it on.
   - "Get a copy of your data", then a state showing the request and its due date ("Ready by
     12 Oct").
   - "Erase my data". BEFORE asking, say what is kept: "Your name and number are removed. Your
     bills and wallet records are kept, without your name, for as long as the law requires."
     Confirming opens a sheet where they type ERASE.
   - The salon's privacy contact (email and phone). Variant: "Studio Nine Salon hasn't added a
     privacy contact yet. Ask at the counter."
```

---

## PROMPT 4 — Owner: the day (O1–O3 and the sheets)

```
Add the owner app: Brand A, bottom navigation Today · Customers · Dashboard · More. The owner is
standing, one-handed, between customers. Big targets, the bottom third of the screen, and no
confirmation dialog on anything they do forty times a day.

O1 Today (the most important screen in the product)
- App bar: the salon's wordmark, the date "Tue 29 Sep" with ‹ › arrows; on the right a "Needs
  attention" icon with a red count badge, and "+" for a walk-in.
- When offline, a quiet line under the app bar: "Offline · 1 change waiting to sync". Not an
  error style; nothing is wrong.
- Booking rows: time (tabular), customer name, services, stylist, and the price on the right.
  The row's action depends on its state. Show all of these in the main mock:
  a) Booked: a full-width 56px "Start" button and a small ✕ icon button "Cancel booking".
  b) In progress: the label "In progress" and a full-width 56px "Mark complete" button. ONE tap,
     no dialog; the row changes at once.
  c) Done, not paid: "✓ Done" and an outlined "Take payment".
  d) Done, and the customer said counter in their app: "✓ Done · Paying at the counter" and
     "Take payment".
  e) Done and paid: "✓ Done · Paid" (success icon plus the word). Part paid: "✓ Done · Part
     paid".
  Also: a row with a small "waiting to sync" icon, and a "Walk-in customer" row.
- Empty: "Nothing booked today." with "Add a walk-in".

Start sheet (a bottom sheet from "Start")
- "Start" and "Ask the customer for the 4-digit code in their app.", a large 4-digit numeric
  field with centred digits, and "Start with this code" (56px, disabled until four digits).
- Wrong code: "That is not their code. 2 tries left."
- Locked: "Too many wrong tries, so this code is locked. Start without it - the owner will see
  why." and "Start without the code".
- Offline: "No connection, so the code cannot be checked. You can start without it - the owner
  will see why." and "Start without the code".
- Customer without the app: NO code field at all. "This customer does not have the app, so there
  is no code. Start without one - the owner will see it was started this way." and "Start
  without the code".

Take payment sheet
- "Take payment · Asha · ₹1,000". The split, as the server worked it out: "Already paid in the
  app ₹550", "From wallet ₹0", "Collect ₹450" (money-l).
- When there is wallet balance: "Use wallet balance (₹X available)".
- "The rest by": Cash · UPI · Card (nothing pre-selected), then "Record payment".
- Offline: "No connection, so the wallet balance cannot be checked. Collect the full amount, or
  wait until you are online to use the wallet." After recording offline: "Payment recorded. It
  will show as paid once it reaches the server."

O2 Add walk-in: find or add the customer (name and phone), service, add-ons (UNTICKED), stylist,
the next free times, "Book walk-in". Offline: "Will book when you are online."

O3 Needs attention: one row per action the server refused. What it was ("Mark complete · Asha ·
4:30 PM"), why, in words ("That appointment was already finished or cancelled."), and "Try
again" / "Discard". Empty: "Nothing needs attention."
```

---

## PROMPT 5 — Owner: customers, dashboard, menu, team, settings (O4–O13)

```
Continue the owner app, Brand A.

O4 Customers: a search field (a name, or a whole phone number), rows with the name, last visit
   ("12 days ago"), number of visits, and the wallet balance on the right, read-only. When shown
   from the phone's copy: "As of 10:42".
O5 Customer detail: name, masked phone, visits, last visit, the wallet balance read-only with its
   mandatory line and "Balances can't be changed here.", then the visit history. There is NO
   adjust-balance control: not a disabled one, not a hidden one. It is absent.
O6 Dashboard (stat tiles first; a chart only where the shape means something)
   - 2×2 stat tiles: Today's revenue ₹12,450 (▲ 18% vs last Tue) · Visits today 23 · New
     customers this month 14 · Outstanding wallet credit ₹38,200 ("Customers' prepaid money. It
     can't be changed here.").
   - "Started without the code": "This month 3 · with the code 41", with the reasons (code
     locked 1, no app 1, never started 1).
   - Reminders, in ONE card: sent 120, booked from a reminder 34, conversion 28%, spend ₹96.
   - Retention chart: return rate at 30 / 60 / 90 days, two series only (wallet customers =
     --series-1 blue, others = --series-2 orange), a legend AND direct labels on the lines, a
     0-100% axis that says so, "n = 42" per cohort, a young cohort reads "not yet" (never 0%),
     and a table of the same numbers under the chart.
   - A warning row: "Yesterday's numbers didn't match the visits. We've flagged it; nothing was
     changed."
O7 Services: grouped list with price and duration, "Add service"; the form has name, category,
   price in ₹, duration, repeat cycle in days, and a "Show to customers" toggle (a service is
   hidden, never deleted).
O8 Add-ons: list with "+₹" and "+min" and which services each goes with; add/edit form.
O9 Team: staff with an Active toggle; add/edit; working hours per day.
O10 Rules: the wallet bonus rule in plain words ("Every ₹500 topped up earns ₹50 bonus", set up
   by Crayora, read-only here); BONUS EXPIRY in days, which the owner CAN change, with "Changes
   apply to new bonus only. Bonus already given keeps its date."; reminder timing per service
   ("Haircut: 25-35 days"); the cancellation policy text.
O11 Hours and holidays: weekly hours, a holiday list, "Add holiday".
O12 Billing (the salon's own subscription): plan, status, next invoice; messaging spend per
   channel (Push free · WhatsApp ₹ · SMS ₹) ALWAYS shown beside how many reminders turned into
   bookings, never one without the other; the marketing follow-up setting (SMS by default,
   WhatsApp if chosen).
O13 Salon profile: display name, logo and colours, read-only: "Your branding is set up by
   Crayora. Contact support to change it."
More: Services, Add-ons, Team, Hours, Rules, Billing, Salon profile, Language, Log out.
```

---

## PROMPT 6 — Staff mode (S1–S3, a later phase: keep it light)

```
Add the stylist's app: Brand A, the same chassis as the owner app, but only their own work.
S1 My schedule: today's bookings assigned to them, with the same row states as O1 (Start / In
   progress + Mark complete / Done).
S2 Booking detail: services, add a service or add-on to the bill, a tip, Mark complete.
S3 My earnings: commission from completed visits this week and this month, as stat tiles and a
   list.
```

---

## PROMPT 7 — The Crayora console, part 1 (K1–K7, K9, desktop 1440×900)

```
Add the Crayora admin console: a desktop web app used by Crayora's own operators to set up and
run salons. Give it its own frame (1440×900) in the prototype and its own screen group in the
sidebar.

It wears CRAYORA's identity, never a salon's: dark ink on a warm neutral, one accent (#2F4B8A),
the same fixed status colours, body text 14px, dense tables with 36-40px rows, labels above
fields, fully usable from the keyboard, and a left navigation: Salons · New salon · Customer
binding · Wallet correction · Data-rights requests · Metrics · Flags · Audit log. No decorative
imagery. Forms show a persistent "Saved" state.

K1 Login: email and password, then an MFA step, "Enter the 6-digit code from your authenticator".
K2 Salons: a table (name, city, status chip Draft / Active / Suspended, plan, bind rate %,
   customers, last active), search, filters, "New salon".
K3 New salon (provisioning wizard): steps in a left rail, Identity → Branding → Catalogue →
   Rules → Integrations → Commercials → Owner. "Activate" is a separate, deliberate action at
   the end, never automatic.
K4 Salon overview: status, who activated it and when, the key numbers, links to each section.
K5 Branding studio
   - Left: display name; primary and accent colours (four colours at most); heading and body
     font from a curated list in two groups, "Latin only" and "Latin + Devanagari"; a radius
     slider 0-24; logo, wordmark and splash uploads.
   - Right: a LIVE phone preview of the customer home screen and a button, in light and dark,
     using the same token variables as the app, so the preview cannot lie.
   - A contrast report, pass or fail for every pairing (body text 4.5:1, large text and borders
     3:1).
   - "Publish" is BLOCKED, with the reason written out, when any check fails, or when the salon
     serves Hindi and a chosen font has no Devanagari.
K6 Catalogue: tabs for services, add-ons (and which services they go with), staff, rules.
K7 Credentials for Message Central, Razorpay, WhatsApp and RCS. WRITE-ONLY. Each shows
   "•••• 4821 · set 12 Sep by Rahul" and a status (Tested ✓ / Untested / Failed), with
   "Replace" and "Test connection". There is NO reveal, show or copy control anywhere, because
   nothing can be read back.
K9 QR pack: a preview of the counter card (the salon's logo, the QR code, the code CRAY-7KQ2MX,
   one line of instruction), "Regenerate" (asks for a typed reason) and "Download PDF".
Also: Salon privacy settings: the privacy contact (email and phone) that the salon's customers
see, and a preview of the notice on U4.
```

---

## PROMPT 8 — The Crayora console, part 2 (K8, K10–K16)

```
Continue the console. Same style.

K8 Messaging (per salon): WhatsApp template status, RCS agent status, send and delivery-ack
   rates, COST PER CHANNEL, and the OTP fallback count (how often Crayora's own SMS account was
   used because the salon's failed) with an alert chip.
K10 Billing and activation: record the offline setup fee; "Activate salon" as a deliberate action
   with a typed reason; subscription status; a dunning timeline.
K11 Support mode: start a time-boxed session with a required reason. While it runs, a strong
   banner: "Support mode · ends in 14:32 · reason: …", and all customer data MASKED.
K12 Customer binding desk (super-admins only): look up by the EXACT full phone number, with a
   reason. "Unbind" is offered only when the customer has no history. "Transfer" needs the
   destination salon, a typed reason, the balance AS DISCLOSED (it must match), and a tick "The
   customer was told". Every action is audited.
K13 Wallet correction, the ONLY human path to a balance: look up, the current balance, a signed
   correction amount, a mandatory typed reason. It is shown as a new ledger row, never as an
   edit.
K14 Metrics: MRR, churn, activations, push-to-WhatsApp ratio, time to first bind. Stat tiles,
   plus line charts with at most three series in the fixed chart colours.
K15 Feature flags: a per-salon table of toggles.
K16 Audit log: a filterable table (time, who, salon, action, reason) with a drawer showing the
   before and after.
Data-rights requests: a queue of copy and erasure requests across salons, with due dates (red
   when overdue), status, and "Carry out erasure" (a typed confirmation that explains financial
   records are anonymised, not deleted).
Pattern for every destructive action (suspend, unbind, transfer, correction, regenerate QR): a
typed-reason dialog, where the reason becomes the audit entry. Never a bare "Are you sure?".
```

---

## PROMPT 9 — The final check (send last)

```
Go through every screen in the prototype and check it against the rules in my first message.
For each screen, try all five switchers: Brand A / B / Neutral, light and dark, English / Hindi
/ Hinglish, 100% and 200% text, and Content / Empty / Loading / Error / Offline.
Fix anything that clips, overlaps, tints a surface with the brand colour, shows a wallet balance
without its line, pre-selects something that costs money, uses colour alone for a status, or
animates money. Then give me a short list of what you fixed, and anything you could not fix.
```

---

## When Claude Design is done

Send me the prototype link (or the exported HTML/code) and, if it produced one, the tokens file.
I will build the Flutter screens and the console from it. `DESIGN.md` still governs anything the
mocks get wrong: I will build the correct version and tell you where the mock and the rules
disagree.
