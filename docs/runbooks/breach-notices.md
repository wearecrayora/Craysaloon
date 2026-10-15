# Breach notices: drafts to fill in

**Written for: whoever is running a breach (`RUNBOOK-BREACH.md`).** Written on 15 Oct 2026 because
the first rehearsal found none existed: at hour 4 of an incident is not when to draft from nothing.
Fill the `<angle brackets>`; delete nothing else without a reason. Never put customer data in any of
these.

---

## 1. CERT-In - inside 6 hours (`incident@cert-in.org.in`)

Use CERT-In's current incident reporting form if it has changed; these are the facts it asks for.
Send at the 5-hour mark with "under investigation" where you do not know yet.

```
Subject: Incident report - personal data breach - Crayora (Cray Salon)

Reporting organisation : Crayora, India - Cray Salon (software provider to salons)
Contact                : <name>, <phone>, crayoratech@gmail.com
Time of occurrence     : <date, time IST, or "under investigation">
Time of detection      : <date, time IST> - how: <report from a researcher / alert / ...>
Type of incident       : <data breach / unauthorised access / compromise of credentials / ...>
Systems affected       : <Supabase Postgres (ap-south-1, Mumbai) / Edge Functions /
                          Crayora console (Cloudflare Workers) / R2 object storage>
Data involved          : <which fields: names, mobile numbers, visit history, ...>
People affected        : <approximate number, or "under investigation">
Salons affected        : <number> (each is the Data Fiduciary for its customers)
What has been done     : <containment steps, with times>
What is planned        : <next steps>
Logs                   : retained 180 days in India (ops.ict_logs, Mumbai); preserved, nothing deleted
```

Keep the sent copy. It is the evidence the 6-hour clock was met.

---

## 2. Data Protection Board - intimation without delay, full report in 72 hours

Through the Board's prescribed channel (record it in the runbook's contacts before it is needed).

**Intimation (now):**

```
Data Fiduciary   : <salon's legal name> (Crayora, Cray Salon, is its Data Processor and files
                   with it / for it)
What happened    : <one paragraph: nature of the breach>
Extent           : <how many people, which data>
When             : occurred <time or unknown>; detected <time>
Where            : <systems, region>
Likely impact    : <what it could mean for the people affected>
```

**Full report (within 72 hours of becoming aware)** - the above, updated, plus:

- the broader facts and circumstances, and the timeline;
- the mitigation already taken, and what remains;
- what is known about who or what caused it;
- the remedial measures, including the gate or control that now exists so it fails loudly next time;
- a copy of the notice sent to the affected people (section 4).

---

## 3. To the salon (Crayora writes first - the salon is the Data Fiduciary)

```
Subject: Important: a data incident affecting <salon name>

<Owner's name>,

At <time> on <date> we learned that <one sentence a person can repeat>.

What we know: <data involved, how many of your customers, the period>.
What we do not know yet: <the open questions>.
What we have done: <containment, with times>.

Because <salon name> is responsible for its customers' data under the DPDP Act, the notices to
CERT-In, the Data Protection Board and your affected customers are made with you. We have drafted
them; we will call you at <time> to go through them, and you will hear from us again by <time>.

<name>, Crayora - <phone> - crayoratech@gmail.com
```

---

## 4. To each affected customer (from the salon, in their language)

No customer data in the message itself. Not "we take your privacy seriously". If they need to do
nothing, say so plainly.

**English**

```
<Salon name>: On <date> we found that <what happened, in one sentence>. Your <name / mobile
number / visit history - only what is THEIRS> may have been seen by <who, as far as known>.
This could mean <what it could mean for them>. We have <what was done>. You <do not need to do
anything / should ...>. Questions: <salon privacy contact name>, <phone or email>. You can also
complain to the Data Protection Board of India.
```

**हिन्दी**

```
<सैलून का नाम>: <तारीख़> को हमें पता चला कि <क्या हुआ, एक वाक्य में>। आपका <नाम / मोबाइल नंबर /
विज़िट का इतिहास - सिर्फ़ जो उनका है> <किसके द्वारा, जितना पता है> देखा गया हो सकता है। इसका मतलब हो
सकता है <उनके लिए इसका क्या मतलब है>। हमने <क्या किया गया>। आपको <कुछ करने की ज़रूरत नहीं है /
... करना चाहिए>। सवाल: <सैलून का गोपनीयता संपर्क>, <फ़ोन या ईमेल>। आप भारत के डेटा संरक्षण बोर्ड में
भी शिकायत कर सकते हैं।
```

**How it reaches them.** By app notification where they have the app; SMS and WhatsApp are off
(0108). The salon owner sees each customer's number in the app (Customers) and can call or message
the rest. Crayora does not send it from its own name.
