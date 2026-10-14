"""The beauty still life as SVG, for the console and the join site.

    python scripts/design/still-life-svg.py <out-dir>

Same objects and the same rules as the app's painter
(app/lib/core/ui/beauty_still_life.dart, DESIGN.md 3.5a): frosted glass -
a faint graded fill, a hairline edge, a catch-light - neutral, faint, still,
at the edges of a wide viewport. Writes still-life-light.svg and
still-life-dark.svg; each is a fixed full-viewport background (slice).
"""
import os
import sys

out_dir = sys.argv[1]

# Unit-space shapes: x about -0.3..0.3, y 0 (top) .. 1 (bottom).
def rrect(l, t, r, b, rad):
    return f'<rect x="{l}" y="{t}" width="{r - l:.3f}" height="{b - t:.3f}" rx="{rad}"/>'

def circle(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}"/>'

def path(d):
    return f'<path d="{d}"/>'

OBJECTS = {
    'lipstick': {
        'shapes': [rrect(-0.16, 0.48, 0.16, 1.0, 0.04), rrect(-0.13, 0.36, 0.13, 0.48, 0.02),
                   path('M-0.10 0.36 L-0.10 0.10 Q-0.06 0.02 0.10 0 L0.10 0.36 Z')],
        'lines': [], 'shine': (-0.11, 0.55, -0.11, 0.95),
    },
    'compact': {
        'shapes': [circle(0, 0.30, 0.30), circle(0, 0.30, 0.24), rrect(-0.05, 0.58, 0.05, 0.64, 0.02),
                   circle(0, 0.92, 0.30), circle(0, 0.92, 0.20)],
        'lines': [], 'shine': (-0.16, 0.16, -0.04, 0.08),
    },
    'brush': {
        'shapes': [path('M-0.03 0.30 Q-0.20 0.14 -0.11 0 Q0 -0.05 0.11 0 Q0.20 0.14 0.03 0.30 Z'),
                   rrect(-0.045, 0.30, 0.045, 0.42, 0.015),
                   path('M-0.04 0.42 L0.04 0.42 L0.018 1.0 Q0 1.02 -0.018 1.0 Z')],
        'lines': ['M-0.024 0.28 L-0.06 0.04', 'M0 0.28 L0 0.04', 'M0.024 0.28 L0.06 0.04'],
        'shine': (-0.02, 0.48, -0.008, 0.9),
    },
    'polish': {
        'shapes': [rrect(-0.07, 0, 0.07, 0.42, 0.03), rrect(-0.10, 0.40, 0.10, 0.48, 0.02),
                   rrect(-0.22, 0.48, 0.22, 1.0, 0.10)],
        'lines': [], 'shine': (-0.15, 0.58, -0.15, 0.90),
    },
    'perfume': {
        'shapes': [circle(0, 0.10, 0.10), rrect(-0.05, 0.19, 0.05, 0.30, 0.01),
                   path('M-0.20 0.30 L0.20 0.30 L0.28 0.48 L0.28 0.92 Q0.28 1 0.20 1 L-0.20 1 '
                        'Q-0.28 1 -0.28 0.92 L-0.28 0.48 Z')],
        'lines': ['M-0.28 0.48 L0.28 0.48'], 'shine': (-0.20, 0.54, -0.20, 0.92),
    },
    'comb': {
        'shapes': [rrect(-0.10, 0, 0.10, 1.0, 0.05)],
        'lines': [f'M0.10 {0.06 + i * 0.056:.3f} L{0.26 if i < 8 else 0.30} {0.06 + i * 0.056:.3f}'
                  for i in range(16)],
        'shine': (-0.05, 0.08, -0.05, 0.9),
    },
    'scissors': {
        'shapes': [circle(-0.13, 0.82, 0.12), circle(0.13, 0.82, 0.12),
                   path('M-0.07 0.72 L0.06 0 L0.10 0.04 L0 0.70 Z'),
                   path('M0.07 0.72 L-0.06 0 L-0.10 0.04 L0 0.70 Z'), circle(0, 0.58, 0.02)],
        'lines': [], 'shine': None,
    },
    'mascara': {
        'shapes': [rrect(-0.06, 0, 0.06, 0.44, 0.03), rrect(-0.07, 0.44, 0.07, 1.0, 0.035)],
        'lines': ['M-0.07 0.44 L0.07 0.44'], 'shine': (-0.035, 0.52, -0.035, 0.94),
    },
}

# Placement on a 1440 x 900 viewport (sliced to fill any screen): edges only.
W, H = 1440, 900
PLACES = [
    ('perfume', 1330, 40, 330, 14),
    ('compact', 40, 260, 300, -8),
    ('brush', 1420, 380, 560, 24),
    ('lipstick', 150, 640, 300, -22),
    ('polish', 1210, 690, 230, 10),
    ('comb', 420, -10, 270, 72),
    ('scissors', 760, 760, 240, -28),
    ('mascara', 1010, -20, 260, 78),
]

def svg(dark):
    ink = '#ffffff' if dark else '#1d2430'
    fill_hi, fill_lo = (0.065, 0.025) if dark else (0.05, 0.02)
    edge = 0.12 if dark else 0.09
    shine = 0.18 if dark else 0.6
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
        f'preserveAspectRatio="xMidYMid slice" aria-hidden="true">',
        '<defs>',
        f'<linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{ink}" stop-opacity="{fill_hi}"/>'
        f'<stop offset="1" stop-color="{ink}" stop-opacity="{fill_lo}"/></linearGradient>',
        f'<linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="#fff" stop-opacity="0"/>'
        f'<stop offset=".5" stop-color="#fff" stop-opacity="{shine}"/>'
        f'<stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>',
        '</defs>',
    ]
    for name, x, y, height, turn in PLACES:
        o = OBJECTS[name]
        parts.append(f'<g transform="translate({x} {y}) rotate({turn}) scale({height})">')
        parts.append(f'<g fill="url(#glass)" stroke="{ink}" stroke-opacity="{edge}" '
                     f'stroke-width="1.2" vector-effect="non-scaling-stroke">'
                     + ''.join(o['shapes']).replace('/>', ' vector-effect="non-scaling-stroke"/>')
                     + '</g>')
        if o['lines']:
            parts.append(f'<g fill="none" stroke="{ink}" stroke-opacity="{edge}" stroke-width="1.2" '
                         f'stroke-linecap="round">'
                         + ''.join(f'<path d="{d}" vector-effect="non-scaling-stroke"/>' for d in o['lines'])
                         + '</g>')
        if o['shine']:
            x1, y1, x2, y2 = o['shine']
            parts.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="url(#shine)" '
                         f'stroke-width="3" stroke-linecap="round" vector-effect="non-scaling-stroke"/>')
        parts.append('</g>')
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'

os.makedirs(out_dir, exist_ok=True)
for dark in (False, True):
    name = f'still-life-{"dark" if dark else "light"}.svg'
    with open(os.path.join(out_dir, name), 'w', encoding='utf-8', newline='\n') as f:
        f.write(svg(dark))
    print('wrote', name)
