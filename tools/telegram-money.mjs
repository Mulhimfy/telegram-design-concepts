// Money's icon in Telegram is a bitmap: "Settings/Gram" (Telegram-iOS f1dd7a2, gramd@3x.png, 29 × 24.33 pt;
// PresentationResourcesSettings.money). The money rig turns the sparkle inside the gem on its own, so the web
// prototype draws it as two images split exactly as the native module splits it (LivingIconImageSplit.swift):
// the gem (the sparkle's pixels filled with the gem's colour) and the sparkle (white, with the coverage it had).
// Drawn over one another they are the bitmap again.
// usage: node tools/telegram-money.mjs   (writes prototype/assets/icons/money-{gem,sparkle}@3x.png, prints the
//        sparkle's centre for prototype/src/ui/settings-screen.js)
import { writeFileSync } from 'node:fs';
import { inflateSync, deflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';

const COMMIT = 'f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838';
const URL_ = `https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/${COMMIT}/submodules/TelegramUI/Images.xcassets/Settings/Gram.imageset/gramd@3x.png`;
const OUT = fileURLToPath(new URL('../prototype/assets/icons/', import.meta.url));

function decode(buf) {
  let p = 8;
  let width = 0;
  let height = 0;
  const idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p);
    const type = buf.toString('latin1', p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      if (data[8] !== 8 || data[9] !== 6 || data[12] !== 0) throw new Error('expected 8-bit RGBA, not interlaced');
    }
    if (type === 'IDAT') idat.push(data);
    p += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * 4;
  const out = Buffer.alloc(stride * height);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const cur = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= 4 ? cur[x - 4] : 0;
      const b = prev[x];
      const c = x >= 4 ? prev[x - 4] : 0;
      let v = line[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const pp = a + b - c;
        const pa = Math.abs(pp - a);
        const pb = Math.abs(pp - b);
        const pc = Math.abs(pp - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      cur[x] = v & 255;
    }
    cur.copy(out, y * stride);
    prev = cur;
  }
  return { width, height, pixels: out };
}

function encode(width, height, pixels) {
  const crcTable = new Uint32Array(256).map((_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (b) => {
    let c = 0xffffffff;
    for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4);
    c.writeUInt32BE(crc(body));
    return Buffer.concat([len, body, c]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) pixels.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

// LivingIconImageSplit.split, for straight (not premultiplied) RGBA.
export function split({ width, height, pixels }) {
  const counts = new Map();
  for (let i = 0; i < pixels.length; i += 4) {
    if (pixels[i + 3] !== 255) continue;
    const key = (pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2];
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  const shape = [...counts.entries()].reduce((a, b) => (b[1] > a[1] ? b : a))[0];
  const color = [(shape >> 16) & 255, (shape >> 8) & 255, shape & 255];
  const channel = [0, 1, 2].reduce((a, b) => (color[b] < color[a] ? b : a));
  const span = 255 - color[channel];
  const base = Buffer.from(pixels);
  const sparkle = Buffer.alloc(pixels.length);
  let weight = 0;
  let sumX = 0;
  let sumY = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      if (pixels[i + 3] !== 255) continue;
      const s = Math.max(0, Math.min(1, (pixels[i + channel] - color[channel]) / span));
      if (s <= 0.02) continue;
      base[i] = color[0];
      base[i + 1] = color[1];
      base[i + 2] = color[2];
      sparkle[i] = 255;
      sparkle[i + 1] = 255;
      sparkle[i + 2] = 255;
      sparkle[i + 3] = Math.round(s * 255);
      weight += s;
      sumX += s * (x + 0.5);
      sumY += s * (y + 0.5);
    }
  }
  return { base, sparkle, center: [sumX / weight, sumY / weight], color };
}

const r = await fetch(URL_);
if (!r.ok) throw new Error(`${r.status} ${URL_}`);
const image = decode(Buffer.from(await r.arrayBuffer()));
const result = split(image);
writeFileSync(`${OUT}money-gem@3x.png`, encode(image.width, image.height, result.base));
writeFileSync(`${OUT}money-sparkle@3x.png`, encode(image.width, image.height, result.sparkle));
const pt = (v) => +(v / 3).toFixed(4);
console.log(JSON.stringify({ size: [image.width, image.height], sizePt: [pt(image.width), pt(image.height)], gem: `#${result.color.map((v) => v.toString(16).padStart(2, '0')).join('')}`, sparkleCenterPt: result.center.map(pt) }));
