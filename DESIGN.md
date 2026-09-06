# Cray Salon — Design System

**The visual and interaction rules. Read before building any screen.**

| | |
|---|---|
| **Applies to** | Flutter app (customer / owner / staff), **Android and iOS**, and the Next.js console |
| **Companions** | `RULES.md` (binding) · `ARCHITECTURE.md` (mechanisms) · `Cray-Salon-PRD-v4.md` (scope) · `PHASES.md` (order) · `IMPLEMENTATION.md` (screen inventory) |
| **Authoritative for** | design tokens, typography, layout, components, motion, chart rules |
| **Status** | Binding. §3 and §14 are not stylistic opinions |

> **The single constraint that shapes everything here:** this app is **white-labelled per salon**.
> Colour, fonts, logo and corner radius are supplied by a salon we have never met, chosen by an
> operator in a hurry. The design system is therefore a **chassis that must survive arbitrary
> branding** — not a look. Read §3 before anything else.

---

## 1. Who is using this, and where

Design for the actual room, not for a screenshot.

| User | Context | What that forces |
|---|---|---|
| **Salon owner** | Standing, one-handed, phone in the other hand or wet hands, between customers, on a cracked mid-range Android in a bright room | Large targets, bottom-reachable actions, high contrast, forgiving taps, no precision gestures |
| **Barber** (Tier 2) | Same, but mid-cut and faster | Mark-complete must be reachable and unmissable |
| **Customer** | Opens the app maybe once a month, for two minutes | Zero learning curve, no hidden navigation, nothing to remember between visits |
| **Crayora operator** | Desktop, console, doing the same setup repeatedly | Density, keyboard flow, defaults, no decorative chrome |

Two facts about the device that are not negotiable: **the network is unreliable** and **the phone
is slow**. Every screen has an offline state, and no screen may depend on an animation completing.

**Android ships first; the design is written for both.** The launch is Android-only for cost
reasons, not design ones (`RULES.md` §8.11). **One design language — these tokens — renders on
both platforms.** For a white-labelled app the salon's identity matters more than platform-native
chrome, and maintaining two design languages would double the surface for half the benefit. What
we *do* respect per platform: safe areas, back-gesture behaviour, text-scaling limits, and the
launcher-icon reality (`ARCHITECTURE.md` §7.3) — where iOS has no equivalent of the Android
pinned shortcut, so its branding is in-app only.

---

## 2. Principles

1. **The app belongs to the salon, not to Crayora.** Crayora branding appears in exactly two
   places: the app's Play Store listing, and a single line in Settings. Nowhere else.
2. **Money is never ambiguous.** Every amount states what it is, whose it is, and what will happen
   to it. If a number could be misread as something the customer can withdraw, rewrite it.
3. **One tap for the thing that matters.** Mark-complete drives every automation in the product.
   It is one tap from the day view, always, offline included.
4. **Nothing is pre-selected that costs money.** Add-ons start unchecked. Always. (`RULES.md` §2)
5. **Say the constraint before the action, not after.** Expiry and non-refundability appear on the
   Add Money screen, not on a terms page reached afterwards.
6. **Legible beats beautiful.** A salon may choose a pale palette and a display font. The system
   protects the reader from that choice (§3.3).
7. **Boring where it counts.** Money, consent and confirmation screens use the plainest possible
   presentation. Delight belongs to empty states and the referral flow.

---

## 3. The white-label chassis

### 3.1 What varies, what is fixed

| Varies per salon | **Fixed across all salons** |
|---|---|
| Brand primary, accent, and their derived steps | The neutral surface and ink ramps |
| Heading and body font **family** | The type **scale**, weights, and line heights |
| Logo, wordmark, splash, notification large icon | Every layout, spacing value and grid |
| Corner radius (one number) | Motion durations and easing |
| Display name | Status colours (success / warning / danger / info) |
| — | **Chart colours** (§9) |
| — | Iconography |

A salon changes how the app *feels*. It never changes how the app *works* or how it is *read*.

### 3.2 Token schema

This is the authoritative schema. `ARCHITECTURE.md` §7.1 shows an abbreviated example of the same
document; where they differ, this file wins.

```jsonc
{
  "version": 7,
  "displayName": "Studio Nine Salon",

  "brand": {
    "light": { "primary": "#1F6F5C", "accent": "#C8A24A" },
    "dark":  { "primary": "#7FD3BC", "accent": "#E3C378" }
  },

  "typography": {
    "heading": { "family": "Fraunces",   "weight": 600 },
    "body":    { "family": "Inter Tight", "weight": 400 },
    "script":  "latin"                     // or "devanagari" — see §5.3
  },

  "shape": { "radius": 14 },

  "assets": {
    "logo":              "…/logo.<hash>.png",
    "wordmark":          "…/wordmark.<hash>.svg",
    "splash":            "…/splash.<hash>.png",
    "notificationLarge": "…/notif.<hash>.png"
  }
}
```

**The operator supplies four colours at most.** Everything else — hover states, disabled states,
containers, text-on-brand, borders — is **derived at publish time**, never entered by hand. An
operator choosing twelve colours is an operator choosing twelve accessibility failures.

### 3.3 Guardrails — how the system survives a bad palette

These run at publish time in the console (`ARCHITECTURE.md` §14.2) and are not optional.

| Guardrail | Rule |
|---|---|
| **`onPrimary` is computed, never chosen** | Black or white, whichever reaches ≥4.5:1 against the brand primary. If neither does, the palette is rejected |
| **Brand primary is never a text colour on an arbitrary surface** | For text on `surface`, the system derives `brandInk` — the brand hue darkened (light mode) or lightened (dark mode) until it clears 4.5:1 |
| **Brand primary never sits behind body text** | It may fill buttons, chips, active indicators and small accents. A paragraph never sits on it |
| **Status colours are never themed** | `success` / `warning` / `danger` / `info` are fixed. A salon whose brand is red does not get a red "success" |
| **Chart colours are never themed** | §9 |
| **Contrast gate** | Publish is **blocked** if any derived pairing fails: body text ≥4.5:1, large text and UI borders ≥3:1 |
| **Radius is clamped** | Operator value clamped to 0–24. Derived: `chip = clamp(radius/2, 6, 12)`, `sheet = radius × 1.5`, `pill = 999` |
| **Fallbacks are real** | If branding cannot be fetched, render the neutral default. Never a half-themed screen, and **never another salon's branding** (`RULES.md` §8.6) |

### 3.4 Colour roles

Consume roles, never raw hex. CI rejects `Color(0x…)` outside the token layer (`RULES.md` §8.4).

```
brand      primary · onPrimary · primaryContainer · onPrimaryContainer
           accent · onAccent · brandInk
surface    surface · surfaceAlt · surfaceSunken · overlay
line       border · borderStrong · divider
ink        textPrimary · textSecondary · textMuted · textOnBrand
status     success · warning · danger · info   (fixed)
chart      series1–3 · sequential · divergingLow/Mid/High · gridline  (fixed, §9)
```

**Surface and ink ramps are fixed**, tuned once for readability in bright daylight, and are not
tinted by the brand. A salon's identity comes through in the brand roles, the logo and the type —
tinting every surface is how a white-label app becomes unreadable at a window seat.

---

## 4. Layout

### 4.1 Grid and spacing

**4dp base.** Permitted values only: `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64`.
No other spacing number appears in the codebase.

| Use | Value |
|---|---|
| Screen horizontal padding | 16 |
| Between related elements | 8 |
| Between a label and its field | 4 |
| Between cards in a list | 12 |
| Between sections | 24 |
| Above a section heading | 32 |
| Bottom safe area above a sticky action | 16 + system inset |

### 4.2 Page frame

```
┌─────────────────────────────┐
│ App bar — salon wordmark    │  56dp. Salon identity lives here and nowhere else on the page.
├─────────────────────────────┤
│                             │
│ Scrolling content           │  16dp side padding. Single column. Always.
│                             │
├─────────────────────────────┤
│ Sticky primary action       │  Optional. 56dp tall + safe inset.
└─────────────────────────────┘
```

**One column. Always.** No side-by-side content below 600dp, which is every phone this ships to.

### 4.3 Reach

Phones are used one-handed. The **bottom third is the action zone**: primary buttons, mark-complete,
Add Money, Book Now. The top is for identity and reading. Destructive actions never sit in the
thumb's resting arc — cancel and refund live behind a confirm sheet, not on the surface.

### 4.4 Touch targets

- **Minimum 48×48dp**, always, including icon buttons.
- **Mark-complete: 56dp minimum**, with its own row-level tap area on the day view.
- 8dp minimum between adjacent targets.
- A target may be larger than its visual — a 24dp icon inside a 48dp hit box is correct.

---

## 5. Typography

### 5.1 The scale

Fixed across all salons. Only the *family* varies.

| Role | Size / line | Weight | Use |
|---|---|---|---|
| `display` | 32 / 38 | heading | Onboarding, empty-state headline. One per screen at most |
| `h1` | 24 / 30 | heading | Screen title |
| `h2` | 20 / 26 | heading | Section |
| `h3` | 17 / 24 | 600 | Card title, list group |
| `body` | 15 / 22 | 400 | Default. **Never smaller for anything a customer must read** |
| `bodyStrong` | 15 / 22 | 600 | Emphasis inside body |
| `caption` | 13 / 18 | 400 | Secondary metadata, timestamps |
| `micro` | 11 / 16 | 500 | Chip labels, badges. **Never for money, never for a legal disclosure** |
| `moneyXL` | 34 / 38 | 600 tabular | Wallet balance, revenue hero |
| `moneyL` | 22 / 26 | 600 tabular | Card totals, stat tiles |
| `moneyM` | 17 / 22 | 600 tabular | Line items, list rows |

**All money uses tabular figures** (`fontFeatures: [FontFeature.tabularFigures()]`). Amounts in a
column must align on the decimal, always.

### 5.2 Roles, not sizes

Widgets reference `AppText.body`, never `fontSize: 15`. A screen that needs a size not in the table
is a screen that needs redesigning.

### 5.3 Devanagari — a real constraint, not an afterthought

The app ships in `en`, `hi` and `hi_Latn` from day one. Hindi is written in Devanagari, and that
changes typography in ways Latin-only design misses:

1. **Most display fonts have no Devanagari coverage.** A salon that serves Hindi customers cannot
   have a heading font that renders their language as boxes. The curated font allow-list is
   therefore **split into two sets** — `latin` and `latin+devanagari` — and a salon whose languages
   include `hi` may only choose from the second. The console enforces this; it is not a suggestion.
2. **Devanagari needs more vertical room.** The shirorekha (the top bar) and deep descenders make
   the same point size feel cramped. **Add 2dp to line height on every role when rendering
   Devanagari**, applied by the text theme, not per widget.
3. **Never tighten letter-spacing on Devanagari.** Negative tracking breaks conjunct glyphs.
   `letterSpacing: 0` for `hi`; the small negative tracking used on Latin headings is Latin-only.
4. **Hinglish (`hi_Latn`) is Latin script.** It uses the Latin metrics but tends to run ~15% longer
   than English. Every layout must survive that without truncating — test with the longest locale,
   not the shortest.
5. **Numerals stay Latin (`0–9`) in all three locales.** Indian users read prices in Latin digits;
   Devanagari numerals would be actively confusing on a bill.

### 5.4 Font allow-list

Operators choose from a curated Google Fonts list (`RULES.md` §7, PRD §16A.5) — not arbitrary
uploads, for licensing and app-size reasons. The list is maintained with:

- a `latin` set and a `latin+devanagari` set (§5.3);
- variable fonts preferred (one file, many weights);
- no font whose x-height is so small it fails at `body` size;
- at most two families per salon — one heading, one body — and pairing them is the operator's only
  typographic decision.

**Never block first paint on a font download.** Render with the bundled fallback and swap when
ready (`RULES.md` §8.5). The bundled fallback covers Devanagari.

### 5.5 Number and money formatting

- **Indian grouping**, not thousands: `₹1,20,500` — not `₹120,500`. Use `NumberFormat.currency(locale: 'en_IN')`.
- **Whole rupees by default.** `₹550`, not `₹550.00`. Show paise only when non-zero.
- The `₹` symbol is **never** separated from its number by a line break.
- Negative amounts are `−₹200` with a real minus sign (U+2212), never a hyphen, and never
  parenthesised.
- A zero balance renders as `₹0`, never as an em-dash or a blank.

---

## 6. Components

Beyond the standard set, these are the components this product actually turns on.

### 6.1 Money display

Three variants, and choosing the wrong one is a defect:

| Variant | Use | Rule |
|---|---|---|
| **Balance** | Wallet, `moneyXL` | Always accompanied by "usable only at &lt;Salon&gt;". Never alone |
| **Amount** | Line items, totals, `moneyM`/`moneyL` | Labelled with what it is |
| **Delta** | Ledger history, `moneyM` | Signed, with a status colour **and** a `+`/`−`, never colour alone |

### 6.2 Wallet card

Shows balance, the salon name, last visit, and two actions: **Add Money** and **Use at Checkout**.
Paid and bonus are shown **separately** when the customer expands the breakdown — the summary is one
number, the detail is honest.

**The Add Money screen must show, above the pay button** (`RULES.md` §5.3.6): bonus amount, bonus
expiry date, "paid credit never expires", "usable only at this salon", "cannot be withdrawn as
cash". Body size, not caption. Not collapsed. Not behind a link.

### 6.3 Add-on selector

- Every add-on renders **unchecked**. There is no code path that pre-checks one.
- Each row: name, `+₹price`, `+N min`.
- The running total and duration update **immediately** on toggle — no debounce, no spinner.
- Unavailable add-ons are removed, not disabled-and-greyed. A greyed row is an advertisement for
  something the customer cannot have.

### 6.4 Day-view row

The most important component in the product.

```
┌────────────────────────────────────────────────┐
│  10:30   Ramesh K.          Haircut + Beard    │
│          ₹450 · Suresh                    [✓]  │  ← 56dp target, right edge
└────────────────────────────────────────────────┘
```

- The `[✓]` is **mark-complete**. One tap. No confirm dialog.
- Feedback is **immediate and local** — the row settles into its completed state at once, whether
  or not the network responded. Offline is the normal case, not the exception.
- A queued (unsynced) row carries a small sync indicator. It is **not** an error style — nothing is
  wrong, it just hasn't reached the server.
- A **rejected** row moves to the "Needs attention" inbox with a reason and a one-tap fix
  (`RULES.md` §9.6). It never vanishes.

### 6.5 Slot picker

- Available slots only. Unavailable times are absent, not struck through.
- Duration is derived from service + selected add-ons, so the grid **changes when add-ons change** —
  make that visible, don't let it happen silently.
- Selected slot is filled with brand primary; text on it uses computed `onPrimary` (§3.3).

### 6.6 Stat tile

The dashboard's cards are **stat tiles, not charts** — a single number's job is to be read, and a
chart around it adds nothing.

```
Today's revenue
₹12,450          ← moneyXL, textPrimary
▲ 18% vs last Tue ← caption, status colour + arrow glyph, never colour alone
```

- Label above, value below. Never the reverse.
- A comparison is optional; when present it names its baseline. "▲ 18%" without "vs what" is noise.
- Maximum **four tiles per row group** on mobile — two columns, two rows. Beyond that, the owner is
  scanning rather than reading.

### 6.7 Needs-attention row

Used for rejected offline actions and failed sends. Carries: what failed, why, and one action.
Uses `warning` (recoverable) or `danger` (needs a decision) with an **icon and a label** —
never colour alone.

### 6.8 State components

Every screen implements four states. A screen with only the happy path is not done (`RULES.md` §12).

| State | Rule |
|---|---|
| **Empty** | Says what will appear here and gives the one action that fills it. Never an illustration with no next step |
| **Loading** | Static skeletons matching the final layout. **No shimmer sweep** — see §7.4 |
| **Error** | Says what failed in plain language and offers retry. Never a code, never "something went wrong" |
| **Offline** | A persistent, quiet banner — not a modal. The app keeps working; say what is queued |

---

## 7. Motion

### 7.1 Durations and easing

| Token | Duration | Use |
|---|---|---|
| `motion.micro` | 120ms | State change, toggle, ripple, checkbox |
| `motion.standard` | 220ms | Card enter, sheet, expand/collapse |
| `motion.large` | 280ms | Page transition |
| `motion.exit` | ×0.8 of enter | Exits are always faster than entrances |

```
enter / standard   cubic-bezier(0.2, 0, 0,   1)   // decelerate
exit               cubic-bezier(0.3, 0, 1,   1)   // accelerate
```

**No bounce, no elastic, no overshoot, ever.** It reads as dated, it costs frames on low-end
hardware, and on a money screen it reads as instability.

### 7.2 What animates

Motion exists to explain a change in state — where something came from, or what it became.

| Do animate | How |
|---|---|
| Sheets and dialogs | Slide + fade from the edge they belong to |
| Expand / collapse | Height with `standard`, content fades in at 60% through |
| List insertion | Fade + 8dp rise. Never a slide across the screen |
| Selection | `micro` fill and border change |
| Add-on toggle → total | The **total** cross-fades to its new value. It does not count up |

### 7.3 What must never animate

- **Money.** No count-up, no roll, no ticker. A balance that animates reads as unsettled — the
  customer is watching their own money move for no reason. Amounts appear at their final value.
- **Anything that delays mark-complete.** The day-view tap responds on the frame it is received.
- **Anything on first paint.** No staggered entrance on a list the user is waiting for.
- **Route transitions carrying a form the user has begun.** Never re-animate a partially filled
  screen.

### 7.4 Reduced motion and slow devices

- Honour `MediaQuery.disableAnimations`. When set, replace slide and scale with a 100ms fade.
  **Never remove feedback entirely** — a state change with no acknowledgement reads as a failed tap.
- **Skeletons do not shimmer.** A shimmer sweep is a continuously animating gradient across the
  whole screen — the single worst thing to run on a budget Android while it is also fetching. Use a
  static neutral block.
- Any animation that cannot hold 60fps on the target device is deleted, not degraded.

---

## 8. Content and tone

- **Short sentences. Verbs.** The owner is reading this between customers.
- **Bilingual by construction.** Every string is in ARB from the start; no string is composed by
  concatenation, because word order differs across `en` / `hi` / `hi_Latn`.
- **Never translate the salon's display name**, a person's name, or a service name the owner typed.
- **Money copy is literal.** "₹50 bonus expires 4 March 2027." Not "Hurry! Offer ending soon."
- **Errors name the thing.** "This slot was just taken. Pick another?" — not "Booking failed."
- **Never blame the user.** "That code didn't match a salon" — not "Invalid code."
- Hinglish is the register many owners actually prefer; keep it natural, not transliterated English.

---

## 9. Data display and charts

**Charts are brand-neutral. This is a rule, not a preference.**

A per-salon palette cannot be validated for colour-vision deficiency at scale — one salon's brand
hues will inevitably collide under deuteranopia, and we would ship an unreadable chart to that
salon and never hear about it. So chart colours are **fixed across every salon**. The salon's
identity is carried by the chrome around the chart, not the marks inside it.

### 9.1 The fixed chart palette

Three categorical slots, validated for all-pairs separation in both light and dark modes:

| Slot | Hue | Light | Dark |
|---|---|---|---|
| `series1` | blue | `#2a78d6` | `#3987e5` |
| `series2` | orange | `#eb6834` | `#d95926` |
| `series3` | aqua | `#1baf7a` | `#199e70` |

Validated: worst all-pairs CVD ΔE 9.2 light / 9.4 dark (≥8 target); normal-vision ΔE 24.0 light /
20.9 dark (≥15 floor). One documented relief case — aqua sits at 2.74:1 on the light surface, below
3:1 — which is satisfied by construction here because every chart in this product has ≤3 series and
therefore carries **direct labels** (§9.3).

**Three is the cap.** A fourth series folds into "Other" or becomes small multiples. Do not add a
fourth hue.

- **Sequential** (magnitude, one hue light→dark): blue ramp, `#cde2fb` → `#104281`.
- **Diverging** (polarity): blue ↔ red with a **neutral gray** midpoint (`#f0efec` light,
  `#383835` dark). Never a hue at the midpoint, never a rainbow.
- **Status** (`success` `#0ca30c` · `warning` `#fab219` · `danger` `#d03b3b` · `info`) is reserved.
  A status colour is **never** reused as a series, and always ships with an icon and a label.

Dark mode values are **selected steps for the dark surface**, not an automatic inversion.

### 9.2 Choosing the form

Ask what the number's job is before choosing anything:

| Job | Form |
|---|---|
| A single headline figure | **Stat tile** (§6.6) — not a chart |
| Magnitude across a few categories | Horizontal bar |
| Change over time | Line |
| Return rate by cohort, two segments | Grouped bar or two lines |
| Part-of-whole | Say the number. A pie chart of three services is worse than three sentences |

**Never a dual-axis chart.** Two measures of different scale become two charts, or are indexed to a
common base. This is the most common chart mistake there is.

### 9.3 Marks and anatomy

- Lines 2px. Markers ≥8px. Bars with 4px rounded ends anchored to the baseline.
- **2px surface-coloured gap** between adjacent fills and stacked segments; a 2px surface ring where
  marks overlap.
- Grid and axes are recessive — `gridline` token, never full-strength ink.
- **Selective direct labels**, never a number on every point. With ≤3 series, label every series
  directly *and* keep a legend for ≥2.
- **Text wears ink tokens, never the series colour.** The coloured mark beside a label carries the
  identity; the label itself stays `textPrimary` / `textSecondary`.
- Colour follows the **entity**, never its rank. Filtering out a series must not repaint the
  survivors.

### 9.4 The cohort retention chart

The product's one genuinely analytical view: return rate at 30 / 60 / 90 days, wallet vs non-wallet.

- Two series → `series1` (wallet) and `series2` (non-wallet), fixed assignment.
- Legend present **and** both directly labelled.
- Y axis is a percentage, `0–100`, and says so.
- A tooltip on hover/tap gives the exact figures and the cohort size — a rate without an `n` is a
  claim without evidence, and with a 12-customer cohort it is noise.
- Below the chart, a **table view** of the same numbers. It is the accessibility fallback and it is
  also what the owner will screenshot.

### 9.5 Interaction

Charts are interactive by default: a tooltip on tap for bars and points, a crosshair for lines. Hit
targets are larger than the marks. On mobile, tap-to-pin rather than hover.

---

## 10. Iconography and imagery

- **One icon set**, outline, 24dp on a 48dp target, 2px stroke. Never mix two sets.
- Icons carry meaning **with** a label, not instead of one. The only unlabelled icons permitted are
  back, close and overflow.
- **No decorative icon tile above every heading.** (§14)
- Photos are the salon's own work, always consented (`RULES.md` §11.4), compressed client-side,
  and never stretched. No stock photography of models anywhere in the product.
- The salon logo appears **once per screen** — in the app bar. Not repeated in cards.

---

## 11. Accessibility

Non-negotiable, and checked at publish for the salon's own palette (§3.3).

- Body text ≥ **4.5:1**. Large text and UI borders ≥ **3:1**.
- Targets ≥ **48×48dp**; 8dp apart.
- Every interactive element has a semantic label. Icon-only buttons have a tooltip *and* a label.
- **Text scales to 200%** without clipping or overlap. Test every screen at max system font size —
  this is where fixed-height cards break.
- **Never colour alone.** Status carries an icon and a label; chart series carry direct labels.
- Focus order follows reading order. Sheets trap focus and restore it on dismiss.
- Respect reduced motion (§7.4).

---

## 12. The console (Next.js on Vercel)

Same tokens, different context: desktop, an operator repeating a task, no white-labelling of the
console itself.

- The console wears **Crayora's** identity. Salon branding appears only inside the **branding
  preview**, which renders from the **shared token package** so the preview cannot lie about what
  the customer will see (`ARCHITECTURE.md` §7.2).
- **Density over comfort.** Tighter spacing than the app: 8dp base rhythm, compact table rows.
- **Forms are the product.** Labels above fields, inline validation on blur, a persistent save
  state, and keyboard-completable in one pass.
- Destructive and irreversible actions — suspend, unbind, transfer, wallet correction — use a
  **typed-reason dialog**, never a bare confirm. The reason field is the audit entry
  (`RULES.md` §6.5).
- Secrets render as `•••• 4821` with a *Test connection* button and no reveal control, because
  there is nothing to reveal (`RULES.md` §11.1).

---

## 13. Definition of done (design)

- [ ] Renders correctly under **three test brandings**: a dark brand, a pale brand, and the neutral
      default
- [ ] Renders correctly in **light and dark**, both stamped and system
- [ ] Renders correctly in `en`, `hi` (Devanagari metrics) and `hi_Latn` (longest strings)
- [ ] Readable at **200% text scale** with no clipping
- [ ] Empty, loading, error and **offline** states all implemented
- [ ] All targets ≥48dp; primary action reachable one-handed
- [ ] All money uses tabular figures and Indian grouping
- [ ] No raw hex, no raw font size, no spacing value outside the scale
- [ ] Reduced-motion path verified; no shimmer
- [ ] Charts: form chosen before colour, ≤3 series, fixed palette, direct labels, table fallback

---

## 14. Anti-patterns

Every model — this one included — drifts toward the same handful of tells. If a screen matches an
entry here, it is wrong.

**Generic AI-design tells:**

- Purple-to-blue gradients. Any decorative gradient, really.
- Inter (or the system font) for absolutely everything.
- Cards nested inside cards. Then a card inside that.
- A rounded-square icon tile floating above every section heading.
- Gray text on a coloured background.
- Pure `#000` or `#FFF`, or untinted grays. Neutrals carry a slight hue.
- Bounce and elastic easing.
- Centred body text.
- Emoji as interface iconography.

**Specific to this product:**

- **Tinting every surface with the brand colour.** It is how a white-label app becomes unreadable.
  Brand goes on buttons and accents; surfaces stay neutral (§3.4).
- **Animating a money value.** (§7.3)
- **A pre-checked add-on.** (`RULES.md` §2)
- **Burying expiry or non-refundability** behind a link, a tooltip, or `caption` size. (§6.2)
- **A greyed-out unavailable slot or add-on** — remove it instead. (§6.3)
- **Crayora branding inside the app.** The customer is a customer of the salon. (§2.1)
- **A dashboard of six pie charts.** Stat tiles first; a chart only when the shape carries meaning.
- **Shimmer skeletons** on a device that is already struggling. (§7.4)
- **A confirm dialog on mark-complete.** It is one tap; the undo is re-tapping. (§6.4)
- **A Devanagari-incapable font** on a salon serving Hindi customers. (§5.3)
