// Screenshot the prototype in headless Chrome (SwiftShader WebGL2).
// usage: node tools/shot.mjs --url "http://127.0.0.1:8737/prototype/?device=iphone11" --w 414 --h 896 --dpr 2 --out a.png [--eval "js"] [--evalFile f.js]
//        --mobile: emulate a phone (touch, coarse pointer), as the page sees it on an iPhone
import puppeteer from 'puppeteer-core';
import { mkdtempSync, rmSync } from 'node:fs';
const profileDir = mkdtempSync('/root/tgdesign/.chrome-tmp-');
process.on('exit', () => { try { rmSync(profileDir, { recursive: true, force: true }); } catch (_) {} });
import fs from 'node:fs';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => {
  if (v.startsWith('--')) acc.push([v.slice(2), a[i + 1] && !a[i + 1].startsWith('--') ? a[i + 1] : true]);
  return acc;
}, []));

const browser = await puppeteer.launch({
  executablePath: '/usr/bin/google-chrome',
  headless: 'new',
  userDataDir: profileDir,
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
    '--disable-dev-shm-usage', '--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none'],
});
try {
  const page = await browser.newPage();
  page.on('console', (m) => { if (['error', 'warning', 'warn'].includes(m.type())) console.log('[page]', m.type(), m.text()); });
  page.on('pageerror', (e) => console.log('[pageerror]', e.message));
  await page.setViewport({ width: Number(args.w || 414), height: Number(args.h || 896), deviceScaleFactor: Number(args.dpr || 2), isMobile: !!args.mobile, hasTouch: !!args.mobile });
  await page.goto(args.url, { waitUntil: 'networkidle2' }); // networkidle2: a live-reload stream stays open
  await page.waitForFunction(() => document.body.dataset.ready === '1' || document.body.dataset.error, { timeout: 30000 });
  const err = await page.evaluate(() => document.body.dataset.error);
  if (err) { console.log('APP ERROR:', err); }
  if (args.evalFile) await page.evaluate(fs.readFileSync(args.evalFile, 'utf8'));
  if (args.eval) { const r = await page.evaluate(args.eval); if (r !== undefined) console.log('eval:', typeof r === 'string' ? r : JSON.stringify(r)); }
  await new Promise((r) => setTimeout(r, Number(args.wait || 150)));
  await page.screenshot({ path: args.out || 'shot.png', type: 'png' });
  console.log('saved', args.out);
} finally {
  await browser.close();
}
