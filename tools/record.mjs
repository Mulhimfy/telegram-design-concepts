// Frame-exact demo recorder: steps the page's virtual clock 1/fps at a time, captures
// each frame and pipes it into ffmpeg (H.264, yuv420p). Nothing depends on how fast
// this machine is: every frame is rendered at its exact time.
//
// usage: node tools/record.mjs --out renders/coin-demo.mp4 [--url …] [--fps 60] [--from 0] [--to 12]   (video seconds)
//        [--size 1080] [--sheet renders/sheet-dir --every 6]   (contact frames instead of video)
import puppeteer from 'puppeteer-core';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const BT709 = 'scale=in_color_matrix=bt601:in_range=pc:flags=accurate_rnd+full_chroma_int,format=rgb48le,'
  + 'scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,'
  + 'setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => {
  if (v.startsWith('--')) acc.push([v.slice(2), a[i + 1] && !a[i + 1].startsWith('--') ? a[i + 1] : true]);
  return acc;
}, []));

const fps = Number(args.fps || 60);
const size = Number(args.size || 1080);
const url = args.url || `http://127.0.0.1:8737/prototype/?composition=square&record=1&device=iphone16pro`;
const out = args.out || '/root/tgdesign/renders/coin-demo.mp4';
const sheetDir = args.sheet;
const every = Number(args.every || 6);

const profileDir = fs.mkdtempSync('/root/tgdesign/.chrome-tmp-');
const browser = await puppeteer.launch({
  executablePath: '/usr/bin/google-chrome',
  headless: 'new',
  userDataDir: profileDir,
  args: ['--no-sandbox', '--disable-gpu-compositing', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
    '--disable-dev-shm-usage', '--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none',
    '--disable-background-timer-throttling', '--disable-renderer-backgrounding'],
});
let ff = null;
const shutdown = async () => {
  try { await browser.close(); } catch (_) {}
  try { if (ff && ff.exitCode === null) ff.kill(); } catch (_) {}
  fs.rmSync(profileDir, { recursive: true, force: true });
  process.exit(1);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
try {
  const page = await browser.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', e.message));
  page.on('console', (m) => { if (['error', 'warn'].includes(m.type()) && !m.text().includes('deprecated')) console.log('[page]', m.text()); });
  await page.setViewport({ width: size, height: size, deviceScaleFactor: 1 });
  await page.goto(url, { waitUntil: 'networkidle0' });
  await page.waitForFunction(() => document.body.dataset.ready === '1' || document.body.dataset.error, { timeout: 60000 });
  const err = await page.evaluate(() => document.body.dataset.error);
  if (err) throw new Error(err);
  // Video length: the script's page time, stretched where it plays in slow motion.
  const frames = await page.evaluate((fps) => window.__tg.demo.frameCount(fps), fps);
  const from = Number(args.from || 0);
  const total = args.to ? Math.min(frames, Math.round(Number(args.to) * fps)) : frames;
  const first = Math.round(from * fps);
  console.log(`rendering ${total - first} frames (${from}–${(total / fps).toFixed(2)}s of video @${fps}fps)`);
  const cdp = await page.createCDPSession();

  if (sheetDir) {
    fs.mkdirSync(sheetDir, { recursive: true });
  } else {
    fs.mkdirSync(path.dirname(out), { recursive: true });
    // Frames arrive as JPEG (full-range BT.601); the video is standard limited-range BT.709, tagged,
    // so every player (Telegram's included) shows the colours the page rendered.
    ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
      '-vf', BT709,
      // A short look-ahead keeps the encoder small (~100 MB less) next to Chrome on a shared box.
      '-c:v', 'libx264', '-preset', 'medium', '-rc-lookahead', '15', '-crf', '14', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
      '-movflags', '+faststart', '-threads', '1', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  }
  const t0 = Date.now();
  for (let f = 0; f < total; f++) {
    const capture = f >= first && (!sheetDir || (f - first) % every === 0);
    await page.evaluate((dt, draw) => window.__tg.demo.step(dt, draw), 1 / fps, capture);
    if (!capture) continue;
    const shot = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 93, optimizeForSpeed: true });
    const buf = Buffer.from(shot.data, 'base64');
    if (sheetDir) {
      fs.writeFileSync(path.join(sheetDir, `f${String(f).padStart(5, '0')}.jpg`), buf);
    } else if (!ff.stdin.write(buf)) {
      await new Promise((r) => ff.stdin.once('drain', r));
    }
    if (f % 60 === 0) {
      const el = (Date.now() - t0) / 1000;
      console.log(`frame ${f}/${total}  ${(el / Math.max(1, f - first + 1)).toFixed(2)} s/frame`);
    }
  }
  if (ff) {
    ff.stdin.end();
    await new Promise((r) => ff.on('close', r));
    console.log('saved', out);
  }
} finally {
  await browser.close();
  if (ff && ff.exitCode === null) ff.kill();
  fs.rmSync(profileDir, { recursive: true, force: true });
}
