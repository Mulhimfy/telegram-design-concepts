// Telegram's HapticFeedback API shape (Display/Source/HapticFeedback.swift):
// impact(.light | .medium | .heavy | .soft | .rigid), tap() (selection), success().
// On the web: Vibration API where it exists (Android), and on iOS 18+ Safari the
// `<input type=checkbox switch>` toggle, which the system answers with a haptic tick.
// Inside Telegram (opened as a Mini App) the app's own HapticFeedback takes over (core/telegram.js).

let iosSwitch = null;
let lastTick = 0;
let host = null; // native haptics from the host app (Telegram Mini App), when there is one
const listeners = new Set();

function iosTick() {
  if (!iosSwitch) {
    const label = document.createElement('label');
    label.style.cssText = 'position:fixed;left:-100px;top:-100px;opacity:0;pointer-events:none';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.setAttribute('switch', '');
    label.appendChild(input);
    document.body.appendChild(label);
    iosSwitch = label;
  }
  iosSwitch.click();
}

const isIOS = typeof navigator !== 'undefined' && /iP(hone|ad|od)/.test(navigator.userAgent);

// Android vibration motors need ~10 ms before a pulse can be felt at all (Chrome also
// ignores vibrate() until the page has had a first tap).
const patterns = { light: 14, soft: 11, medium: 24, heavy: 34, rigid: 18, selection: 10, success: [14, 50, 22] };

export const Haptics = {
  prepare() {},
  useHost(fn) { host = fn; },
  impact(style = 'medium') {
    const now = performance.now();
    if (now - lastTick < 28) return;
    lastTick = now;
    listeners.forEach((l) => l(style));
    if (host) {
      try { host(style); } catch (_) {}
    } else if (isIOS) {
      try { iosTick(); } catch (_) {}
    } else if (navigator.vibrate) {
      try { navigator.vibrate(patterns[style] || 10); } catch (_) {}
    }
  },
  tap() { this.impact('selection'); },
  success() { this.impact('success'); },
  onEvent(fn) { listeners.add(fn); return () => listeners.delete(fn); },
};
