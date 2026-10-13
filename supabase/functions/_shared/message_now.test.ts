// node --test supabase/functions/_shared/message_now.test.ts
//
// 0102: no SMS or WhatsApp message had ever been delivered - the request went
// out with no recipient. These pin the request to Message Central's documents.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { BatchRow } from './push_message.ts';
import { messageNowRequest, messageNowResult, whatsappVariable } from './message_now.ts';

const base: BatchRow = {
  delivery_id: 'd-1',
  notification_id: 'n-1',
  channel: 'sms',
  customer_id: 'c-1',
  token: null,
  platform: null,
  body: 'Studio Nine: your appointment is confirmed for Fri 5 pm.',
  purpose: 'booking_confirmed',
  category: 'transactional',
  phone: '9812345678',
  sender_id: 'STNINE',
  wa_template: null,
  wa_lang: null,
  wa_variables: null,
};

const q = (row: BatchRow) => {
  const r = messageNowRequest(row);
  assert.ok(r.ok, r.ok ? '' : r.reason);
  return Object.fromEntries((r as { query: URLSearchParams }).query);
};

test('an SMS goes TO someone: the number, the country, the sender and the text', () => {
  assert.deepEqual(q(base), {
    type: 'SMS',
    flowType: 'SMS',
    countryCode: '91',
    mobileNumber: '9812345678',
    senderId: 'STNINE',
    message: base.body,
    messageType: 'TRANSACTION',
  });
});

test('marketing is PROMOTIONAL; everything else is a TRANSACTION', () => {
  assert.equal(q({ ...base, category: 'marketing' }).messageType, 'PROMOTIONAL');
});

test('no number, no sender, or no text: nothing is sent, and the reason says which', () => {
  for (const [row, reason] of [
    [{ ...base, phone: null }, 'no_phone'],
    [{ ...base, sender_id: null }, 'sms_sender_not_set'],
    [{ ...base, body: null }, 'no_template'],
  ] as const) {
    const r = messageNowRequest(row);
    assert.equal(r.ok, false);
    assert.equal((r as { reason: string }).reason, reason);
  }
});

const wa: BatchRow = {
  ...base,
  channel: 'whatsapp',
  body: null,
  sender_id: '919800000001',
  wa_template: 'booking_confirmed_v1',
  wa_lang: 'en',
  wa_variables: ['Studio Nine', 'Fri, 5 pm'],
};

test('WhatsApp sends the APPROVED template to the number, from the salon’s WhatsApp number', () => {
  assert.deepEqual(q(wa), {
    flowType: 'WHATSAPP',
    type: 'BROADCAST',
    templateName: 'booking_confirmed_v1',
    senderId: '919800000001',
    countryCode: '91',
    mobileNumber: '9812345678',
    langId: 'en',
    // A comma inside a value would shift every placeholder after it.
    variables: 'Studio Nine, Fri 5 pm',
  });
});

test('WhatsApp never sends free text - no approved template, no message', () => {
  const r = messageNowRequest({ ...wa, wa_template: null });
  assert.equal(r.ok, false);
  assert.equal((r as { reason: string }).reason, 'no_whatsapp_template');
});

test('a channel Message Central is not wired for is refused, not guessed at', () => {
  const r = messageNowRequest({ ...base, channel: 'rcs' });
  assert.equal(r.ok, false);
});

test('a variable loses its commas and nothing else', () => {
  assert.equal(whatsappVariable(' Rs 1,20,500 '), 'Rs 1 20 500');
});

test('only HTTP 200 with responseCode 200 is a send', () => {
  assert.deepEqual(messageNowResult(200, { responseCode: 200, data: { transactionId: 't-1' } }), {
    ok: true,
    providerMessageId: 't-1',
  });
  // WhatsApp broadcasts answer with data: null - still a send.
  assert.deepEqual(messageNowResult(200, { responseCode: 200, message: 'SUCCESS', data: null }), {
    ok: true,
    providerMessageId: undefined,
  });
  assert.equal(messageNowResult(200, { responseCode: 805, message: 'insufficient credits' }).ok, false);
  assert.equal(messageNowResult(401, null).ok, false);
});

test('a failure reason never echoes the body - it can carry the number', () => {
  const r = messageNowResult(400, { responseCode: 400, message: 'BAD_REQUEST 9812345678' });
  assert.equal(r.ok, false);
  assert.doesNotMatch((r as { reason: string }).reason, /9812345678/);
});
