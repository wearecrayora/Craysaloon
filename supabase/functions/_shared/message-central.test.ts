// node --test supabase/functions/_shared/message-central.test.ts
//
// PRD 20 / CLAUDE.md rule 16: "no code attempts to template, brand or validate
// the OTP message - it is Message Central's and fixed". The OTP request carries
// exactly VerifyNow's fields and nothing that could word, sign or brand it.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { otpSendQuery } from './message-central.ts';

test('the OTP request is exactly VerifyNow’s fields - no message, template, sender or brand', () => {
  const q = otpSendQuery('C-SALON1', '9812345678');
  assert.deepEqual([...q.keys()].sort(), [
    'countryCode',
    'customerId',
    'flowType',
    'mobileNumber',
    'otpLength',
  ]);
  for (const forbidden of ['message', 'templateId', 'entityId', 'senderId', 'type', 'messageType']) {
    assert.equal(q.has(forbidden), false, `${forbidden} must never ride an OTP send`);
  }
});

test('six digits, not VerifyNow’s default four', () => {
  assert.equal(otpSendQuery('C-SALON1', '9812345678').get('otpLength'), '6');
});
