// DamiMovies account check (Cloudflare Worker + KV).
// POST { mode: "signup" | "login", idToken } -> verifies the Google ID token and
// keeps the list of signed-up Gmail accounts.
//   signup: 200 created, 409 already signed up
//   login : 200 ok,      404 not signed up yet
//
// POST { action: "token_request", idToken, whatsapp, days, price, deviceId }
//   stores the request and sends you a Telegram message with the customer's
//   WhatsApp number so you can send them a token.
//
// Needs: KV namespace bound as USERS, and variable GOOGLE_WEB_CLIENT_ID.
// For notifications: TELEGRAM_BOT_TOKEN (secret) and TELEGRAM_CHAT_ID.

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

async function verifyGoogleToken(idToken, env) {
  const res = await fetch('https://oauth2.googleapis.com/tokeninfo?id_token=' + encodeURIComponent(idToken));
  if (!res.ok) return null;
  const t = await res.json();
  if (t.aud !== env.GOOGLE_WEB_CLIENT_ID) return null;
  if (t.email_verified !== 'true' && t.email_verified !== true) return null;
  if (Number(t.exp) * 1000 < Date.now()) return null;
  const email = String(t.email || '').toLowerCase();
  if (!/@(gmail|googlemail)\.com$/.test(email)) return null;
  return { email, name: t.name || '' };
}

async function notifyAdmin(env, r) {
  if (!env.TELEGRAM_BOT_TOKEN || !env.TELEGRAM_CHAT_ID) return false;
  const text =
    'New DamiMovies token request\n\n' +
    'WhatsApp: +' + r.whatsapp + '\n' +
    'Chat: https://wa.me/' + r.whatsapp + '\n' +
    'Plan: ' + r.days + ' days (' + r.price + ')\n' +
    'Device ID: ' + r.deviceId + '\n' +
    'Gmail: ' + r.email + '\n\n' +
    'Make the token in token-admin.html with this Device ID and days, then send it to the WhatsApp number.';
  try {
    const res = await fetch('https://api.telegram.org/bot' + env.TELEGRAM_BOT_TOKEN + '/sendMessage', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text, disable_web_page_preview: true }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function handleTokenRequest(body, info, env) {
  if (!(await env.USERS.get('user:' + info.email))) return json({ error: 'not_registered' }, 403);
  const whatsapp = String(body.whatsapp || '').replace(/\D/g, '');
  if (whatsapp.length < 8 || whatsapp.length > 15) return json({ error: 'bad_whatsapp' }, 400);
  const days = parseInt(body.days, 10);
  if (!(days >= 1 && days <= 3650)) return json({ error: 'bad_days' }, 400);
  const deviceId = String(body.deviceId || '').toUpperCase();
  if (!/^[A-Z0-9-]{8,20}$/.test(deviceId)) return json({ error: 'bad_device' }, 400);
  const price = String(body.price || '').slice(0, 40);

  // At most 5 requests per Gmail per day.
  const rlKey = 'rl:' + info.email + ':' + new Date().toISOString().slice(0, 10);
  const count = parseInt((await env.USERS.get(rlKey)) || '0', 10);
  if (count >= 5) return json({ error: 'too_many' }, 429);
  await env.USERS.put(rlKey, String(count + 1), { expirationTtl: 172800 });

  const record = { email: info.email, whatsapp, days, price, deviceId, at: Date.now() };
  await env.USERS.put('req:' + record.at + ':' + Math.random().toString(36).slice(2, 8), JSON.stringify(record), {
    expirationTtl: 60 * 60 * 24 * 60,
  });
  const notified = await notifyAdmin(env, record);
  return json({ ok: true, notified });
}

export default {
  async fetch(request, env) {
    if (request.method === 'GET') return json({ ok: true, service: 'damimovies-auth' });
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
    if (!env.USERS || !env.GOOGLE_WEB_CLIENT_ID) return json({ error: 'worker_not_configured' }, 500);

    let body;
    try { body = await request.json(); } catch { return json({ error: 'bad_request' }, 400); }
    const mode = body.mode === 'signup' ? 'signup' : 'login';
    const idToken = String(body.idToken || '');
    if (!idToken) return json({ error: 'missing_token' }, 400);

    const info = await verifyGoogleToken(idToken, env);
    if (!info) return json({ error: 'invalid_token' }, 401);

    if (body.action === 'token_request') return handleTokenRequest(body, info, env);

    const key = 'user:' + info.email;
    const existing = await env.USERS.get(key);
    if (mode === 'signup') {
      if (existing) return json({ error: 'exists' }, 409);
      await env.USERS.put(key, JSON.stringify({ created: Date.now(), name: info.name }));
      return json({ ok: true, status: 'created' });
    }
    if (!existing) return json({ error: 'not_registered' }, 404);
    return json({ ok: true, status: 'ok' });
  },
};
