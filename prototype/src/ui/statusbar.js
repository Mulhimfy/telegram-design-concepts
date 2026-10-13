// iOS status bar (time, cellular, Wi-Fi, battery), sized for notch / Dynamic Island phones.

export function statusBarSVG({ battery = 1, charging = false, signal = 4, color = '#fff' } = {}) {
  const bars = [0, 1, 2, 3].map((i) => {
    const h = 3.6 + i * 2.2;
    const on = i < signal;
    return `<rect x="${i * 4.6}" y="${11 - h}" width="3.1" height="${h}" rx="0.9" fill="${color}" opacity="${on ? 1 : 0.35}"/>`;
  }).join('');
  const wifi = `<g transform="translate(23.5,0.4)" fill="${color}">
      <path d="M7.67 2.3c2.3 0 4.4.9 5.97 2.38a.36.36 0 0 0 .5-.01l1.13-1.14a.36.36 0 0 0 0-.51A10.86 10.86 0 0 0 7.67 0 10.86 10.86 0 0 0 .07 3.02a.36.36 0 0 0 0 .51l1.13 1.14c.14.14.36.14.5.01A8.6 8.6 0 0 1 7.67 2.3z"/>
      <path d="M7.67 6.04c1.27 0 2.43.47 3.31 1.25.14.12.36.12.5-.02l1.13-1.14a.36.36 0 0 0-.01-.52 7.1 7.1 0 0 0-9.86 0 .36.36 0 0 0-.01.52l1.13 1.14c.14.14.36.14.5.02a5 5 0 0 1 3.31-1.25z"/>
      <path d="M10.04 9.04a.35.35 0 0 0-.01-.52 3.4 3.4 0 0 0-4.72 0 .35.35 0 0 0-.01.52l2.11 2.13c.14.14.37.14.51 0l2.12-2.13z"/>
    </g>`;
  const bw = 24.5;
  const fillW = Math.max(1.5, (bw - 4) * battery);
  const batt = `<g transform="translate(44,0)">
      <rect x="0.5" y="0.5" width="${bw}" height="11.5" rx="3.6" fill="none" stroke="${color}" stroke-opacity="0.35"/>
      <rect x="2.2" y="2.2" width="${fillW}" height="8.1" rx="2.1" fill="${charging ? '#34c759' : color}"/>
      <path d="M${bw + 1.6} 4.2v4.1c.8-.3 1.4-1.1 1.4-2.05 0-.95-.6-1.75-1.4-2.05z" fill="${color}" fill-opacity="0.4"/>
    </g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="73" height="13" viewBox="0 0 73 13">${bars}${wifi}${batt}</svg>`;
}

export function buildStatusBar(parent, device, { time = '9:41', color = '#fff', battery = 1, charging = false } = {}) {
  const el = document.createElement('div');
  if (device.native) {
    // On a real phone the system draws the status bar.
    return { el, time: null };
  }
  el.className = 'statusbar abs';
  el.style.cssText = `left:0;top:0;width:${device.width}px;height:${device.statusBar}px;z-index:40;pointer-events:none;color:${color}`;
  // Time sits centred in the left "ear"; icons in the right one.
  const ear = device.island ? (device.width - 95) / 2 : (device.width - 209) / 2;
  const centerY = device.island ? 32 : 24.5;
  const t = document.createElement('div');
  t.className = 'abs w600';
  t.textContent = time;
  t.style.cssText = `left:${device.island ? 17 : 0}px;width:${ear - (device.island ? 6 : 0)}px;top:${centerY - 11}px;height:22px;text-align:center;font-family:var(--font-text);font-size:17px;letter-spacing:-0.4px;line-height:22px;`;
  el.appendChild(t);
  const icons = document.createElement('div');
  icons.className = 'abs';
  icons.innerHTML = statusBarSVG({ battery, charging, color });
  const iconsW = 73;
  const rightCenter = device.width - ear / 2 + (device.island ? -4 : 2);
  icons.style.cssText = `left:${rightCenter - iconsW / 2}px;top:${centerY - 6.5}px;width:${iconsW}px;height:13px;`;
  el.appendChild(icons);
  parent.appendChild(el);
  let current = color;
  // Light content on the cover, dark over a light navigation bar (light theme, collapsed).
  const setColor = (c) => {
    if (c === current) return;
    current = c;
    el.style.color = c;
    icons.innerHTML = statusBarSVG({ battery, charging, color: c });
  };
  return { el, time: t, setColor };
}
