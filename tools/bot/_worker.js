// @Tgdesignbot on Cloudflare Pages (advanced mode): the static prototype is served from the
// same deploy, and Telegram's webhook lands here, so the bot and the designs keep working
// whether or not any server of ours is up.
//
//   POST /tg/<HOOK_PATH>   Telegram updates (checked against X-Telegram-Bot-Api-Secret-Token)
//   everything else        the prototype (static files)
//
// Secrets (wrangler pages secret put … --project-name tgdesign): BOT_TOKEN, HOOK_PATH,
// WEBHOOK_SECRET. Demo videos are sent by Telegram file id (videos/index.json, tools/bot/upload-videos.py);
// the mp4s are also served from /videos/ as a fallback link.

const DESIGNS = [
  {
    key: 'glass', emoji: '🪟', title: 'Glass Avatar', query: '',
    how: 'Settings → touch your photo: it turns to glass. Drag it any way, past edge-on it turns over, a flick spins it. Let go and it goes straight back to normal, so it stays minimal and never gets in the way. <b>Change Glass Color</b>: its light runs across the profile and over your name as the photo turns.',
  },
  {
    key: 'back', emoji: '🔄', title: 'Back Photo', query: '?design=back',
    how: 'Surprise your followers with a hidden photo, shown only when your profile photo is turned over. Settings → <b>Add Back Photo</b>, pick one: your photo turns over by itself to show it. Drag the photo to turn it between both sides.',
  },
  {
    key: 'icons', emoji: '⚙️', title: 'Living Icons', query: '?design=icons',
    how: 'Settings → open any row and come back: its icon comes alive, every part of it moves (the lock opens and slams shut, the bell rings, the bolt cracks…).',
  },
  {
    key: 'swipe', emoji: '💬', title: 'Depth Swipe', query: '?tab=chats',
    how: 'Chats → swipe a chat right or left: the name, message and photo move in 3D. Pulling right, the letters roll back in a wave as you pull; to the left the photo rolls over the screen’s edge and every letter flips over it. Swipe all the way for the spin.',
  },
  {
    key: 'gifts', emoji: '🎁', title: 'Glass Gifts', query: '?tab=chats&open=alex',
    how: 'A profile’s Gifts → touch a gift: the glass leans and lights up. Hold and slide across the gifts, tilt your phone. (A tap still opens the gift’s info, as today.)',
  },
];

const INTRO = '<b>Telegram design concepts</b>\nFive ideas for Telegram iOS, running in a replica of the app. Each one below comes as two videos: Telegram today (before), then the design (after). Tap <b>Try</b> under it to test it yourself.';
const MENU = '<b>Telegram design concepts</b>\nFive ideas for Telegram iOS, running in a replica of the app. Tap one to try it; /start shows each one before and after.';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function appUrl(origin, d) {
  return `${origin}/${d.query}`;
}

// A design's open button. Web App buttons only work in private chats; elsewhere the designs open in
// the browser.
function openButton(origin, d, privateChat, text) {
  return privateChat ? { text, web_app: { url: appUrl(origin, d) } } : { text, url: appUrl(origin, d) };
}

// Inline keyboard without videos: one row per design.
function keyboard(origin, designs, privateChat) {
  return { inline_keyboard: designs.map((d) => [openButton(origin, d, privateChat, `${d.emoji} ${d.title}`)]) };
}

function designText(list) {
  return list.map((d) => `${d.emoji} <b>${esc(d.title)}</b>\n${d.how}`).join('\n\n');
}

async function api(env, method, body) {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    const json = await r.json().catch(() => ({ ok: false }));
    // /start sends eleven messages in a row; if Telegram asks to slow down, wait and send again.
    const wait = json.parameters && json.parameters.retry_after;
    if (json.error_code !== 429 || !wait || wait > 10 || attempt >= 2) return json;
    await new Promise((resolve) => setTimeout(resolve, wait * 1000));
  }
}

async function hasVideos(env, origin) {
  // The videos ship with the deploy (videos/index.json lists them).
  try {
    const r = await env.ASSETS.fetch(new Request(`${origin}/videos/index.json`));
    if (!r.ok) return null;
    return await r.json();
  } catch (_) {
    return null;
  }
}

// /start: the intro, then every design as its two videos (before, then after with its Try button).
// Without videos (none in the deploy, or any other text): one message with the descriptions and a button per design.
async function sendDesigns(env, origin, chat, designs, videos) {
  if (!videos) {
    const text = designs.length === 1 ? designText(designs) : `${MENU}\n\n${designText(designs)}`;
    await api(env, 'sendMessage', {
      chat_id: chat.id,
      text,
      parse_mode: 'HTML',
      link_preview_options: { is_disabled: true },
      reply_markup: keyboard(origin, designs, chat.type === 'private'),
    });
    return;
  }
  if (designs.length > 1) await api(env, 'sendMessage', { chat_id: chat.id, text: INTRO, parse_mode: 'HTML' });
  for (const d of designs) await sendVideo(env, origin, chat, d, videos);
}

// The design's videos, by Telegram file id (tools/bot/upload-videos.py): before (Telegram today), then
// after, captioned with how to try it and carrying the Try button.
async function sendVideo(env, origin, chat, d, videos) {
  const pair = (videos && videos[d.key]) || {};
  const button = { inline_keyboard: [[openButton(origin, d, chat.type === 'private', `${d.emoji} Try ${d.title}`)]] };
  const captions = {
    before: `${d.emoji} <b>${esc(d.title)} — Before</b>\nTelegram today`,
    after: `${d.emoji} <b>${esc(d.title)} — After</b>\n${d.how}`,
  };
  for (const which of ['before', 'after']) {
    const v = pair[which];
    const extra = which === 'after' ? { reply_markup: button } : {};
    const r = v ? await api(env, 'sendVideo', {
      chat_id: chat.id,
      video: v.file_id,
      width: v.width, height: v.height, duration: v.duration,
      supports_streaming: true,
      caption: captions[which],
      parse_mode: 'HTML',
      ...extra,
    }) : { ok: false };
    if (r.ok) continue;
    // The video couldn't be sent: its link instead (and the after text keeps the Try button).
    const link = v && v.file ? `\n${origin}/videos/${v.file}` : '';
    if (which === 'after' || link) {
      await api(env, 'sendMessage', {
        chat_id: chat.id, text: captions[which] + link, parse_mode: 'HTML', link_preview_options: { is_disabled: true }, ...extra,
      });
    }
  }
}

async function onUpdate(env, origin, u) {
  const videos = await hasVideos(env, origin);
  if (u.message) {
    const m = u.message;
    const [cmd = '', arg = ''] = (m.text || '').trim().split(/\s+/, 2);
    const command = cmd.replace(/@\w+$/, '').toLowerCase();
    if (m.chat.type !== 'private' && !command.startsWith('/')) return;   // groups: commands only
    // /start, /videos: every design's videos; /start <design> (t.me/Tgdesignbot?start=swipe), /<design>: that
    // one's; anything else: the menu.
    const one = DESIGNS.find((d) => d.key === arg.toLowerCase() || `/${d.key}` === command);
    const full = one || command === '/start' || command === '/videos';
    await sendDesigns(env, origin, m.chat, one ? [one] : DESIGNS, full ? videos : null);
    return;
  }
  if (u.callback_query) {
    const q = u.callback_query;
    const [kind, key] = String(q.data || '').split(':');
    const d = DESIGNS.find((x) => x.key === key);
    await api(env, 'answerCallbackQuery', { callback_query_id: q.id });
    if (kind === 'video' && d && q.message) await sendVideo(env, origin, q.message.chat, d, videos);
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (env.HOOK_PATH && url.pathname === `/tg/${env.HOOK_PATH}`) {
      if (request.method !== 'POST') return new Response('ok');
      if (env.WEBHOOK_SECRET && request.headers.get('x-telegram-bot-api-secret-token') !== env.WEBHOOK_SECRET) {
        return new Response('forbidden', { status: 403 });
      }
      let update;
      try { update = await request.json(); } catch (_) { return new Response('bad request', { status: 400 }); }
      // Answer Telegram at once; the replies go out in the background.
      ctx.waitUntil(onUpdate(env, url.origin, update).catch(() => {}));
      return new Response('ok');
    }
    // Field diagnostics from the prototype (prototype/src/core/diag.js): printed for `wrangler pages
    // deployment tail`, nothing stored.
    if (url.pathname === '/log' && request.method === 'POST') {
      const text = (await request.text()).slice(0, 8000);
      console.log(`diag ${text}`);
      return new Response(null, { status: 204 });
    }
    return env.ASSETS.fetch(request);
  },
};
