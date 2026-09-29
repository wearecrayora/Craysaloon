// The FCM v1 message for one push. Pure - no Deno, no network - so its shape is
// tested directly (push_message.test.ts, run by scripts/functions-test.sh).

/** One claimed delivery, as claim_notification_batch hands it back. */
export type BatchRow = {
  delivery_id: string;
  notification_id: string;
  channel: 'push' | 'rcs' | 'whatsapp' | 'sms';
  customer_id: string;
  token: string | null;
  platform: string | null;
  body: string | null;
  purpose: string;
};

/** What a push from this salon wears: its name, colour and logo (PRD 20). */
export type PushBrand = { name: string | null; color: string | null; logo: string | null };

/** The notification channel the app creates, named for the salon (ARCHITECTURE 7.4). */
export const SALON_CHANNEL_ID = 'cray_salon';

/**
 * - **Title = the salon's name.** The customer knows the salon, not Crayora;
 *   the body already says what happened.
 * - **Colour = the salon's primary**, on the salon's own channel. FCM wants
 *   `#rrggbb` exactly; anything else is dropped rather than failing the send.
 * - **Logo** as the notification image, on Android and iOS alike, and only an
 *   https URL: FCM rejects the WHOLE message over a bad image, and a push that
 *   never sends escalates to a channel the salon pays for.
 */
export function fcmMessage(row: BatchRow, brand: PushBrand | null) {
  const color = brand?.color && /^#[0-9a-f]{6}$/i.test(brand.color) ? brand.color : undefined;
  const logo = brand?.logo && brand.logo.startsWith('https://') ? brand.logo : undefined;

  return {
    token: row.token,
    notification: {
      ...(brand?.name ? { title: brand.name } : {}),
      body: row.body,
      ...(logo ? { image: logo } : {}),
    },
    data: {
      // The ack protocol's whole mechanism: the app calls ack_notification with
      // this id the moment the message lands, in the foreground OR the
      // background isolate.
      delivery_id: row.delivery_id,
      purpose: row.purpose,
    },
    android: {
      priority: 'high',
      notification: { channel_id: SALON_CHANNEL_ID, ...(color ? { color } : {}) },
    },
    ...(logo
      ? { apns: { payload: { aps: { 'mutable-content': 1 } }, fcm_options: { image: logo } } }
      : {}),
  };
}
