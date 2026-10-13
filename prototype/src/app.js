// Entry point. Query parameters:
//   device=iphone11|iphone16pro   (default iphone11 = the user's phone, 414×896, no island)
//   composition=square            1080×1080 video stage (device frame, backdrop, camera)
//   record=1                      virtual clock, driven by tools/record.mjs
//   native=1                      use the real viewport (auto on phones)
//   theme=dark|light, palette=teal, name=, subtitle=
// Opened from a bot's web_app button it runs as a Telegram Mini App (core/telegram.js).
//
// The screen is the own profile in the Settings tab (one photo). Its avatar turns into
// glass under the finger and turns over to its back: the same photo by default, or a back
// photo added with "Add Back Photo"; "Change Glass Color" tints the glass and sends its
// light across the screen.

import { Color } from './core/color.js';
import { Clock } from './core/clock.js';
import { Haptics } from './core/haptics.js';
import { Animator, ease } from './core/animator.js';
import { SpringParams, SpringValue } from './core/spring.js';
import { initTelegram, telegramHaptics, setTelegramChrome } from './core/telegram.js';
import { Cover } from './ui/cover.js';
import { buildSettingsScreen, iconURL } from './ui/settings-screen.js';
import { LivingIcons } from './settings/living-icons.js';
import { NavStack } from './settings/nav.js';
import { buildSubPage } from './settings/subpages.js';
import { buildProfilePage } from './profile/profile-page.js';
import { crowSVG, ggStatusSVG, svgDataURL, loadImage } from './ui/glyphs.js';
import { LightLayer } from './ui/light.js';
import { TurnLight } from './ui/turn-light.js';
import { InputRouter } from './ui/input.js';
import { GLASS_COLORS, hexToRgb, glassColorSheet, backPhotoSheet } from './ui/glass-sheets.js';
import { ProfileScroll } from './ui/profile-scroll.js';
import { GlassCoin } from './coin/coin-physics.js';
import { CoinRenderer } from './coin/coin-renderer.js';
import { CoinController } from './coin/coin-controller.js';
import { Stage, buildDeviceFrame } from './stage.js';
import { Demo } from './demo.js';
import { buildChatsPage } from './chats/chats-page.js';
import { attachPointer } from './chats/chat-input.js';
import { glassDemoScript } from './scripts/coin-demo.js';
import { DEMOS } from './scripts/index.js';

const params = new URLSearchParams(location.search);

export const DEVICES = {
  iphone11: { name: 'iPhone 11', width: 414, height: 896, statusBar: 48, island: false, corner: 41.5, bottomInset: 34 },
  iphone16pro: { name: 'iPhone 16 Pro', width: 402, height: 874, statusBar: 54, island: true, corner: 55, bottomInset: 34 },
};

// Profile palettes (dark). Teal sampled from the user's phone (user-01.jpg).
export const PALETTES = {
  teal: { main: Color.hex('#2f6a7b'), secondary: Color.hex('#3c987c') },
  violet: { main: Color.hex('#6a4fd6'), secondary: Color.hex('#9a72ee') },
};

const BACK_PHOTOS = [1, 2, 3, 4, 5, 6, 8, 9].map((n) => `pick-${n}.jpg`); // + "None" = a 3 × 3 grid
const photoURL = (f) => new URL(`../assets/photos/${f}`, import.meta.url).href;

function detectNative() {
  if (params.has('native')) return params.get('native') !== '0';
  return Math.min(window.innerWidth, window.innerHeight) < 500 && matchMedia('(pointer: coarse)').matches;
}

function safeInset(side) {
  const probe = document.createElement('div');
  probe.style.cssText = `position:fixed;top:0;padding-top:env(safe-area-inset-${side});visibility:hidden`;
  document.body.appendChild(probe);
  const v = parseFloat(getComputedStyle(probe).paddingTop) || 0;
  probe.remove();
  return v;
}

async function main() {
  const tg = await initTelegram();
  const hostHaptics = telegramHaptics(tg);
  if (hostHaptics) Haptics.useHost(hostHaptics);

  const stageEl = document.getElementById('stage');
  const composition = params.get('composition');
  const native = !composition && detectNative();
  let device = { ...(DEVICES[params.get('device')] || (composition ? DEVICES.iphone16pro : DEVICES.iphone11)) };
  if (native) {
    // Home-screen app: the page runs under the status bar (inset = its height). Safari and Telegram
    // draw their own bars above the page (inset 0), so the header starts at the top like in the app.
    const top = safeInset('top');
    const coarse = matchMedia('(pointer: coarse)').matches;
    device = {
      name: 'native', width: window.innerWidth, height: window.innerHeight,
      statusBar: top > 0 ? top : coarse ? 0 : 20, island: top >= 51, corner: 0, native: true,
      bottomInset: safeInset('bottom'),
    };
    reloadOnResize(() => !!window.__tg?.router?.touch);
  }
  // On a phone the theme follows the system (or Telegram's) unless the link sets one.
  const systemTheme = tg ? tg.colorScheme : native ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : 'dark';
  const dark = (params.get('theme') || systemTheme) === 'dark';
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';

  const deviceEl = document.createElement('div');
  deviceEl.className = 'device';
  deviceEl.style.width = `${device.width}px`;
  deviceEl.style.height = `${device.height}px`;
  stageEl.appendChild(deviceEl);
  const screen = document.createElement('div');
  screen.className = 'screen';
  screen.style.width = `${device.width}px`;
  screen.style.height = `${device.height}px`;
  deviceEl.appendChild(screen);
  // The tab-bar screen (both tabs and the tab bar): pushed pages slide over it as one piece.
  const rootView = document.createElement('div');
  rootView.className = 'abs root-view';
  rootView.style.cssText = `left:0;top:0;width:${device.width}px;height:${device.height}px`;
  screen.appendChild(rootView);

  let stage = null;
  // Rendering scale for canvases (cover + coin), in px per pt.
  let renderScale;
  if (composition === 'square') {
    stage = new Stage(stageEl, deviceEl, screen, device);
    renderScale = 3;
  } else {
    // Desktop / framed preview: the phone with its bezel, fitted into the window.
    const framed = !native && params.get('frame') !== '0';
    if (framed) {
      deviceEl.appendChild(buildDeviceFrame(device));
      screen.style.borderRadius = `${device.corner}px`;
      stageEl.style.background = 'radial-gradient(ellipse at 50% 35%, #2a2d36 0%, #0d0e12 70%)';
    }
    const fit = () => {
      if (native) return;
      const margin = framed ? 40 : 0;
      const s = Math.min((window.innerWidth - margin) / device.width, (window.innerHeight - margin) / device.height);
      deviceEl.style.transform = `scale(${params.has('scale') ? parseFloat(params.get('scale')) : Math.min(1, s)})`;
    };
    fit();
    window.addEventListener('resize', fit);
    renderScale = Math.min(3, Math.max(window.devicePixelRatio || 1, params.has('dpr') ? parseFloat(params.get('dpr')) : 0));
  }

  await document.fonts.ready.catch(() => {});

  const palette = PALETTES[params.get('palette') || 'teal'] || PALETTES.teal;
  const glyph = await loadImage(svgDataURL(crowSVG));
  const persona = {
    name: params.get('name') || 'Ahmed',
    subtitle: params.get('subtitle') || '@ahmedevfy',
    statusImage: svgDataURL(ggStatusSVG()),
    time: params.get('time') || '9:41',
  };
  const ui = buildSettingsScreen(rootView, { device, persona, palette, dark });
  if (ui.statusBar?.el?.parentElement) screen.appendChild(ui.statusBar.el);   // stays put over pushed pages
  const G = ui.geometry;

  if (device.island) {
    const island = document.createElement('div');
    island.className = 'dynamic-island';
    // Island as drawn in the designer demo mockup (≈ 95 × 36.5 pt at 11 pt from the top).
    island.style.cssText = `position:absolute;left:${(device.width - 95) / 2}px;top:11.5px;width:95px;height:36.5px;border-radius:18.25px;background:#000;z-index:60`;
    deviceEl.appendChild(island);
  }

  // Cover
  const cover = new Cover(ui.cover);
  const coverParams = {
    width: G.W, height: G.backgroundHeight, canvasHeight: G.coverCanvasHeight, defaultHeight: G.defaultHeight,
    avatarCenter: G.avatarCenter, main: palette.main, secondary: palette.secondary,
    glyph, dark, scale: renderScale, avatarTransitionFraction: 0,
  };
  cover.draw(coverParams);
  if (stage) stage.setBackdropSource(ui.cover);
  // The bars around the page (Safari's status bar area, Telegram's Mini App header) take the
  // colour at the top of the screen so the header reads as one piece, as in the app: the
  // cover's top at rest, the navigation bar when collapsed, black over the expanded photo.
  const coverTop = coverTopColor(ui.cover) || palette.secondary.hex();
  const setTopColor = (state) => {
    if (!native) return;
    const color = state === 'banner' ? coverTop : state === 'photo' || dark ? '#000000' : '#ffffff';
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', color);
    setTelegramChrome(tg, { header: color, background: dark ? '#000000' : '#efeff4' });
  };
  setTopColor('banner');

  // Glass avatar
  const renderer = new CoinRenderer(ui.coin, { preserve: params.get('record') === '1' });
  const [avatarImage, ...backImages] = await Promise.all([
    loadImage(photoURL('ahmed-0.jpg')),
    ...BACK_PHOTOS.map((f) => loadImage(photoURL(f))),
  ]);
  renderer.setFace(0, avatarImage);
  renderer.updateCover(ui.cover, cover.version);

  // Both sides show the photo until a back photo is added.
  const physics = new GlassCoin({ photoCount: 1, back: 0 });
  const coinRect = { x: G.avatarCenter.x - G.coinSize / 2, y: G.avatarCenter.y - G.coinSize / 2 };
  const env = envColors(palette, dark);
  const clock = new Clock(params.get('record') === '1');
  const animator = new Animator();
  // The glass colour (Clear = no tint) and the flash of a colour change.
  const glassStyle = { index: 0, color: [1, 1, 1], tint: 0, flash: 0 };
  let coinScale = renderScale;
  let frameDt = 1 / 60;
  let lastFrameTime = clock.now();
  const controller = new CoinController({
    canvas: ui.coin, renderer, physics, sizePt: G.coinSize,
    getFrame: () => ({
      sizePt: { w: G.coinSize, h: G.coinSize },
      // In the video stage the canvas resolution follows the camera zoom (quantized).
      pxPerPt: stage ? Math.min(3, Math.max(1.5, Math.ceil(stage.pxPerPt * 4 * 1.05) / 4)) : coinScale,
      coverRectPt: [-coinRect.x, -coinRect.y, G.W, G.coverCanvasHeight],
      envLow: env.low, envHigh: env.high, dark,
      envRotation: 0,
      glassColor: glassStyle.color, glassTint: glassStyle.tint, flash: glassStyle.flash,
      dt: frameDt,
    }),
  });

  renderer.onRestore = () => { controller.needsFrame = true; };

  // Landing on the other side: the pattern bounces like a profile-colour change
  // (PeerInfoCoverComponent.animateTransition: sublayerTransform.scale [1, 1.14, 1] over 0.4 s).
  // The glass is dissolving by then, so the snapshot it refracts is only refreshed at the end
  // (uploading the cover texture every frame stalls phones).
  controller.onLand = (changed) => {
    if (!changed) return;
    animator.tween({
      duration: 0.4,
      apply: (u) => {
        coverParams.patternScale = u < 0.5 ? 1 + 0.14 * (u / 0.5) : 1.14 - 0.14 * ((u - 0.5) / 0.5);
        cover.draw(coverParams);
        if (u >= 1) renderer.updateCover(ui.cover, cover.version);
      },
    }, clock.now());
  };

  // Light of the glass colour over the whole screen.
  const light = new LightLayer(rootView, {
    device, scale: stage ? 2 : 1, origin: G.avatarCenter, radius: 50, cover,
    glassEls: [ui.qr, ui.cap, ui.tab], dark, under: ui.coin,
  });
  const lightGlass = light.glassEls;
  // …and the light the glass throws across the header while it turns.
  const turnLight = new TurnLight(rootView, { device, ui, light, cover, style: () => glassStyle, scale: stage ? 2 : 1 });

  // Scrolling: the header collapses into the navigation bar, pulling down expands the photo.
  const scroll = new ProfileScroll({
    screen: rootView, ui, device, dark, avatarImage, light, cover, coverParams,
    // Back at rest: the glass refracts the cover as drawn now.
    onRest: () => renderer.updateCover(ui.cover, cover.version),
    onTopChange: setTopColor,
  });

  // ------------------------------------------------------------- sheets

  let sheet = null;
  const sheets = [];
  const show = (s, now) => {
    if (!sheets.includes(s)) sheets.push(s);
    sheet = s;
    s.open(now);
  };
  const backRow = ui.rows.find((r) => r.id === 'backPhoto');
  // On a phone the choices survive the live reload (per browser; never in a recording).
  const prefs = clock.virtual ? null : loadPrefs();
  const savePrefs = () => {
    if (!prefs) return;
    try { localStorage.setItem('glassAvatar', JSON.stringify({ color: glassStyle.index, back: backIndex })); } catch (_) {}
  };
  let backIndex = null;
  const setGlassColor = (i, now) => {
    if (i === glassStyle.index) return;
    glassStyle.index = i;
    savePrefs();
    const rgb = hexToRgb(GLASS_COLORS[i].hex);
    const from = { color: glassStyle.color, tint: glassStyle.tint };
    const to = { color: rgb || from.color, tint: rgb ? 1 : 0 };
    Haptics.impact('light');
    physics.pulse(now, 0.18);
    light.change(rgb, now);
    animator.tween({
      duration: 0.22, curve: ease.inOut,
      apply: (u) => {
        glassStyle.color = from.color.map((v, k) => v + (to.color[k] - v) * u);
        glassStyle.tint = from.tint + (to.tint - from.tint) * u;
        controller.needsFrame = true;
      },
    }, now);
    animator.tween({
      duration: 0.55,
      apply: (u) => {
        glassStyle.flash = 0.9 * (u < 0.12 ? u / 0.12 : Math.pow(1 - (u - 0.12) / 0.88, 2));
        controller.needsFrame = true;
      },
    }, now);
  };
  if (prefs && GLASS_COLORS[prefs.color]) {
    const rgb = hexToRgb(GLASS_COLORS[prefs.color].hex);
    glassStyle.index = prefs.color;
    glassStyle.color = rgb || [1, 1, 1];
    glassStyle.tint = rgb ? 1 : 0;
    light.set(rgb);
  }
  const colorSheet = glassColorSheet(screen, { device, current: glassStyle.index, onPick: setGlassColor });
  lightGlass.push(colorSheet.panel);
  // The back: the photo itself by default (one picture, both sides), or a back photo. A side
  // only changes while it faces away, so nothing pops in view: with the front showing, the
  // new back is set at once and the avatar turns over to show it; with the back showing, it
  // turns and the new back is set as it passes edge-on.
  const setBackRowTitle = () => {
    if (backRow?.title) backRow.title.firstChild.textContent = backIndex === null ? 'Add Back Photo' : 'Change Back Photo';
  };
  const applyBack = (i) => {
    if (i === null) {
      physics.setBack(0);
    } else {
      renderer.setFace('back', backImages[i]);
      physics.setBack('back');
    }
    controller.needsFrame = true;
  };
  let pendingBack;   // undefined: nothing waiting; null: none; n: photo n
  physics.onFaceChange = (face) => {
    if (pendingBack !== undefined && Math.abs(face) % 2 === 0) {
      applyBack(pendingBack);
      pendingBack = undefined;
    }
  };
  const chooseBack = (i, now) => {
    if (i === backIndex) return;
    backIndex = i;
    savePrefs();
    setBackRowTitle();
    if (Math.abs(physics.face) % 2 === 0) {
      applyBack(i);
      if (i === null) physics.pulse(now, 0.18);
      else physics.turnBy(1, now);
    } else {
      pendingBack = i;
      physics.turnBy(i === null ? 1 : 2, now);
    }
    controller.needsFrame = true;
  };
  const backSheet = backPhotoSheet(screen, {
    device,
    photos: BACK_PHOTOS.map(photoURL),
    onPick: (cell, now) => {
      // Cell 0 is "None"; the photos follow.
      const choice = cell === 0 ? null : cell - 1;
      animator.after(0.28, (t) => backSheet.dismiss(t), now);
      // As the sheet leaves, the avatar turns over and shows its new back.
      animator.after(0.75, (t) => chooseBack(choice, t), now);
    },
  });
  backSheet.onClose = () => { sheet = null; };
  if (prefs && Number.isInteger(prefs.back) && backImages[prefs.back]) {
    backIndex = prefs.back;
    applyBack(backIndex);
    setBackRowTitle();
  }
  colorSheet.onClose = () => { sheet = null; };

  // ------------------------------------------------------------- input

  // Settings icons that come alive when you return from their page (settings/living-icons.js).
  const living = new LivingIcons({ iconURL });
  setTimeout(() => living.prefetch(ui.rows.map((r) => r.icon).filter((n) => n && n !== 'money')), 1200);

  // Pushed pages (a Settings row's page) over the tab-bar screen.
  const nav = new NavStack({ screen, root: rootView, device, clock });
  // The bars around the page (Safari / Telegram) take the pushed page's top colour.
  nav.onChange = (top) => {
    if (!native) return;
    if (top) {
      const c = top.headerColor || (dark ? '#000000' : '#efeff4');
      document.querySelector('meta[name="theme-color"]')?.setAttribute('content', c);
      setTelegramChrome(tg, { header: c, background: dark ? '#000000' : '#efeff4' });
    } else if (tab === TAB_CHATS) setTopColor('bar');
    else setTopColor(scroll.topState || 'banner');
  };

  // ------------------------------------------------------------- tabs
  // The tab bar works: Chats (the swipe-actions concept) and Settings (the glass avatar).
  // `?tab=chats` opens on Chats.
  const TAB_CHATS = 2;
  const TAB_SETTINGS = 3;
  let tab = params.get('tab') === 'chats' ? TAB_CHATS : TAB_SETTINGS;
  const chatsUI = buildChatsPage(rootView, { device, dark, clock, photoURL });
  const capsule = { x: new SpringValue(ui.tab.itemX(tab), SpringParams.fromResponse(0.38, 0.78)) };
  const setTab = (i, now, animated = true) => {
    if (i !== TAB_CHATS && i !== TAB_SETTINGS) {
      Haptics.tap();
      return;   // Contacts and Calls aren't part of the prototype
    }
    const changed = i !== tab;
    tab = i;
    ui.tab.items.forEach((it, j) => it.classList.toggle('selected', j === i));
    if (animated) capsule.x.animate(ui.tab.itemX(i), now);
    else {
      capsule.x.set(ui.tab.itemX(i), now);
      ui.tab.capsule.style.left = `${ui.tab.itemX(i)}px`;
    }
    chatsUI.page.style.display = i === TAB_CHATS ? '' : 'none';
    if (i === TAB_CHATS) {
      ui.statusBar?.setColor?.(dark ? '#fff' : '#000');
      setTopColor('bar');
    } else {
      scroll.layout(true);
      setTopColor(scroll.topState || 'banner');
    }
    if (changed && animated) Haptics.tap();
  };
  {
    // Tab bar taps never reach the pages under it.
    let down = null;
    const itemAt = (e) => {
      const r = ui.tab.getBoundingClientRect();
      const x = (e.clientX - r.left) * (ui.tab.offsetWidth / r.width);
      return Math.max(0, Math.min(3, Math.floor((x - ui.tab.itemX(0)) / ui.tab.itemW)));
    };
    ui.tab.addEventListener('pointerdown', (e) => { e.stopPropagation(); down = itemAt(e); });
    ui.tab.addEventListener('pointerup', (e) => {
      e.stopPropagation();
      const i = itemAt(e);
      if (down === i) setTab(i, clock.now());
      down = null;
    });
  }

  const router = new InputRouter({
    enabled: () => tab === TAB_SETTINGS && !nav.top,
    screen, device, clock, animator,
    coin: controller,
    coinCenter: () => (scroll.avatarInteractive ? G.avatarCenter : null),
    scroll,
    rows: () => ui.rows,
    onRowTap: (id, now) => {
      if (id === 'backPhoto') { backSheet.select(backIndex === null ? 0 : backIndex + 1); show(backSheet, now); }
      else if (id === 'glassColor') show(colorSheet, now);
      else {
        // Its page slides in; coming back, the row's icon comes alive.
        const row = ui.rows.find((r) => r.id === id);
        const title = row?.title?.firstChild?.textContent || id;
        const page = buildSubPage({ device, title });
        page.onReturning = (t) => { if (row) living.play(row, t); };
        if (row) living.press(row, now);
        animator.after(0.06, (t) => nav.push(page, t), now);
      }
    },
    onAvatarTap: (now) => scroll.expand(now),
    sheet: () => (sheet && sheet.isOpen ? sheet : null),
  });
  // A chat opens its profile (the Gifts tab: the glass gift tiles).
  const openProfile = (chat, now) => {
    if (nav.top) return;
    const page = buildProfilePage({ device, dark, chat, photoURL, tg, scale: renderScale });
    animator.after(0.08, (t) => nav.push(page, t), now);
  };
  chatsUI.chats.onOpen = openProfile;
  if (params.get('open')) {
    const chat = chatsUI.chats.rows.map((r) => r.chat).find((c) => c.id === params.get('open'));
    if (chat) { setTab(TAB_CHATS, clock.now(), false); openProfile(chat, clock.now()); }
  }

  if (!clock.virtual) {
    // A mouse over a pushed page (no button pressed): hover (the gift tiles lean toward it).
    screen.addEventListener('pointermove', (e) => {
      if (e.pointerType !== 'mouse' || e.buttons || !nav.top?.hover) return;
      const r = screen.getBoundingClientRect();
      nav.top.hover([(e.clientX - r.left) * (device.width / r.width), (e.clientY - r.top) * (device.height / r.height)], clock.now());
    });
    screen.addEventListener('pointerleave', () => nav.top?.hover?.(null, clock.now()));
    router.attach();
    attachPointer(screen, { device, clock, target: chatsUI.chats, enabled: () => tab === TAB_CHATS && !nav.top });
    attachPointer(screen, { device, clock, target: nav, enabled: () => !!nav.top });
  }
  setTab(tab, clock.now(), false);

  const demoUpdaters = [];   // extra per-frame work a demo script adds (ctx.addUpdater)
  const render = (now, dtHint, draw = true) => {
    const d = dtHint || now - lastFrameTime;
    frameDt = d > 0 ? Math.max(1 / 240, Math.min(1 / 20, d)) : 1 / 60;
    lastFrameTime = now;
    let busy = animator.update(now);
    for (const s of sheets) busy = s.update(now) || busy;
    busy = scroll.update(now) || busy;
    let drew = false;
    let st = null;
    if (!draw) {
      st = physics.state(now);
    } else if (controller.needsFrame || stage) {
      st = controller.frame(now);
      drew = true;
    }
    if (st) light.setLift(st.glass);
    if (!capsule.x.settled) {
      ui.tab.capsule.style.left = `${capsule.x.update(now).toFixed(2)}px`;
      busy = true;
    }
    if (tab === TAB_CHATS || chatsUI.chats.touch) busy = chatsUI.chats.update(now) || busy;
    busy = living.update(now) || busy;
    for (const f of demoUpdaters) busy = f(now) || busy;
    busy = nav.update(now) || busy;
    busy = light.update(now) || busy;
    if (st || turnLight.active) busy = turnLight.update(st || physics.state(now), now) || busy;
    return { busy, drew };
  };

  const pose = (q) => {
    const st = { yaw: 0, pitch: 0, lift: 1, glass: 1, offsetX: 0, offsetY: 0, sideA: 0, sideB: 0, ...q };
    renderer.render(st, controller.getFrame(st));
    window.__posed = true;
  };

  // Scripted fingers (demo videos) take the same paths as real ones: the tab bar, a pushed
  // page, the chat list or the Settings router (whichever has the screen when they touch).
  let demoTouch = null;
  const tabHit = (p) => {
    const x0 = parseFloat(ui.tab.style.left);
    const y0 = parseFloat(ui.tab.style.top);
    if (p[0] < x0 || p[0] > x0 + ui.tab.offsetWidth || p[1] < y0 || p[1] > y0 + ui.tab.offsetHeight) return null;
    return Math.max(0, Math.min(3, Math.floor((p[0] - x0 - ui.tab.itemX(0)) / ui.tab.itemW)));
  };
  const demoInput = {
    inject(type, p, now) {
      if (type === 'down') {
        const i = nav.top ? null : tabHit(p);
        demoTouch = i != null ? { kind: 'tab', i } : nav.top ? { kind: 'nav' } : tab === TAB_CHATS ? { kind: 'chats' } : { kind: 'settings' };
      }
      const t = demoTouch;
      if (!t) return;
      if (type === 'up') demoTouch = null;
      if (t.kind === 'tab') {
        if (type === 'up' && tabHit(p) === t.i) setTab(t.i, now);
        return;
      }
      if (t.kind === 'nav') nav[type](p, now);
      else if (t.kind === 'chats') chatsUI.chats[type](p, now);
      else router.inject(type, p, now);
    },
  };

  let demo = null;
  if (stage) {
    const which = params.get('demo');
    const ctx = {
      avatar: G.avatarCenter, G, W: G.W, H: device.height, device, ui, stage, clock,
      sheets: { back: backSheet, color: colorSheet }, chats: chatsUI.chats, nav, living, physics, light, turnLight,
      setTab, get tab() { return tab; }, openProfile, scroll, glassStyle, setGlassColor, chooseBack, iconURL, screen,
      addUpdater: (f) => demoUpdaters.push(f),
      // Screen pt of an element's centre (whatever the camera does).
      centerOf: (el) => {
        const r = el.getBoundingClientRect();
        const sr = screen.getBoundingClientRect();
        const k = device.width / sr.width;
        return [(r.left + r.width / 2 - sr.left) * k, (r.top + r.height / 2 - sr.top) * k];
      },
    };
    const script = which && DEMOS[which] ? DEMOS[which](ctx) : glassDemoScript(ctx);
    demo = new Demo({ script, clock, stage, router: demoInput, render });
  }

  window.__tg = {
    clock, controller, physics, renderer, cover, ui, device, coverParams, pose, stage, demo, render,
    router, scroll, light, turnLight, glassStyle, setGlassColor, sheets: { back: backSheet, color: colorSheet },
    chats: chatsUI.chats, chatsUI, setTab, get tab() { return tab; }, living, nav,
  };

  if (clock.virtual) {
    render(clock.now());
    if (stage) stage.apply(0);
  } else {
    // Draw only while something moves: a resting avatar costs no GPU (and no battery on a
    // phone). If the glass can't hold ~40 fps while it moves, it renders at a lower scale.
    let last = clock.now();
    let slowFrames = 0;
    const loop = () => {
      const now = clock.now();
      const dt = now - last;
      last = now;
      if (!window.__posed) {
        const { drew } = render(now, dt);
        if (drew && dt < 0.1) {
          // Fewer motion-blur samples first (only fast spins use them), then fewer pixels.
          slowFrames = dt > 1 / 40 ? slowFrames + 1 : Math.max(0, slowFrames - 1);
          if (slowFrames > 12) {
            slowFrames = 0;
            if (renderer.maxSamples > 3) renderer.maxSamples -= 2;
            else if (coinScale > 1.25) coinScale = Math.max(1.25, coinScale - 0.25);
            console.log(`glass: ${renderer.maxSamples} samples at ${coinScale}x`);
          }
        }
      }
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }
  document.body.dataset.ready = '1';
}

// The layout is built for the viewport it starts with; rotating (or a host resizing the page
// for good) rebuilds it. Small height changes (a host's bars, a sheet dragged and let go) are
// ignored, and never while a finger is down.
function reloadOnResize(touching) {
  const w0 = window.innerWidth;
  const h0 = window.innerHeight;
  let timer = null;
  const check = () => {
    if (Math.abs(window.innerWidth - w0) <= 1 && Math.abs(window.innerHeight - h0) <= 100) return;
    if (touching()) timer = setTimeout(check, 500);
    else location.reload();
  };
  window.addEventListener('resize', () => {
    clearTimeout(timer);
    timer = setTimeout(check, 700);
  });
}

function loadPrefs() {
  try {
    return JSON.parse(localStorage.getItem('glassAvatar') || '{}') || {};
  } catch (_) {
    return {};
  }
}

function coverTopColor(canvas) {
  try {
    const [r, g, b] = canvas.getContext('2d').getImageData(Math.floor(canvas.width / 2), 0, 1, 1).data;
    return `#${[r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('')}`;
  } catch (_) {
    return null;
  }
}

function envColors(palette, dark) {
  const low = palette.main.withMultiplied(1, 1.05, dark ? 0.55 : 0.8);
  const high = palette.secondary.withMultiplied(1, 0.6, 1.45).mixedWith(Color.white(1), 0.38);
  return { low: low.vec3(), high: high.vec3() };
}

main().catch((e) => {
  console.error(e);
  document.body.dataset.error = String((e && e.stack) || e);
});
