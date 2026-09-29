// node --test supabase/functions/_shared/push_message.test.ts
//
// PRD 20: "every push carries the salon's name, logo and colour" - and none of
// that may ever cost the push itself.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { type BatchRow, fcmMessage, SALON_CHANNEL_ID } from './push_message.ts';

const row: BatchRow = {
  delivery_id: 'd-1',
  notification_id: 'n-1',
  channel: 'push',
  customer_id: 'c-1',
  token: 'device-token',
  platform: 'android',
  body: 'Your haircut is tomorrow at 11:00.',
  purpose: 'reminder',
};

const brand = {
  name: 'Studio Nine Salon',
  color: '#B84F5E',
  logo: 'https://assets.example.test/studio-nine/logo.png',
};

test('the salon is the title, in its colour, on its own channel, with its logo', () => {
  const m = fcmMessage(row, brand) as any;
  assert.equal(m.notification.title, 'Studio Nine Salon');
  assert.equal(m.notification.body, row.body);
  assert.equal(m.notification.image, brand.logo);
  assert.equal(m.android.notification.color, '#B84F5E');
  assert.equal(m.android.notification.channel_id, SALON_CHANNEL_ID);
  assert.equal(m.apns.fcm_options.image, brand.logo);
});

test('the ack id always rides along - it is what stops a paid escalation', () => {
  for (const b of [brand, null]) {
    const m = fcmMessage(row, b) as any;
    assert.equal(m.data.delivery_id, 'd-1');
    assert.equal(m.android.priority, 'high');
  }
});

test('no brand read: the message still sends, plainly', () => {
  const m = fcmMessage(row, null) as any;
  assert.equal(m.notification.title, undefined);
  assert.equal(m.notification.body, row.body);
  assert.equal(m.android.notification.color, undefined);
  assert.equal(m.apns, undefined);
});

test('a colour FCM would reject is dropped, not sent', () => {
  for (const color of ['B84F5E', '#B84F5', 'rose', '#B84F5E80']) {
    const m = fcmMessage(row, { ...brand, color }) as any;
    assert.equal(m.android.notification.color, undefined, color);
    assert.equal(m.notification.title, 'Studio Nine Salon');
  }
});

test('a placeholder or non-https logo never reaches FCM', () => {
  for (const logo of ['pending-upload', 'http://x.test/logo.png', '', null]) {
    const m = fcmMessage(row, { ...brand, logo }) as any;
    assert.equal(m.notification.image, undefined, String(logo));
    assert.equal(m.apns, undefined);
  }
});
