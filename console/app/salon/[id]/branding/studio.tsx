'use client';

import { useActionState, useMemo, useState } from 'react';
import {
  formatGate,
  resolveTokens,
  validateBranding,
  type BrandInput,
  type Mode,
} from '@cray/design-tokens';
import { publishBrandingAction, type PublishState } from '@/app/actions';

const empty: PublishState = {};

/**
 * The operator picks four colours. Everything else - onPrimary, brandInk, the
 * container steps, the ink ramp - is derived at publish, because an operator
 * choosing twelve colours is an operator choosing twelve accessibility
 * failures.
 *
 * The preview and the gate both come from @cray/design-tokens, the same module
 * the app resolves its theme from. That is the whole reason the package is
 * shared: a preview computed by different code from the one that renders the
 * customer's app is a preview that can lie.
 */

function defaults(displayName: string): BrandInput {
  return {
    version: 1,
    displayName,
    // These clear the gate. #c2571f, an obvious-looking choice for this accent,
    // measures 4.49:1 against white - one hundredth under the 4.5 threshold,
    // and blocked. Starting an operator on a palette they cannot publish would
    // teach them to distrust the gate.
    brand: {
      light: { primary: '#1f6f5c', accent: '#b04d1a' },
      dark: { primary: '#7fd3bc', accent: '#f0a06a' },
    },
    typography: {
      heading: { family: 'Inter', weight: 600 },
      body: { family: 'Inter', weight: 400 },
      script: 'latin',
    },
    shape: { radius: 12 },
    assets: { logo: 'pending-upload' },
  };
}

export function Studio({
  salonId,
  displayName,
  initial,
}: {
  salonId: string;
  displayName: string;
  initial: unknown;
}) {
  const [input, setInput] = useState<BrandInput>(() => {
    // A previously published version is the starting point; anything
    // unparseable falls back rather than crashing the page.
    if (initial && typeof initial === 'object' && 'brand' in (initial as object)) {
      return initial as BrandInput;
    }
    return defaults(displayName);
  });
  const [state, publish, publishing] = useActionState(publishBrandingAction, empty);

  // Live, on every keystroke. This is advice to the operator; the server runs
  // the same check again before anything is written.
  const gate = useMemo(() => validateBranding(input), [input]);

  function setBrand(mode: Mode, key: 'primary' | 'accent', value: string) {
    setInput((v) => ({ ...v, brand: { ...v.brand, [mode]: { ...v.brand[mode], [key]: value } } }));
  }

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) 340px', gap: 24 }}>
      <div>
        <div className="card">
          <h2>Palette</h2>
          <p className="hint" style={{ marginTop: 0 }}>
            Four colours. Light and dark are separate because a colour that is legible on white is
            usually not legible on near-black.
          </p>
          {(['light', 'dark'] as Mode[]).map((mode) => (
            <div key={mode} style={{ marginBottom: 8 }}>
              <strong style={{ fontSize: 13, textTransform: 'capitalize' }}>{mode}</strong>
              <div className="row">
                {(['primary', 'accent'] as const).map((key) => (
                  <div key={key}>
                    <label htmlFor={`${mode}-${key}`}>{key}</label>
                    <div style={{ display: 'flex', gap: 8 }}>
                      <input
                        type="color"
                        aria-label={`${mode} ${key} colour picker`}
                        value={input.brand[mode][key]}
                        onChange={(e) => setBrand(mode, key, e.target.value)}
                        style={{ width: 46, padding: 2 }}
                      />
                      <input
                        id={`${mode}-${key}`}
                        value={input.brand[mode][key]}
                        onChange={(e) => setBrand(mode, key, e.target.value)}
                        spellCheck={false}
                        style={{ fontFamily: 'ui-monospace, monospace' }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        <div className="card">
          <h2>Type and shape</h2>
          <div className="row">
            <div>
              <label htmlFor="heading">Heading font</label>
              <input
                id="heading"
                value={input.typography.heading.family}
                onChange={(e) =>
                  setInput((v) => ({
                    ...v,
                    typography: {
                      ...v.typography,
                      heading: { ...v.typography.heading, family: e.target.value },
                    },
                  }))
                }
              />
            </div>
            <div>
              <label htmlFor="body">Body font</label>
              <input
                id="body"
                value={input.typography.body.family}
                onChange={(e) =>
                  setInput((v) => ({
                    ...v,
                    typography: {
                      ...v.typography,
                      body: { ...v.typography.body, family: e.target.value },
                    },
                  }))
                }
              />
            </div>
          </div>
          <div className="row">
            <div>
              <label htmlFor="script">Script</label>
              <select
                id="script"
                value={input.typography.script}
                onChange={(e) =>
                  setInput((v) => ({
                    ...v,
                    typography: {
                      ...v.typography,
                      script: e.target.value as BrandInput['typography']['script'],
                    },
                  }))
                }
              >
                <option value="latin">Latin</option>
                <option value="devanagari">Devanagari</option>
              </select>
              <p className="hint">
                A salon serving Hindi customers must use a Devanagari-capable font. Devanagari also
                gets extra line height and no letter-spacing.
              </p>
            </div>
            <div>
              <label htmlFor="radius">Corner radius (dp)</label>
              <input
                id="radius"
                type="number"
                min={0}
                max={28}
                value={input.shape.radius}
                onChange={(e) =>
                  setInput((v) => ({ ...v, shape: { radius: Number(e.target.value) } }))
                }
              />
            </div>
          </div>
        </div>

        <form
          action={publish}
          className="card"
          style={{ borderColor: gate.ok ? undefined : 'var(--danger)' }}
        >
          <input type="hidden" name="salonId" value={salonId} />
          <input type="hidden" name="branding" value={JSON.stringify(input)} />

          <h2>Publish</h2>
          {state.error && <div className="error">{state.error}</div>}
          {state.ok && (
            <div className="notice">
              {state.ok} Now at version {state.version}.
            </div>
          )}

          <pre
            style={{
              whiteSpace: 'pre-wrap',
              fontSize: 12.5,
              background: 'var(--bg-soft)',
              padding: 12,
              borderRadius: 6,
              margin: 0,
            }}
          >
            {formatGate(gate)}
          </pre>

          <div className="actions">
            <button disabled={publishing || !gate.ok}>
              {publishing ? 'Publishing…' : 'Publish branding'}
            </button>
            {!gate.ok && (
              <span style={{ fontSize: 13, color: 'var(--ink-soft)' }}>
                Publish is blocked until every failure above clears. There is no override.
              </span>
            )}
          </div>
        </form>
      </div>

      <div>
        <Preview input={input} mode="light" />
        <Preview input={input} mode="dark" />
      </div>
    </div>
  );
}

/**
 * A miniature of the surfaces the customer actually sees. Not a swatch grid:
 * swatches make every palette look fine, and the failure mode being guarded
 * against is text that disappears against its own background.
 */
function Preview({ input, mode }: { input: BrandInput; mode: Mode }) {
  let t;
  try {
    t = resolveTokens(input, mode);
  } catch {
    return (
      <div className="card">
        <h2 style={{ textTransform: 'capitalize' }}>{mode}</h2>
        <p className="hint">Not previewable until the colours are valid hex.</p>
      </div>
    );
  }
  const c = t.color;

  return (
    <div className="card" style={{ padding: 12 }}>
      <h2 style={{ textTransform: 'capitalize', margin: '4px 0 8px' }}>{mode}</h2>
      <div
        style={{
          background: c.surface,
          borderRadius: t.radius.sheet,
          padding: 14,
          border: `1px solid ${c.border}`,
          fontFamily: `${input.typography.body.family}, system-ui, sans-serif`,
        }}
      >
        <div style={{ color: c.brandInk, fontWeight: 700, fontSize: 15 }}>{input.displayName}</div>
        <div style={{ color: c.textSecondary, fontSize: 12, marginBottom: 10 }}>
          Wallet balance
        </div>
        {/* Money: tabular figures, Indian grouping, never animated. */}
        <div
          style={{
            color: c.textPrimary,
            fontSize: 26,
            fontWeight: 700,
            fontVariantNumeric: 'tabular-nums',
          }}
        >
          ₹1,20,500
        </div>

        <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
          <span
            style={{
              background: c.primary,
              color: c.onPrimary,
              padding: '8px 14px',
              borderRadius: t.radius.base,
              fontSize: 13,
              fontWeight: 600,
            }}
          >
            Book again
          </span>
          <span
            style={{
              background: c.primaryContainer,
              color: c.onPrimaryContainer,
              padding: '8px 14px',
              borderRadius: t.radius.base,
              fontSize: 13,
              fontWeight: 600,
            }}
          >
            Top up
          </span>
        </div>

        <div
          style={{
            marginTop: 12,
            paddingTop: 10,
            borderTop: `1px solid ${c.divider}`,
            color: c.textMuted,
            fontSize: 12,
          }}
        >
          Last visit 12 Aug · Haircut
        </div>

        {/* Status colours are never themed - the same fixed set in every salon. */}
        <div style={{ display: 'flex', gap: 6, marginTop: 10, fontSize: 11, fontWeight: 600 }}>
          <span style={{ color: c.success }}>Completed</span>
          <span style={{ color: c.warning }}>Pending</span>
          <span style={{ color: c.danger }}>Cancelled</span>
        </div>
      </div>
    </div>
  );
}
