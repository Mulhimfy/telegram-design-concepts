// Run scripted UI steps on the prototype in headless Chrome and screenshot after each one.
// usage: node tools/ui-check.mjs --url URL --steps steps.mjs --out DIR [--w 414 --h 896 --dpr 2 --mobile]
// steps.mjs: export default [{ name, js: 'async page-side code', wait: ms, shot: true }, …]
// Page-side helpers: tap(x, y), drag([[x,y],…], seconds), sleep(ms), T = window.__tg.
import puppeteer from 'puppeteer-core';
import { mkdtempSync, rmSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const profileDir = mkdtempSync('/root/tgdesign/.chrome-tmp-');
process.on('exit', () => { try { rmSync(profileDir, { recursive: true, force: true }); } catch (_) {} });

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => {
  if (v.startsWith('--')) acc.push([v.slice(2), a[i + 1] && !a[i + 1].startsWith('--') ? a[i + 1] : true]);
  return acc;
}, []));
const steps = (await import(pathToFileURL(path.resolve(args.steps)).href)).default;
mkdirSync(args.out, { recursive: true });

const helpers = `
  window.sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  window.T = window.__tg;
  window.tap = async (x, y, hold = 90) => { const R = T.router; R.inject('down', [x, y], T.clock.now()); await sleep(hold); R.inject('up', [x, y], T.clock.now()); };
  window.drag = async (points, seconds = 0.4, release = true) => {
    const R = T.router; R.inject('down', points[0], T.clock.now());
    const n = Math.max(2, Math.round(seconds * 60));
    for (let i = 1; i <= n; i++) {
      await sleep(1000 / 60);
      const u = i / n, f = u * (points.length - 1), j = Math.min(points.length - 2, Math.floor(f)), t = f - j;
      R.inject('move', [points[j][0] + (points[j + 1][0] - points[j][0]) * t, points[j][1] + (points[j + 1][1] - points[j][1]) * t], T.clock.now());
    }
    const last = points[points.length - 1];
    if (release) R.inject('up', last, T.clock.now());
  };
`;

const browser = await puppeteer.launch({
  executablePath: '/usr/bin/google-chrome',
  headless: 'new',
  userDataDir: profileDir,
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
    '--disable-dev-shm-usage', '--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none'],
});
try {
  const page = await browser.newPage();
  page.on('console', (m) => { if (['error', 'warn'].includes(m.type()) && !/apple-mobile|Failed to load resource/.test(m.text())) console.log('[page]', m.type(), m.text()); });
  page.on('pageerror', (e) => console.log('[pageerror]', e.message));
  await page.setViewport({ width: Number(args.w || 414), height: Number(args.h || 896), deviceScaleFactor: Number(args.dpr || 2), isMobile: !!args.mobile, hasTouch: !!args.mobile });
  await page.goto(args.url, { waitUntil: 'networkidle2' });
  await page.waitForFunction(() => document.body.dataset.ready === '1' || document.body.dataset.error, { timeout: 30000 });
  const err = await page.evaluate(() => document.body.dataset.error);
  if (err) console.log('APP ERROR:', err);
  await page.evaluate(helpers);
  let i = 0;
  for (const s of steps) {
    const r = await page.evaluate(`(async () => { ${s.js || ''} })()`);
    if (r !== undefined) console.log(`${s.name}:`, typeof r === 'string' ? r : JSON.stringify(r));
    if (s.wait) await new Promise((res) => setTimeout(res, s.wait));
    if (s.shot !== false) {
      const file = path.join(args.out, `${String(++i).padStart(2, '0')}-${s.name}.png`);
      await page.screenshot({ path: file });
    }
  }
  console.log('done', i, 'shots');
} finally {
  await browser.close();
}
