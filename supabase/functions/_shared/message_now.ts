// The paid rungs, as Message Central documents them (0102). Pure: no network,
// no secrets - what goes on the wire, so it can be tested without either.
//
//   SMS (MessageNow SMS API)
//     POST /verification/v3/send?type=SMS&flowType=SMS&countryCode=91
//          &mobileNumber=…&senderId=…&message=…&messageType=TRANSACTION|PROMOTIONAL
//   WhatsApp (WhatsApp Now API V1, "Send Single Broadcast")
//     POST /verification/v3/send?flowType=WHATSAPP&type=BROADCAST&templateName=…
//          &senderId=<WABA number>&countryCode=91&mobileNumber=…&langId=…&variables=a, b
//   Both: header `authToken` - the salon's own Message Central token.
//
// Until 0102 the dispatcher posted a JSON body to this endpoint with no
// recipient at all, so no SMS or WhatsApp message was ever delivered. The
// tests beside this file fail if a request ever goes out without one again.
//
// No DLT fields (templateId, entityId): Message Central's SMS needs none.

import type { BatchRow } from './push_message.ts';

export type MessageNowRequest =
  | { ok: true; query: URLSearchParams }
  | { ok: false; reason: string };

/**
 * WhatsApp Now separates variables with commas, so a value carrying one would
 * shift every placeholder after it. Commas become spaces.
 */
export function whatsappVariable(value: string): string {
  return value.replace(/,/g, ' ').replace(/\s+/g, ' ').trim();
}

export function messageNowRequest(row: BatchRow): MessageNowRequest {
  if (row.channel !== 'sms' && row.channel !== 'whatsapp') {
    return { ok: false, reason: `${row.channel}_not_supported` };
  }
  if (!row.phone) return { ok: false, reason: 'no_phone' };
  if (!row.sender_id) {
    return { ok: false, reason: row.channel === 'sms' ? 'sms_sender_not_set' : 'whatsapp_number_not_set' };
  }

  if (row.channel === 'sms') {
    if (!row.body) return { ok: false, reason: 'no_template' };
    return {
      ok: true,
      query: new URLSearchParams({
        type: 'SMS',
        flowType: 'SMS',
        countryCode: '91',
        mobileNumber: row.phone,
        senderId: row.sender_id,
        message: row.body,
        // Marketing is PROMOTIONAL by Message Central's own rules; everything
        // else this product sends is a transaction the customer is party to.
        messageType: row.category === 'marketing' ? 'PROMOTIONAL' : 'TRANSACTION',
      }),
    };
  }

  // WhatsApp only ever sends a Meta-approved template - never free text, which
  // WhatsApp refuses outside a customer's 24-hour window anyway.
  if (!row.wa_template || !row.wa_lang) return { ok: false, reason: 'no_whatsapp_template' };
  const query = new URLSearchParams({
    flowType: 'WHATSAPP',
    type: 'BROADCAST',
    templateName: row.wa_template,
    senderId: row.sender_id,
    countryCode: '91',
    mobileNumber: row.phone,
    langId: row.wa_lang,
  });
  if (row.wa_variables && row.wa_variables.length > 0) {
    query.set('variables', row.wa_variables.map(whatsappVariable).join(', '));
  }
  return { ok: true, query };
}

export type MessageNowResult =
  | { ok: true; providerMessageId?: string }
  | { ok: false; reason: string };

/**
 * A send is HTTP 200 carrying responseCode 200. Anything else is a failure, and
 * its reason is the provider's status words only - the body is not echoed,
 * because it can carry the recipient's number.
 */
export function messageNowResult(status: number, body: unknown): MessageNowResult {
  const b = (body ?? {}) as { responseCode?: unknown; message?: unknown; data?: { transactionId?: unknown } | null };
  if (status === 200 && Number(b.responseCode) === 200) {
    const id = b.data?.transactionId;
    return { ok: true, providerMessageId: typeof id === 'string' && id ? id : undefined };
  }
  const words = typeof b.message === 'string' ? b.message.replace(/[^A-Za-z_ ]/g, '').slice(0, 60) : '';
  return { ok: false, reason: `provider_${status}_mc_${b.responseCode ?? 'none'}${words ? `_${words}` : ''}` };
}
