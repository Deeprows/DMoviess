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
// Needs: KV namespace bound as USERS, variable GOOGLE_WEB_CLIENT_ID and
// secret ADMIN_SECRET (password for the /admin token page).
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
    'Open the /admin page of your auth worker, make the token for this Device ID and days, then send it to the WhatsApp number.';
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

// Static Device ID for a Gmail address. MUST match PremiumService in the app.
async function accountId(email) {
  let e = String(email || '').trim().toLowerCase();
  if (e.endsWith('@googlemail.com')) e = e.slice(0, -15) + '@gmail.com';
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('damimovies|acct|' + e)));
  const hex = [...h.slice(0, 6)].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
  return hex.slice(0, 4) + '-' + hex.slice(4, 8) + '-' + hex.slice(8, 12);
}

async function handleTokenRequest(body, info, env) {
  if (!(await env.USERS.get('user:' + info.email))) return json({ error: 'not_registered' }, 403);
  const whatsapp = String(body.whatsapp || '').replace(/\D/g, '');
  if (whatsapp.length < 8 || whatsapp.length > 15) return json({ error: 'bad_whatsapp' }, 400);
  const days = parseInt(body.days, 10);
  if (!(days >= 1 && days <= 3650)) return json({ error: 'bad_days' }, 400);
  // The ID is made here from the verified Gmail, so it cannot be spoofed by the client.
  const deviceId = await accountId(info.email);
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


// ---------------------------------------------------------------- admin (tokens)
// Tokens are signed HERE, so tool/token-admin.html is no longer needed.
// The Ed25519 signing key is created on first use and kept in KV (signing:key).
// Needs the secret ADMIN_SECRET (a long password only you know).
// Open  https://<your-worker>/admin  to make tokens and see requests.

const b64u = (buf) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
};

async function signingKeys(env) {
  const saved = await env.USERS.get('signing:key');
  if (saved) {
    const k = JSON.parse(saved);
    return { pub: k.pub, priv: await crypto.subtle.importKey('pkcs8', unb64u(k.priv), { name: 'Ed25519' }, false, ['sign']) };
  }
  const pair = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const pub = b64u(await crypto.subtle.exportKey('raw', pair.publicKey));
  const priv = b64u(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  await env.USERS.put('signing:key', JSON.stringify({ pub, priv }));
  return signingKeys(env);
}

async function makeToken(env, deviceId, days) {
  const { priv } = await signingKeys(env);
  const nonce = [...crypto.getRandomValues(new Uint8Array(8))].map((b) => b.toString(16).padStart(2, '0')).join('');
  const payload = new TextEncoder().encode('v1|' + deviceId + '|' + days + '|' + nonce);
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, priv, payload);
  return b64u(payload) + '.' + b64u(sig);
}

function isAdmin(request, env) {
  const given = (request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  const want = env.ADMIN_SECRET || '';
  if (want.length < 8 || given.length !== want.length) return false;
  let diff = 0;
  for (let i = 0; i < want.length; i++) diff |= given.charCodeAt(i) ^ want.charCodeAt(i);
  return diff === 0;
}

async function handleAdmin(request, env, path) {
  if (path === '/admin' && request.method === 'GET') {
    return new Response(ADMIN_PAGE, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
  }
  if (!env.USERS) return json({ error: 'worker_not_configured' }, 500);
  if (!env.ADMIN_SECRET) return json({ error: 'admin_secret_not_set' }, 500);
  if (!isAdmin(request, env)) return json({ error: 'unauthorized' }, 401);

  if (path === '/admin/info' && request.method === 'GET') {
    const { pub } = await signingKeys(env);
    const list = await env.USERS.list({ prefix: 'req:' });
    const requests = [];
    for (const k of list.keys.slice(-40)) {
      const v = await env.USERS.get(k.name);
      if (v) requests.push(JSON.parse(v));
    }
    requests.sort((a, b) => b.at - a.at);
    return json({ publicKey: pub, requests });
  }
  if (path === '/admin/token' && request.method === 'POST') {
    let body;
    try { body = await request.json(); } catch { return json({ error: 'bad_request' }, 400); }
    const deviceId = String(body.deviceId || '').trim().toUpperCase();
    if (!/^[A-Z0-9-]{8,20}$/.test(deviceId)) return json({ error: 'bad_device' }, 400);
    const days = parseInt(body.days, 10);
    if (!(days >= 1 && days <= 3650)) return json({ error: 'bad_days' }, 400);
    return json({ ok: true, token: await makeToken(env, deviceId, days) });
  }
  return json({ error: 'not_found' }, 404);
}

const ADMIN_PAGE = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>DamiMovies token admin</title>
<style>
body{font-family:system-ui,sans-serif;background:#0d0b14;color:#eee;margin:0;padding:18px;max-width:640px;margin:auto}
h1{font-size:20px}h2{font-size:16px;margin-top:26px}
input,textarea{width:100%;box-sizing:border-box;background:#1b1727;color:#fff;border:1px solid #3a3350;border-radius:10px;padding:10px;font-size:14px;margin:6px 0}
button{background:#9b5cff;color:#fff;border:0;border-radius:10px;padding:11px 15px;font-size:14px;font-weight:700;margin:6px 6px 6px 0}
button.alt{background:#2a2540}a.btn{display:inline-block;background:#1faf5a;color:#fff;text-decoration:none;border-radius:10px;padding:11px 15px;font-weight:700}
.note{color:#9a94ad;font-size:12px;line-height:1.5}.warn{color:#ffb36b}.req{border:1px solid #3a3350;border-radius:10px;padding:10px;margin:8px 0;font-size:13px}
code{word-break:break-all}
</style></head><body>
<h1>DamiMovies token admin</h1>
<input id="pw" type="password" placeholder="Admin password (ADMIN_SECRET)">
<button id="go">Unlock</button><p id="err" class="warn"></p>
<div id="main" style="display:none">
<h2>App public key</h2>
<p class="note">Paste into assets/data/app_config.json &rarr; removeAds.publicKey (one time).</p>
<textarea id="pub" rows="2" readonly></textarea>
<h2>Make a token</h2>
<input id="dev" placeholder="Device ID  XXXX-XXXX-XXXX" autocapitalize="characters">
<input id="days" type="number" min="1" max="3650" value="30">
<button id="mk">Make token</button>
<div id="res" style="display:none"><textarea id="tok" rows="5" readonly></textarea>
<button class="alt" id="copy">Copy</button> <a class="btn" id="wa" target="_blank" rel="noopener">Send on WhatsApp</a></div>
<h2>Token requests</h2><div id="reqs" class="note">Loading...</div>
</div>
<script>
const $=id=>document.getElementById(id);let pw='';
const api=async(path,opt={})=>{const r=await fetch(path,{...opt,headers:{authorization:'Bearer '+pw,'content-type':'application/json'}});const d=await r.json().catch(()=>({}));if(!r.ok)throw new Error(d.error||r.status);return d;};
function show(r){$('dev').value=r.deviceId;$('days').value=r.days;$('dev').dataset.wa=r.whatsapp;window.scrollTo(0,0);}
async function load(){
 const d=await api('/admin/info');$('pub').value=d.publicKey;$('main').style.display='block';
 const box=$('reqs');box.textContent='';if(!d.requests.length)box.textContent='No requests yet.';
 for(const r of d.requests){const div=document.createElement('div');div.className='req';
  div.append('+'+r.whatsapp+' \\u00b7 '+r.days+' days \\u00b7 '+r.price+' \\u00b7 '+new Date(r.at).toLocaleString());
  div.append(document.createElement('br'));div.append('Device '+r.deviceId+' \\u00b7 '+r.email);div.append(document.createElement('br'));
  const b=document.createElement('button');b.className='alt';b.textContent='Use this';b.onclick=()=>show(r);div.append(b);box.append(div);}
}
$('go').onclick=async()=>{$('err').textContent='';pw=$('pw').value;try{await load();$('pw').style.display=$('go').style.display='none';}catch(e){$('err').textContent=e.message==='unauthorized'?'Wrong password.':'Error: '+e.message;}};
$('mk').onclick=async()=>{$('err').textContent='';try{
 const d=await api('/admin/token',{method:'POST',body:JSON.stringify({deviceId:$('dev').value,days:$('days').value})});
 $('tok').value=d.token;$('res').style.display='block';
 const num=($('dev').dataset.wa||'');
 $('wa').href='https://wa.me/'+num+'?text='+encodeURIComponent('Your DamiMovies ad-free token ('+$('days').value+' days):\\n\\n'+d.token);
}catch(e){$('err').textContent='Could not make token: '+e.message;}};
$('copy').onclick=async()=>{try{await navigator.clipboard.writeText($('tok').value);$('copy').textContent='Copied';}catch(e){$('tok').select();}};
</script></body></html>`;

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname.replace(/\/+$/, '') || '/';
    if (path === '/admin' || path.startsWith('/admin/')) return handleAdmin(request, env, path);
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
