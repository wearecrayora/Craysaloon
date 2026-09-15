import 'server-only';
import QRCode from 'qrcode';
import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'pdf-lib';

/**
 * The printable QR pack (PRD 6.2, 6.3): a counter card, a mirror sticker and a
 * reception poster, in one PDF.
 *
 * Decisions that are not obvious from the output:
 *
 *  - The QR is drawn as VECTOR squares from the module matrix, not embedded as
 *    a bitmap. A reception poster is printed at A4 and a bitmap QR goes soft at
 *    that size; a vector one stays crisp at any print size, including the
 *    shop's own reprint on a larger sheet.
 *
 *  - Black on white, always, regardless of the salon's brand colour. A tinted
 *    or low-contrast QR scans worse, and the failure mode is a customer
 *    standing at the counter waving their phone at a sticker that does not
 *    work. The salon's identity is in its name, printed above.
 *
 *  - Error correction level Q (~25% recoverable). A mirror sticker gets
 *    splashed, scratched and wiped with a cloth; M would be enough on day one
 *    and not in month six.
 *
 *  - The CODE is printed large beneath every QR. PRD 6.3: a customer with a
 *    cracked camera must still be able to type it. The alphabet already
 *    excludes 0/O and 1/I/L, so nothing on this page asks anyone to guess.
 */

const MM = 72 / 25.4; // points per millimetre

const INK = rgb(0, 0, 0);
const SOFT = rgb(0.35, 0.35, 0.35);

export function joinUrl(code: string) {
  return `https://join.craysalon.in/s/${code}`;
}

/**
 * The standard PDF fonts only cover WinAnsi (Latin-1-ish). A salon name in
 * Devanagari would either throw deep inside pdf-lib or - worse - come out
 * mangled on paper a salon has already paid to print. Refuse up front with a
 * sentence the operator can act on.
 */
function assertPrintable(font: PDFFont, text: string, what: string) {
  try {
    font.encodeText(text);
  } catch {
    throw new Error(
      `${what} contains characters the current print fonts cannot render ` +
        '(for example Devanagari). The QR pack does not yet embed a Devanagari ' +
        'font; use a Latin-script display name for the printed pack for now.',
    );
  }
}

function drawQr(page: PDFPage, code: string, x: number, y: number, size: number) {
  const qr = QRCode.create(joinUrl(code), { errorCorrectionLevel: 'Q' });
  const n = qr.modules.size;
  const cell = size / n;

  // ONE path, filled ONCE. The first version drew each dark module as its own
  // rectangle, and every renderer anti-aliases the shared edge between two
  // separately-filled shapes into a faint white seam - the QR came out as a
  // visible grid. It still decoded on screen, but a budget printer can turn
  // those seams into real gaps, and a salon does not reprint a sticker because
  // it looks faintly wrong. A single filled path has no internal edges to seam.
  //
  // Dark modules are merged into horizontal runs first, which keeps the path
  // small: one rectangle per run instead of one per module.
  let d = '';
  for (let row = 0; row < n; row++) {
    let col = 0;
    while (col < n) {
      if (!qr.modules.get(row, col)) {
        col++;
        continue;
      }
      const start = col;
      while (col < n && qr.modules.get(row, col)) col++;
      const x0 = start * cell;
      const x1 = col * cell;
      const y0 = row * cell;
      const y1 = (row + 1) * cell;
      d += `M${x0} ${y0}H${x1}V${y1}H${x0}Z`;
    }
  }

  // drawSvgPath uses SVG coordinates - y increases downward from the origin -
  // so the origin is the QR's TOP-left corner.
  page.drawSvgPath(d, { x, y: y + size, color: INK, borderWidth: 0 });
}

function centred(
  page: PDFPage,
  text: string,
  font: PDFFont,
  size: number,
  y: number,
  color = INK,
  letterSpacing = 0,
) {
  const width = page.getWidth();
  if (letterSpacing === 0) {
    const w = font.widthOfTextAtSize(text, size);
    page.drawText(text, { x: (width - w) / 2, y, size, font, color });
    return;
  }
  // Spaced-out code: drawn glyph by glyph so the spacing is exact.
  const glyphs = [...text];
  const w =
    glyphs.reduce((sum, g) => sum + font.widthOfTextAtSize(g, size), 0) +
    letterSpacing * (glyphs.length - 1);
  let x = (width - w) / 2;
  for (const g of glyphs) {
    page.drawText(g, { x, y, size, font, color });
    x += font.widthOfTextAtSize(g, size) + letterSpacing;
  }
}

type Fonts = { bold: PDFFont; regular: PDFFont; mono: PDFFont };

function layout(
  page: PDFPage,
  f: Fonts,
  displayName: string,
  code: string,
  scale: number,
  compact = false,
) {
  const W = page.getWidth();
  const H = page.getHeight();
  const qrSize = Math.min(W, H) * (compact ? 0.62 : 0.6);
  const qrX = (W - qrSize) / 2;

  let y = H - 20 * MM * scale;

  if (!compact) {
    centred(page, displayName, f.bold, 20 * scale, y);
    y -= 11 * MM * scale;
    centred(page, 'Scan to join', f.bold, 15 * scale, y);
    y -= 6 * MM * scale;
    centred(page, 'Scan karke join karein', f.regular, 11 * scale, y, SOFT);
    y -= 8 * MM * scale;
  } else {
    // The sticker has no heading, so centre the QR-plus-code block vertically
    // instead of pinning it to the top. Pinned, it left a band of empty paper
    // at the bottom that reads as a printing error on a physical sticker.
    //
    // The block runs from the top of the QR down to the code's BASELINE: text
    // is drawn upward from its baseline, so the code adds nothing below that
    // line. Counting its font size as extra height (the first attempt) biased
    // the block ~3 mm upward - measured, not guessed, off a 150 dpi render.
    const codeGap = 9 * MM;
    y = (H + qrSize + codeGap) / 2;
  }

  const qrY = y - qrSize;
  drawQr(page, code, qrX, qrY, qrSize);
  y = qrY - (compact ? 9 : 12) * MM * scale;

  if (!compact) {
    centred(page, 'Or open the app and enter this code', f.regular, 10 * scale, y, SOFT);
    y -= 10 * MM * scale;
  }

  centred(page, code, f.mono, (compact ? 17 : 26) * scale, y, INK, (compact ? 1.5 : 3) * scale);

  if (!compact) {
    centred(page, joinUrl(code).replace('https://', ''), f.regular, 8 * scale, 10 * MM, SOFT);
  }
}

export async function renderQrPack(displayName: string, code: string): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  pdf.setTitle(`${displayName} - join QR pack`);
  pdf.setSubject(`Join code ${code}`);
  pdf.setProducer('Crayora console');
  pdf.setCreator('Crayora console');

  const f: Fonts = {
    bold: await pdf.embedFont(StandardFonts.HelveticaBold),
    regular: await pdf.embedFont(StandardFonts.Helvetica),
    mono: await pdf.embedFont(StandardFonts.CourierBold),
  };

  assertPrintable(f.bold, displayName, 'The display name');

  // 1. Counter card - A5 portrait.
  layout(pdf.addPage([148 * MM, 210 * MM]), f, displayName, code, 1);

  // 2. Mirror sticker - 100 mm square, QR and code only. Anything smaller
  //    than this and a phone at arm's length struggles to focus on it.
  layout(pdf.addPage([100 * MM, 100 * MM]), f, displayName, code, 1, true);

  // 3. Reception poster - A4 portrait, the same card scaled up.
  layout(pdf.addPage([210 * MM, 297 * MM]), f, displayName, code, 1.42);

  return pdf.save();
}
