// Static server for the prototype.
//   node tools/serve.mjs [port]          the whole repo on http://127.0.0.1:8737 (desktop preview, videos, tools)
//   node tools/serve.mjs --port 8738 --root prototype --live --public
//                                        the phone test build (behind Caddy, see tools/phone/)
// Options:
//   --root DIR   serve DIR (relative to the repo) instead of the repo
//   --live       pages reload whenever a file under the root changes (server-sent events on /__live)
//   --public     safe to expose: dotfiles are refused (and SF Pro fonts never leave the server: they
//                live outside prototype/, Apple's licence forbids redistributing them)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const flag = (name) => argv.includes(`--${name}`);
const option = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : fallback;
};
const root = path.resolve(repo, option('root', '.'));
const port = Number(option('port', /^\d+$/.test(argv[0] || '') ? argv[0] : 8737));
const live = flag('live');
const isPublic = flag('public');

const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.woff2': 'font/woff2', '.mp4': 'video/mp4', '.metal': 'text/plain; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
};

// Live reload: every page keeps an EventSource on __live and reloads when the version changes.
// The version starts with the boot time, so a restarted server reloads open pages too.
const boot = Date.now().toString(36);
let version = `${boot}.0`;
let changes = 0;
const clients = new Set();
const liveClient = '<script>(() => { let v = null; const es = new EventSource(\'__live\');'
  + ' es.onmessage = (e) => { if (v !== null && e.data !== v) location.reload(); v = e.data; }; })();</script>';
if (live) {
  let timer = null;
  fs.watch(root, { recursive: true }, (_event, file) => {
    if (!file || /(^|\/)\./.test(file) || /~$|\.sw[px]$/.test(file)) return;
    clearTimeout(timer);
    timer = setTimeout(() => {
      version = `${boot}.${++changes}`;
      for (const res of clients) res.write(`data: ${version}\n\n`);
      console.log(`changed ${file} → reloading ${clients.size} page(s)`);
    }, 150);
  });
  // Comments keep idle proxies (and phones) from dropping the stream.
  setInterval(() => { for (const res of clients) res.write(': ping\n\n'); }, 25000).unref();
}

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (live && url.pathname === '/__live') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', 'x-accel-buffering': 'no' });
    res.write(`retry: 1000\ndata: ${version}\n\n`);
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }
  let rel;
  try { rel = decodeURIComponent(url.pathname); } catch (_) { res.writeHead(400); res.end(); return; }
  let p = path.normalize(path.join(root, rel));
  const inside = p === root || p.startsWith(root + path.sep);
  if (!inside || (isPublic && /(^|[\\/])\./.test(path.relative(root, p)))) { res.writeHead(404); res.end('not found'); return; }
  if (fs.existsSync(p) && fs.statSync(p).isDirectory()) p = path.join(p, 'index.html');
  fs.readFile(p, (err, data) => {
    if (err) { console.log('404', url.pathname); res.writeHead(404); res.end('not found'); return; }
    const ext = path.extname(p).toLowerCase();
    if (live && ext === '.html') {
      const html = data.toString('utf8');
      const at = html.lastIndexOf('</body>');
      data = at >= 0 ? html.slice(0, at) + liveClient + html.slice(at) : html + liveClient;
    }
    res.writeHead(200, {
      'content-type': types[ext] || 'application/octet-stream',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    });
    res.end(data);
  });
}).listen(port, '127.0.0.1', () => console.log(`serving ${root} on http://127.0.0.1:${port}${live ? ' (live reload)' : ''}`));
