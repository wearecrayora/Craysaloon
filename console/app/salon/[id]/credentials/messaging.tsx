'use client';

import { useActionState } from 'react';
import {
  messagingIdentityAction,
  whatsappTemplateAction,
  type ActionState,
} from '@/app/actions';
import type { IntegrationRow, MessageKey, WhatsappTemplateRow } from '@/server/admin-db';

const empty: ActionState = {};

/**
 * The paid rungs of the ladder (0102). Push is free and always tried first;
 * these decide what happens when a push is not acknowledged. Both send from the
 * salon's OWN Message Central account - the credential above - and cost the
 * salon. Nothing here is a secret, but only Crayora sets it (RULES 8.12).
 */
export function MessagingForm({
  salonId,
  messageCentral,
  whatsapp,
  keys,
  templates,
}: {
  salonId: string;
  messageCentral: IntegrationRow | undefined;
  whatsapp: IntegrationRow | undefined;
  keys: MessageKey[];
  templates: WhatsappTemplateRow[];
}) {
  const [state, save, saving] = useActionState(messagingIdentityAction, empty);
  const [tState, saveTemplate, savingTemplate] = useActionState(whatsappTemplateAction, empty);
  const mcReady = messageCentral?.has_secret && messageCentral.status !== 'failing';

  return (
    <>
      <form action={save} className="card">
        <input type="hidden" name="salonId" value={salonId} />
        <h2 style={{ marginTop: 0 }}>SMS and WhatsApp</h2>
        <p className="hint" style={{ marginTop: 0 }}>
          When a push is not acknowledged, the message falls back to WhatsApp (cheaper) and then
          SMS - from the salon&rsquo;s own Message Central account, at the salon&rsquo;s cost. A
          channel with nothing set here is simply skipped. No DLT registration is needed.
        </p>
        {!mcReady && (
          <div className="notice">
            Save a working Message Central credential above first. Without it neither SMS nor
            WhatsApp can send, whatever is set here.
          </div>
        )}
        {state.error && <div className="error">{state.error}</div>}
        {state.ok && <div className="notice">{state.ok}</div>}
        <div className="row">
          <div>
            <label htmlFor="smsSenderId">SMS sender ID</label>
            <input
              id="smsSenderId"
              name="smsSenderId"
              defaultValue={messageCentral?.sender_id ?? ''}
              placeholder="As issued by Message Central - blank for no SMS"
              autoComplete="off"
              spellCheck={false}
            />
          </div>
          <div>
            <label htmlFor="whatsappNumber">WhatsApp Business number</label>
            <input
              id="whatsappNumber"
              name="whatsappNumber"
              defaultValue={whatsapp?.sender_id ?? ''}
              placeholder="With country code, e.g. 919812345678"
              inputMode="numeric"
              autoComplete="off"
            />
          </div>
        </div>
        <label htmlFor="whatsappStatus">WhatsApp templates (Meta approval)</label>
        <select
          id="whatsappStatus"
          name="whatsappStatus"
          defaultValue={whatsapp?.whatsapp_template_status ?? 'not_started'}
        >
          <option value="not_started">Not started - WhatsApp is skipped</option>
          <option value="pending">Submitted, pending - WhatsApp is skipped</option>
          <option value="approved">Approved - WhatsApp is used</option>
          <option value="rejected">Rejected - WhatsApp is skipped</option>
        </select>
        <div className="actions">
          <button disabled={saving}>{saving ? 'Saving…' : 'Save messaging'}</button>
        </div>
      </form>

      <form action={saveTemplate} className="card">
        <input type="hidden" name="salonId" value={salonId} />
        <h2 style={{ marginTop: 0 }}>WhatsApp templates</h2>
        <p className="hint" style={{ marginTop: 0 }}>
          WhatsApp only ever sends a template Meta has approved. Create each one in the
          salon&rsquo;s Message Central dashboard, then map it here: the name{' '}
          <strong>exactly as Message Central returned it</strong> (lower case, with _), its
          language, and which value fills {'{{1}}'}, {'{{2}}'}… in order. A message with no
          template in the customer&rsquo;s language uses the English one; with neither, it goes
          by SMS. Leave the name blank to clear a mapping.
        </p>
        {tState.error && <div className="error">{tState.error}</div>}
        {tState.ok && <div className="notice">{tState.ok}</div>}
        <div className="row">
          <div>
            <label htmlFor="templateKey">Message</label>
            <select id="templateKey" name="templateKey" required>
              {keys.map((k) => (
                <option key={k.template_key} value={k.template_key}>
                  {k.template_key} - values: {['salon', ...k.placeholders.filter((p) => p !== 'salon')].join(', ')}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="locale">Customer language</label>
            <select id="locale" name="locale" defaultValue="en">
              <option value="en">English</option>
              <option value="hi">Hindi</option>
              <option value="hi_Latn">Hinglish</option>
            </select>
          </div>
        </div>
        <div className="row">
          <div>
            <label htmlFor="templateName">Template name</label>
            <input id="templateName" name="templateName" placeholder="booking_confirmed_v1" spellCheck={false} />
          </div>
          <div>
            <label htmlFor="lang">Template language code</label>
            <input id="lang" name="lang" placeholder="en, en_US or hi" spellCheck={false} />
          </div>
        </div>
        <label htmlFor="variables">Values, in placeholder order</label>
        <input id="variables" name="variables" placeholder="salon, when" spellCheck={false} />
        <div className="actions">
          <button disabled={savingTemplate}>{savingTemplate ? 'Saving…' : 'Save template'}</button>
        </div>

        {templates.length > 0 && (
          <table style={{ marginTop: 16, width: '100%' }}>
            <thead>
              <tr>
                <th align="left">Message</th>
                <th align="left">Language</th>
                <th align="left">Template</th>
                <th align="left">Values</th>
              </tr>
            </thead>
            <tbody>
              {templates.map((t) => (
                <tr key={`${t.template_key}:${t.locale}`}>
                  <td>{t.template_key}</td>
                  <td>{t.locale}</td>
                  <td style={{ fontFamily: 'ui-monospace, monospace' }}>
                    {t.template_name} ({t.lang})
                  </td>
                  <td>{t.variables.join(', ') || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </form>
    </>
  );
}
