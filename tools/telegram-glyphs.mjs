// Telegram's own Settings glyphs at Telegram-iOS f1dd7a2 (the vector PDFs of Images.xcassets), as SVG path
// data in the 30 × 30 y-down space of prototype/assets/icons. The prototype's icon files were made from them
// (--svg), and the Swift Living Icons are checked against them (ios/Standalone/LivingIconsCore: every icon's
// parts, at rest, must cover exactly Telegram's glyph).
//
// usage: node tools/telegram-glyphs.mjs > ios/Standalone/LivingIconsCore/Tests/LivingIconsCoreTests/Resources/telegram-glyphs.json
//        node tools/telegram-glyphs.mjs --svg <icon> > prototype/assets/icons/<icon>.svg
//        node tools/telegram-glyphs.mjs --swift <icon>    (Swift literals of one glyph)
import { inflateSync } from 'node:zlib';

const COMMIT = 'f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838';
const BASE = `https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/${COMMIT}/submodules/TelegramUI/Images.xcassets/`;

// The prototype's icon → the asset Telegram draws in that row (PresentationResourcesSettings.swift :120-319,
// PeerInfoSettingsItems.swift :65-76 for the profile's own rows).
export const GLYPHS = {
  'ic-profile': 'Item List/Icons/Profile.imageset/profile.pdf',
  'ic-proxy': 'Item List/Icons/Proxy.imageset/shieldprx.pdf',
  'ic-saved': 'Item List/Icons/SavedMessages.imageset/bookmark.pdf',
  'ic-phone': 'Item List/Icons/Phone.imageset/phone.pdf',
  'ic-devices': 'Item List/Icons/Devices.imageset/devices.pdf',
  'ic-folder': 'Item List/Icons/Folder.imageset/folder.pdf',
  'ic-bell': 'Item List/Icons/Notifications.imageset/bell.pdf',
  'ic-lock': 'Item List/Icons/Privacy.imageset/lock.pdf',
  'ic-data': 'Item List/Icons/Data.imageset/storage.pdf',
  'ic-appearance': 'Item List/Icons/Appearance.imageset/appearance.pdf',
  'ic-power': 'Item List/Icons/PowerSaving.imageset/battery.pdf',
  'ic-language': 'Item List/Icons/Language.imageset/globe.pdf',
  'ic-premium': 'Item List/Icons/Premium.imageset/premium.pdf',
  'ic-stars': 'Item List/Icons/Stars.imageset/stars.pdf',
  'ic-business': 'Item List/Icons/Business.imageset/business.pdf',
  'ic-gift': 'Item List/Icons/Gift.imageset/gift.pdf',
  'ic-ask': 'Item List/Icons/Support.imageset/support.pdf',
  'ic-faq': 'Item List/Icons/Faq.imageset/question.pdf',
  'ic-features': 'Item List/Icons/Tips.imageset/lamp.pdf',
  'set-emoji-status': 'Settings/EditEmojiStatus.imageset/editstatus_30.pdf',
  'set-avatar': 'Settings/SetAvatar.imageset/addphoto_30.pdf',
  'set-covercolor': 'Premium/BoostPerk/CoverColor.imageset/covercolor_30.pdf',
};

const fmt = (v) => {
  const r = Math.round(v * 1e6) / 1e6;
  return String(Object.is(r, -0) ? 0 : r);
};

// The painted paths of a small vector PDF: content streams (FlateDecode or plain) with q/Q, cm, w,
// m/l/c/v/y/h/re and f/f*/S/B. A black stream beside a coloured one is a soft-mask form, not paint.
export function pdfPaths(buf) {
  const text = buf.toString('latin1');
  const mb = text.match(/\/MediaBox\s*\[([^\]]*)\]/)[1].trim().split(/\s+/).map(Number);
  const height = mb[3];
  const re = /<<([\s\S]*?)>>\s*stream\r?\n/g;
  const streams = [];
  let m;
  while ((m = re.exec(text))) {
    const dict = m[1];
    const start = m.index + m[0].length;
    const end = text.indexOf('endstream', start);
    let data = buf.subarray(start, end);
    if (/\/Subtype\s*\/XML/.test(dict) || /\/N\s+3/.test(dict)) continue;
    if (/FlateDecode/.test(dict)) {
      try { data = inflateSync(data); } catch { continue; }
    }
    const s = data.toString('latin1');
    if (/ (m|l|c|re)\s/.test(s)) streams.push(s);
  }
  const black = (s) => /0\.000000 0\.000000 0\.000000 scn/.test(s);
  const painted = streams.some((s) => !black(s)) ? streams.filter((s) => !black(s)) : streams;
  const out = [];
  for (const s of painted) {
    const toks = s.split(/\s+/).filter(Boolean);
    let stack = [];
    let ctm = [1, 0, 0, 1, 0, 0];
    const saved = [];
    let lw = 1;
    let d = [];
    let cur = [0, 0];
    const mul = (a, b) => [a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2], a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5]];
    const P = (x, y) => `${fmt(ctm[0] * x + ctm[2] * y + ctm[4])} ${fmt(height - (ctm[1] * x + ctm[3] * y + ctm[5]))}`;
    const scale = () => Math.sqrt(Math.abs(ctm[0] * ctm[3] - ctm[1] * ctm[2]));
    for (const t of toks) {
      if (/^[-+]?(\d+\.?\d*|\.\d+)$/.test(t)) { stack.push(Number(t)); continue; }
      switch (t) {
        case 'q': saved.push([ctm, lw]); break;
        case 'Q': [ctm, lw] = saved.pop(); break;
        case 'cm': ctm = mul(stack.slice(-6), ctm); break;
        case 'w': lw = stack[stack.length - 1]; break;
        case 'm': d.push(`M${P(stack[0], stack[1])}`); cur = [stack[0], stack[1]]; break;
        case 'l': d.push(`L${P(stack[0], stack[1])}`); cur = [stack[0], stack[1]]; break;
        case 'c': d.push(`C${P(stack[0], stack[1])} ${P(stack[2], stack[3])} ${P(stack[4], stack[5])}`); cur = [stack[4], stack[5]]; break;
        case 'v': d.push(`C${P(cur[0], cur[1])} ${P(stack[0], stack[1])} ${P(stack[2], stack[3])}`); cur = [stack[2], stack[3]]; break;
        case 'y': d.push(`C${P(stack[0], stack[1])} ${P(stack[2], stack[3])} ${P(stack[2], stack[3])}`); cur = [stack[2], stack[3]]; break;
        case 'h': d.push('Z'); break;
        case 're': { const [x, y, w, h] = stack; d.push(`M${P(x, y)}L${P(x + w, y)}L${P(x + w, y + h)}L${P(x, y + h)}Z`); break; }
        case 'f': case 'F': case 'f*': case 'B': case 'B*': case 'b': case 'b*':
          out.push({ d: d.join(''), evenOdd: t.endsWith('*') });
          d = [];
          break;
        case 'S': case 's':
          out.push({ d: d.join(''), stroke: Number(fmt(lw * scale())) });
          d = [];
          break;
        case 'n': d = []; break;
        default: break;
      }
      if (t !== 'q' && t !== 'Q') stack = [];
    }
  }
  return out;
}

async function fetchPDF(asset) {
  const url = BASE + asset.split('/').map(encodeURIComponent).join('/');
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  return Buffer.from(await r.arrayBuffer());
}

// A glyph as an icon file of prototype/assets/icons (the convention of the other converted files there).
export function svgFile(paths) {
  const lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="30pt" height="30pt" viewBox="0 0 30 30">'];
  for (const p of paths) {
    if (p.stroke) lines.push(`<path fill="none" stroke="rgb(100%, 100%, 100%)" stroke-width="${p.stroke}" d="${p.d}"/>`);
    else lines.push(`<path fill-rule="${p.evenOdd ? 'evenodd' : 'nonzero'}" fill="rgb(100%, 100%, 100%)" fill-opacity="1" d="${p.d}"/>`);
  }
  lines.push('</svg>');
  return lines.join('\n') + '\n';
}

if (process.argv[1].endsWith('telegram-glyphs.mjs')) {
  const swift = process.argv.indexOf('--swift');
  const svg = process.argv.indexOf('--svg');
  if (svg > 0) {
    // usage: node tools/telegram-glyphs.mjs --svg ic-power > prototype/assets/icons/ic-power.svg
    process.stdout.write(svgFile(pdfPaths(await fetchPDF(GLYPHS[process.argv[svg + 1]]))));
  } else if (swift > 0) {
    const name = process.argv[swift + 1];
    const paths = pdfPaths(await fetchPDF(GLYPHS[name]));
    for (const p of paths) {
      const opts = [p.evenOdd ? ', evenOdd: true' : '', p.stroke ? `, stroke: ${p.stroke}` : ''].join('');
      console.log(`        LivingIconSource(.path("${p.d}")${opts}),`);
    }
  } else {
    const out = { commit: COMMIT, glyphs: {} };
    for (const [name, asset] of Object.entries(GLYPHS)) {
      out.glyphs[name] = { asset: asset.replace(/\.imageset\/.*$/, ''), paths: pdfPaths(await fetchPDF(asset)) };
    }
    process.stdout.write(JSON.stringify(out, null, 1));
  }
}
