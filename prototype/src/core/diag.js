// Field diagnostics for chasing a phone-only bug: script errors and a one-line summary of each swipe's 3D rig,
// posted to `log` next to the page — the Cloudflare worker prints them (`wrangler pages deployment tail`), the
// live dev server appends them to a file. Nothing personal: the browser, the screen size and the numbers of the
// swipe. Only with ?diag=1 (it found why left-swipe letters seemed to turn only on full swipes; fixed), never
// in recordings (?record=1).
const browser = typeof window !== 'undefined' && typeof location !== 'undefined';
const params = new URLSearchParams(browser ? location.search : '');
const on = browser && params.get('diag') === '1' && params.get('record') !== '1';
export const diagOn = on;
const session = Math.random().toString(36).slice(2, 8);
let queue = [];
let timer = null;

export function diag(type, data = {}) {
  if (!on) return;
  queue.push({ t: Math.round(performance.now()), type, ...data });
  if (queue.length > 40) queue.shift();
  if (!timer) timer = setTimeout(flush, 2000);
}

function flush() {
  timer = null;
  if (!queue.length) return;
  const body = JSON.stringify({ s: session, ua: navigator.userAgent, w: innerWidth, h: innerHeight, dpr: devicePixelRatio, items: queue.splice(0) });
  try {
    if (!(navigator.sendBeacon && navigator.sendBeacon('log', body))) fetch('log', { method: 'POST', body, keepalive: true }).catch(() => {});
  } catch (_) {}
}

if (on) {
  addEventListener('error', (e) => diag('error', { msg: String(e.message), at: `${(e.filename || '').split('/').pop()}:${e.lineno}:${e.colno}` }));
  addEventListener('unhandledrejection', (e) => diag('rejection', { msg: String((e.reason && (e.reason.stack || e.reason.message)) || e.reason).slice(0, 400) }));
  addEventListener('pagehide', flush);
}
