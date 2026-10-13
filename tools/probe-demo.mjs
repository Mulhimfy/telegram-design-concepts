// Steps a demo script without rendering and reports where the coin lands (for tuning scripts).
// usage: node tools/probe-demo.mjs "<url>" [override JSON for window.__probe]
import puppeteer from 'puppeteer-core';
import { mkdtempSync, rmSync } from 'node:fs';
const profileDir = mkdtempSync('/root/tgdesign/.chrome-tmp-');
const url = process.argv[2];
const b = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: 'new', userDataDir: profileDir,
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'] });
try {
  const p = await b.newPage();
  await p.setViewport({ width: 1080, height: 1080 });
  await p.goto(url, { waitUntil: 'networkidle0' });
  await p.waitForFunction(() => document.body.dataset.ready === '1');
  const r = await p.evaluate(() => {
    const tg = window.__tg;
    const lands = [];
    const prev = tg.physics.onLand;
    tg.physics.onLand = (changed, face) => {
      lands.push({ t: +tg.demo.t.toFixed(2), changed, face, content: String(tg.physics.contentForFace(face)) });
      prev(changed, face);
    };
    const total = Math.round(tg.demo.duration * 60);
    for (let i = 0; i < total; i++) tg.demo.step(1 / 60, false);
    return { lands, final: String(tg.physics.contentForFace(tg.physics.face)) };
  });
  console.log(JSON.stringify(r));
} finally { await b.close(); rmSync(profileDir, { recursive: true, force: true }); }
