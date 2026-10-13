// Render a grid of coin poses (header crop) for look-dev.
// usage: node tools/poses.mjs OUT.png [device]
import puppeteer from 'puppeteer-core';
import { mkdtempSync, rmSync } from 'node:fs';
const profileDir = mkdtempSync('/root/tgdesign/.chrome-tmp-');
process.on('exit', () => { try { rmSync(profileDir, { recursive: true, force: true }); } catch (_) {} });
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
const out = process.argv[2] || 'poses.png';
const device = process.argv[3] || 'iphone11';
const extra = process.argv[5] || '';
const D = Math.PI / 180;
const posesA = [
  { label: 'rest', q: { lift: 0, glass: 0 } },
  { label: 'pressed', q: { lift: 1, glass: 1, yaw: 0.12, pitch: -0.05 } },
  { label: 'yaw 30', q: { yaw: -30 * D, pitch: 0.06 } },
  { label: 'yaw 60', q: { yaw: -60 * D, pitch: 0.1 } },
  { label: 'yaw 80', q: { yaw: -80 * D, pitch: 0.12 } },
  { label: 'yaw 90 (edge)', q: { yaw: -90 * D, pitch: 0.15 } },
  { label: 'yaw 110 (back)', q: { yaw: -110 * D, pitch: 0.1 } },
  { label: 'yaw 150', q: { yaw: -150 * D, pitch: 0.05 } },
  { label: 'yaw 180 back', q: { yaw: -180 * D, pitch: 0 } },
  { label: 'pitch -35', q: { yaw: -15 * D, pitch: -35 * D } },
  { label: 'toss 1.18', q: { yaw: -40 * D, pitch: 0.2, lift: 1.18 } },
  { label: 'jelly -0.2', q: { yaw: 0, pitch: 0, lift: -0.2, glass: 0.3 } },
];
const posesB = [
  { label: 'yaw -12', q: { yaw: -12 * D } },
  { label: 'yaw -20', q: { yaw: -20 * D } },
  { label: 'yaw -28', q: { yaw: -28 * D } },
  { label: 'yaw -40', q: { yaw: -40 * D } },
  { label: 'yaw +20', q: { yaw: 20 * D } },
  { label: 'yaw +31', q: { yaw: 31 * D } },
  { label: 'yaw +45', q: { yaw: 45 * D } },
  { label: 'pitch +18', q: { pitch: 18 * D } },
  { label: 'yaw -25 pitch -12', q: { yaw: -25 * D, pitch: -12 * D } },
  { label: 'yaw -135', q: { yaw: -135 * D } },
  { label: 'blur spin', q: { yaw: -200 * D, yawVelocity: -30 } },
  { label: 'pressed', q: { yaw: 0.1, pitch: -0.06 } },
];
const posesC = [
  { label: 'rest', q: { lift: 0, glass: 0, sideA: 0, sideB: 1 } },
  { label: 'pressed', q: { yaw: 0.12, pitch: -0.05, sideA: 0, sideB: 1 } },
  { label: 'yaw -45', q: { yaw: -45 * D, pitch: 0.08, sideA: 0, sideB: 1 } },
  { label: 'yaw -80', q: { yaw: -80 * D, pitch: 0.1, sideA: 0, sideB: 1 } },
  { label: 'yaw -100', q: { yaw: -100 * D, pitch: 0.1, sideA: 0, sideB: 1 } },
  { label: 'yaw -135', q: { yaw: -135 * D, pitch: 0.06, sideA: 0, sideB: 1 } },
  { label: 'yaw -180 photo2', q: { yaw: -180 * D, sideA: 0, sideB: 1 } },
  { label: 'yaw -28 glint', q: { yaw: -28 * D, pitch: -0.1, sideA: 0, sideB: 1 } },
  { label: 'yaw +31 strip', q: { yaw: 31 * D, sideA: 0, sideB: 3 } },
  { label: 'pitch -30', q: { yaw: -10 * D, pitch: -30 * D, sideA: 0, sideB: 1 } },
  { label: 'blur', q: { yaw: -260 * D, yawVelocity: -28, sideA: 2, sideB: 1 } },
  { label: 'toss', q: { yaw: -40 * D, pitch: 0.2, lift: 1.18, sideA: 0, sideB: 1 } },
];
const poses = (process.argv[4] === 'B') ? posesB : (process.argv[4] === 'C') ? posesC : posesA;
const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: 'new', userDataDir: profileDir,
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--disable-dev-shm-usage', '--hide-scrollbars', '--force-color-profile=srgb'] });
const tiles = [];
try {
  const page = await browser.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', e.message));
  await page.setViewport({ width: device === 'iphone16pro' ? 402 : 414, height: device === 'iphone16pro' ? 874 : 896, deviceScaleFactor: 3 });
  await page.goto(`http://127.0.0.1:8737/prototype/?device=${device}&record=1${extra}`, { waitUntil: 'networkidle0' });
  await page.waitForFunction(() => document.body.dataset.ready === '1' || document.body.dataset.error);
  const err = await page.evaluate(() => document.body.dataset.error); if (err) console.log(err);
  const dir = '/root/tgdesign/renders/poses'; fs.mkdirSync(dir, { recursive: true });
  for (let i = 0; i < poses.length; i++) {
    await page.evaluate((q) => window.__tg.pose(q), poses[i].q);
    const f = `${dir}/pose-${String(i).padStart(2, '0')}.png`;
    await page.screenshot({ path: f, clip: device === 'iphone16pro' ? { x: 81, y: 46, width: 240, height: 170 } : { x: 87, y: 40, width: 240, height: 170 } });
    tiles.push([f, poses[i].label]);
  }
} finally { await browser.close(); }
// contact sheet via python
const py = `
import sys
from PIL import Image, ImageDraw
tiles=${JSON.stringify(tiles)}
ims=[Image.open(f) for f,_ in tiles]
w,h=ims[0].size; cols=4; rows=(len(ims)+cols-1)//cols
sheet=Image.new('RGB',(cols*w,rows*(h+30)),(20,20,20))
d=ImageDraw.Draw(sheet)
for i,(im,(f,l)) in enumerate(zip(ims,tiles)):
    x=(i%cols)*w; y=(i//cols)*(h+30)
    sheet.paste(im,(x,y+30)); d.text((x+8,y+8),l,fill=(255,230,120))
sheet.save('${out}')
`;
execFileSync('/root/tgdesign/tools/.venv-img/bin/python', ['-I', '-c', py]);
console.log('saved', out);
