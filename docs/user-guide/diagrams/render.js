#!/usr/bin/env node
/* Render every user-guide diagram (HTML) to a 2x PNG for the PDF.
 *
 * The diagram sources are hand-written HTML + the shared diagram.css, the same
 * pattern the repo already uses for docs/diagrams/*.html. Chromium is taken from
 * the ms-playwright cache: the snap build aborts inside this container, and a
 * screenshot against the snap would silently produce a cropped or blank image.
 *
 * Usage:  node docs/user-guide/diagrams/render.js [name.html ...]
 *         (no args = every *.html in this folder)
 *
 * Exits non-zero when a diagram overflows the sheet or clipped its own text, so
 * a broken layout fails here instead of shipping into the PDF.
 */
const fs = require('fs');
const path = require('path');

function loadPlaywright() {
  const candidates = [
    path.join(__dirname, '..', '..', '..', '..', 'hermes', 'skills', 'creative', 'deck-design-pdf', 'node_modules'),
    '/root/.hermes/skills/creative/deck-design-pdf/node_modules',
  ];
  for (const dir of candidates) {
    try { return require(path.join(dir, 'playwright')); } catch (_) { /* next */ }
  }
  throw new Error('playwright not found; expected the deck-design-pdf node_modules');
}

function chromiumBinary() {
  const root = '/root/.cache/ms-playwright';
  const builds = fs.readdirSync(root)
    .filter((d) => /^chromium-\d+$/.test(d))
    .sort((a, b) => Number(a.split('-')[1]) - Number(b.split('-')[1]));
  if (!builds.length) throw new Error(`no chromium build under ${root}`);
  return path.join(root, builds[builds.length - 1], 'chrome-linux64', 'chrome');
}

const DIR = __dirname;
const OUT = path.join(DIR, '..', 'images');
const SHEET_WIDTH = 1400;

/* The diagrams are flat-colour line art, so a 200-colour palette is
 * indistinguishable at print resolution (measured: 0.9 % RMSE against the
 * 24-bit render) and a third of the bytes — which matters because these PNGs
 * are committed next to the PDF. Skipped when ImageMagick is absent. */
function quantize(file) {
  const { spawnSync } = require('child_process');
  const probe = spawnSync('sh', ['-c', 'command -v convert'], { encoding: 'utf8' });
  if (probe.status !== 0) return;
  const out = file.replace(/\.png$/, '.q.png');
  const res = spawnSync('convert', [file, '-strip', '-colors', '200', `PNG8:${out}`]);
  if (res.status === 0 && fs.existsSync(out)) fs.renameSync(out, file);
}

(async () => {
  const { chromium } = loadPlaywright();
  fs.mkdirSync(OUT, { recursive: true });

  const files = process.argv.slice(2).length
    ? process.argv.slice(2)
    : fs.readdirSync(DIR).filter((f) => f.endsWith('.html')).sort();

  const browser = await chromium.launch({
    executablePath: chromiumBinary(),
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none'],
  });
  const context = await browser.newContext({
    viewport: { width: SHEET_WIDTH + 120, height: 1000 },
    deviceScaleFactor: 2,
  });

  let failed = 0;
  for (const file of files) {
    const page = await context.newPage();
    const url = 'file://' + path.join(DIR, file);
    await page.goto(url, { waitUntil: 'load', timeout: 60000 });
    await page.evaluate(() => document.fonts.ready);

    const report = await page.evaluate((width) => {
      const sheet = document.querySelector('#sheet');
      if (!sheet) return { error: 'no #sheet element' };
      const sheetBox = sheet.getBoundingClientRect();
      const problems = [];
      for (const el of sheet.querySelectorAll('*')) {
        const box = el.getBoundingClientRect();
        if (box.width === 0 || box.height === 0) continue;
        if (box.right > sheetBox.right + 1) {
          problems.push(`overflows the sheet: <${el.tagName.toLowerCase()} class="${el.className}">`);
        }
        if (el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0) {
          problems.push(`clipped text: <${el.tagName.toLowerCase()} class="${el.className}">`);
        }
      }
      return {
        width: sheetBox.width,
        height: Math.ceil(sheetBox.height),
        problems: [...new Set(problems)].slice(0, 8),
        count: problems.length,
        tooWide: sheetBox.width > width,
      };
    }, SHEET_WIDTH);

    const outName = file.replace(/\.html$/, '.png');
    const outPath = path.join(OUT, outName);
    await page.locator('#sheet').screenshot({ path: outPath, timeout: 60000 });
    quantize(outPath);

    const ok = !report.error && !report.tooWide && report.count === 0;
    if (!ok) failed += 1;
    console.log(
      `${ok ? 'PASS' : 'FAIL'} ${outName} ${report.width}x${report.height}` +
      (report.error ? ` — ${report.error}` : '') +
      (report.tooWide ? ` — sheet wider than ${SHEET_WIDTH}px` : '') +
      (report.problems && report.problems.length ? `\n     ${report.problems.join('\n     ')}` : '')
    );
    await page.close();
  }

  await browser.close();
  if (failed) {
    console.error(`\n${failed} diagram(s) failed layout checks`);
    process.exit(1);
  }
  console.log(`\n${files.length} diagram(s) rendered into ${OUT}`);
})();
