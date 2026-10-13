// Small vector assets that are custom emoji / stickers in the real app.

// Background-emoji pattern glyph seen on the user's profile (a perched crow).
export const crowSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path fill="#fff" fill-rule="evenodd" d="M52.8 14.2 C46 11.5 38 9 31 8.5 C27 3.5 15 2.5 9.5 9.5 C6 14.5 6 22 8 28 C9.5 36 10.5 44 13 50 L16 55.5 L26 55.5 L27.5 52 C38 56 50 60 62 63 C56 50 50 38 41 29 C38 26 35.5 24.5 33 23.5 C39 20 46 17.5 52.8 14.2 Z M21 12.2 a1.9 1.9 0 1 0 0.01 0 Z M13.5 57.2 h19 v3 h-19 Z"/></svg>`;

// Cat-head pattern from the designer video's purple profile.
export const catSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path fill="#fff" d="M10 8 L24 20 C29 18.5 35 18.5 40 20 L54 8 L56 30 C59 36 58 44 53 50 C47 56 39 58 32 58 C25 58 17 56 11 50 C6 44 5 36 8 30 Z"/></svg>`;

// Camera pattern for the photographer persona of the contact demo.
export const cameraSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path fill="#fff" fill-rule="evenodd" d="M22 12 h20 l4 7 h8 a6 6 0 0 1 6 6 v24 a6 6 0 0 1 -6 6 H10 a6 6 0 0 1 -6 -6 V25 a6 6 0 0 1 6 -6 h8 z M32 25 a12 12 0 1 0 0.01 0 z M32 30 a7 7 0 1 1 -0.01 0 z M49 24 h4 v4 h-4 z"/></svg>`;

// Pixel-art "GG" emoji status from user-01.jpg.
export function ggStatusSVG() {
  const G = [
    '.###.',
    '#...#',
    '#....',
    '#.###',
    '#...#',
    '#...#',
    '.###.',
  ];
  const px = 3.4;
  let rects = '';
  let outline = '';
  for (let letter = 0; letter < 2; letter++) {
    const ox = 1.5 + letter * 6 * px;
    G.forEach((row, y) => {
      [...row].forEach((c, x) => {
        if (c !== '#') return;
        const X = ox + x * px;
        const Y = 1.5 + y * px;
        outline += `<rect x="${(X - 1).toFixed(2)}" y="${(Y - 1).toFixed(2)}" width="${(px + 2).toFixed(2)}" height="${(px + 2).toFixed(2)}"/>`;
        rects += `<rect x="${X.toFixed(2)}" y="${Y.toFixed(2)}" width="${px.toFixed(2)}" height="${px.toFixed(2)}"/>`;
      });
    });
  }
  const w = 3 + 11 * px;
  const h = 3 + 7 * px;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w.toFixed(1)} ${h.toFixed(1)}">
<defs><linearGradient id="gg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff07a"/><stop offset="0.45" stop-color="#ffc62e"/><stop offset="1" stop-color="#f08a12"/></linearGradient></defs>
<g fill="#6b3d00">${outline}</g><g fill="url(#gg)">${rects}</g></svg>`;
}

export function svgDataURL(svg) {
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.decoding = 'async';
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}
