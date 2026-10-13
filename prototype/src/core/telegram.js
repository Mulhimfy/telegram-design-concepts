// Telegram Mini App bridge. Opened from a bot's web_app button, Telegram appends
// #tgWebAppData=… to the URL, and the prototype gets what a web page cannot have on iOS:
// the system's own haptics (WebApp.HapticFeedback → UIImpactFeedbackGenerator /
// UISelectionFeedbackGenerator, the generators the native module drives), the user's colour
// scheme, and no swipe-to-minimise while the coin is being dragged.

export const inTelegram = /(^#|&)tgWebApp(Data|Version|Platform)=/.test(location.hash);

export async function initTelegram() {
  if (!inTelegram) return null;
  if (!window.Telegram?.WebApp) {
    await new Promise((resolve) => {
      const s = document.createElement('script');
      s.src = 'https://telegram.org/js/telegram-web-app.js';
      s.onload = resolve;
      s.onerror = resolve;
      document.head.appendChild(s);
      setTimeout(resolve, 3000); // never hold the prototype hostage to the network
    });
  }
  const tg = window.Telegram?.WebApp;
  if (!tg) return null;
  tg.ready();
  if (tg.isVersionAtLeast('7.7')) tg.disableVerticalSwipes();
  if (!tg.isExpanded) {
    // The layout is built for the viewport it starts with: wait for the expansion to settle.
    await new Promise((resolve) => {
      const done = () => { tg.offEvent('viewportChanged', changed); resolve(); };
      const changed = (e) => { if (!e || e.isStateStable) done(); };
      tg.onEvent('viewportChanged', changed);
      tg.expand();
      setTimeout(done, 800);
    });
  }
  return tg;
}

// Haptics in Telegram's vocabulary (impact styles, selection, notification).
export function telegramHaptics(tg) {
  if (!tg || !tg.isVersionAtLeast('6.1') || !tg.HapticFeedback) return null;
  const h = tg.HapticFeedback;
  return (style) => {
    if (style === 'selection') h.selectionChanged();
    else if (style === 'success') h.notificationOccurred('success');
    else h.impactOccurred(style);
  };
}

// The Mini App header (bot name bar) takes the cover's top colour, so it reads as the
// status-bar area of the profile header.
export function setTelegramChrome(tg, { header, background }) {
  if (!tg) return;
  try {
    if (header && tg.isVersionAtLeast('6.9')) tg.setHeaderColor(header);
    if (background && tg.isVersionAtLeast('6.1')) tg.setBackgroundColor(background);
    if (background && tg.isVersionAtLeast('7.10')) tg.setBottomBarColor(background);
  } catch (_) {}
}
