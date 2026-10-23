// DamiMovies authentication (Cloudflare Worker + D1).
// Primary account / token-request / signing-key storage: D1 binding DB.
// Legacy accounts and original Ed25519 signing key are READ from KV USERS
// during migration. This Worker never writes to KV.
// POST { mode: "signup" | "login", idToken } -> verifies the Google ID token and
// keeps the list of signed-up Gmail accounts.
//   signup: 200 created, 409 already signed up
//   login : 200 ok,      404 not signed up yet
//
// POST { action: "token_request", idToken, whatsapp, days, price, deviceId }
//   stores the request and sends you a Telegram message with the customer's
//   WhatsApp number so you can send them a token.
//
// Needs: D1 database bound as DB; original KV namespace bound as USERS
// (read-only for legacy migration); GOOGLE_WEB_CLIENT_ID; ADMIN_SECRET.
// Run cloudflare/auth-d1-schema.sql on the SAME D1 as your community app
// BEFORE deploying. Keep the existing USERS KV binding until migrated.
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

// Read a legacy account without modifying the old KV namespace.
// A missing KV binding is treated as a configuration error during migration:
// otherwise existing customers could accidentally be treated as new users.
async function legacyAccount(env, email) {
  if (!env.USERS) throw new Error('legacy_kv_binding_missing');
  const raw = await env.USERS.get('user:' + email);
  if (!raw) return null;
  try {
    const old = JSON.parse(raw);
    return {
      name: String(old.name || '').slice(0, 150),
      created: Number.isFinite(Number(old.created)) && Number(old.created) > 0
        ? Math.trunc(Number(old.created)) : Date.now(),
    };
  } catch {
    return { name: '', created: Date.now() };
  }
}

async function findAccount(env, info) {
  const found = await env.DB.prepare('SELECT email FROM auth_users WHERE email = ?')
    .bind(info.email).first();
  if (found) return true;
  const legacy = await legacyAccount(env, info.email);
  if (!legacy) return false;
  // Gradually copy existing signups to D1 at their next login.
  await env.DB.prepare(
    'INSERT OR IGNORE INTO auth_users (email, name, created_ms) VALUES (?, ?, ?)'
  ).bind(info.email, legacy.name || info.name, legacy.created).run();
  return true;
}

// A single conditional INSERT enforces the five-requests-per-Gmail daily
// limit even under concurrent requests, without a separate KV counter.
async function handleTokenRequest(body, info, env) {
  if (!(await findAccount(env, info))) return json({ error: 'not_registered' }, 403);
  const whatsapp = String(body.whatsapp || '').replace(/\D/g, '');
  if (whatsapp.length < 8 || whatsapp.length > 15) return json({ error: 'bad_whatsapp' }, 400);
  const days = parseInt(body.days, 10);
  if (!(days >= 1 && days <= 3650)) return json({ error: 'bad_days' }, 400);
  const deviceId = await accountId(info.email); // Verified Gmail, never client-supplied.
  const price = String(body.price || '').slice(0, 40);
  const at = Date.now();
  const day = new Date(at).toISOString().slice(0, 10);
  const nonce = [...crypto.getRandomValues(new Uint8Array(16))]
    .map((n) => n.toString(16).padStart(2, '0')).join('');
  const record = { email: info.email, whatsapp, days, price, deviceId, at };
  // Respect rate-limit usage made earlier today by the old KV-based Worker.
  // This is a KV READ only; there are no KV writes after migration.
  const legacyUses = Number.parseInt(
    (await env.USERS.get('rl:' + info.email + ':' + day)) || '0', 10);
  const allowance = Math.max(0, 5 - (Number.isFinite(legacyUses) ? legacyUses : 0));
  if (allowance === 0) return json({ error: 'too_many' }, 429);

  const result = await env.DB.prepare(`
    INSERT INTO auth_token_requests
      (id, email, whatsapp, days, price, device_id, created_ms, day_utc)
    SELECT ?, ?, ?, ?, ?, ?, ?, ?
    WHERE (SELECT COUNT(*) FROM auth_token_requests
           WHERE email = ? AND day_utc = ?) < ?
  `).bind(nonce, info.email, whatsapp, days, price, deviceId, at, day,
          info.email, day, allowance).run();
  if (!result.meta || result.meta.changes !== 1) return json({ error: 'too_many' }, 429);

  const notified = await notifyAdmin(env, record);
  return json({ ok: true, notified });
}

// ---------------------------------------------------------------- admin (tokens)
// Tokens are signed HERE, so tool/token-admin.html is no longer needed.
// The ORIGINAL Ed25519 signing key is copied once from KV to D1.
// Never replace an existing key: installed APKs verify tokens with its public key.
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
  let row = await env.DB.prepare(
    "SELECT pub, priv FROM auth_signing_keys WHERE name = 'main'"
  ).first();
  if (!row) {
    // Preserve the exact key that signed existing Remove Ads tokens.
    // READ ONLY: there must be no env.USERS.put call anywhere in this Worker.
    const saved = env.USERS ? await env.USERS.get('signing:key') : null;
    if (saved) {
      const legacy = JSON.parse(saved);
      if (!legacy.pub || !legacy.priv) throw new Error('invalid_legacy_signing_key');
      await env.DB.prepare(
        "INSERT OR IGNORE INTO auth_signing_keys (name, pub, priv, created_ms) VALUES ('main', ?, ?, ?)"
      ).bind(legacy.pub, legacy.priv, Date.now()).run();
    } else if (env.ALLOW_NEW_SIGNING_KEY === 'yes') {
      // For a completely new install ONLY. Never set this on an existing
      // DamiMovies deployment unless you intend to rotate every app key.
      const pair = await crypto.subtle.generateKey(
        { name: 'Ed25519' }, true, ['sign', 'verify']);
      const pub = b64u(await crypto.subtle.exportKey('raw', pair.publicKey));
      const priv = b64u(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
      await env.DB.prepare(
        "INSERT OR IGNORE INTO auth_signing_keys (name, pub, priv, created_ms) VALUES ('main', ?, ?, ?)"
      ).bind(pub, priv, Date.now()).run();
    } else {
      // Fail safely instead of generating a key that would invalidate all
      // existing ad-free tokens.
      throw new Error('signing_key_missing');
    }
    row = await env.DB.prepare(
      "SELECT pub, priv FROM auth_signing_keys WHERE name = 'main'"
    ).first();
  }
  if (!row) throw new Error('signing_key_unavailable');
  return {
    pub: row.pub,
    priv: await crypto.subtle.importKey('pkcs8', unb64u(row.priv),
      { name: 'Ed25519' }, false, ['sign']),
  };
}

// Pull legacy users from KV in small admin-authorized batches. Reruns are
// idempotent: imported users are not overwritten and KV is never modified.
async function migrateLegacyUsers(env, cursor) {
  if (!env.USERS) return { error: 'legacy_kv_binding_missing' };
  const options = { prefix: 'user:', limit: 20 }; // Respect Workers Free subrequest limits.
  if (cursor) options.cursor = cursor;
  const page = await env.USERS.list(options);
  const statements = [];
  let skipped = 0;
  for (const key of page.keys) {
    const email = key.name.slice(5).toLowerCase();
    if (!/^[^\s@]+@(gmail|googlemail)\.com$/.test(email)) { skipped++; continue; }
    const legacy = await legacyAccount(env, email);
    if (!legacy) { skipped++; continue; }
    statements.push(env.DB.prepare(
      'INSERT OR IGNORE INTO auth_users (email, name, created_ms) VALUES (?, ?, ?)'
    ).bind(email, legacy.name, legacy.created));
  }
  const results = statements.length ? await env.DB.batch(statements) : [];
  const added = results.reduce((n, r) => n + (r.meta?.changes || 0), 0);
  return {
    ok: true, scanned: page.keys.length, added,
    skipped, complete: !!page.list_complete,
    cursor: page.list_complete ? null : page.cursor,
  };
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
    return new Response(ADMIN_PAGE, { headers: {
      'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store',
      'x-frame-options': 'DENY', 'referrer-policy': 'no-referrer',
    } });
  }
  if (!env.DB || !env.USERS) return json({ error: 'worker_not_configured' }, 503);
  if (!env.ADMIN_SECRET) return json({ error: 'admin_secret_not_set' }, 503);
  if (!isAdmin(request, env)) return json({ error: 'unauthorized' }, 401);

  if (path === '/admin/info' && request.method === 'GET') {
    let publicKey = '';
    let signingKeyError = null;
    try { publicKey = (await signingKeys(env)).pub; }
    catch (e) { signingKeyError = e.message || 'signing_key_unavailable'; }

    const d1 = await env.DB.prepare(`
      SELECT email, whatsapp, days, price, device_id, created_ms
      FROM auth_token_requests ORDER BY created_ms DESC LIMIT 40
    `).all();
    const requests = (d1.results || []).map((r) => ({
      email: r.email, whatsapp: r.whatsapp, days: r.days,
      price: r.price, deviceId: r.device_id, at: r.created_ms,
    }));
    // Show old KV requests as well while you migrate; never write to KV.
    try {
      const list = await env.USERS.list({ prefix: 'req:', limit: 1000 });
      for (const k of list.keys.slice(-25)) {
        const raw = await env.USERS.get(k.name);
        if (raw) requests.push(JSON.parse(raw));
      }
    } catch (_) { /* Admin can still see all new D1 requests. */ }
    requests.sort((a, b) => b.at - a.at);
    const count = await env.DB.prepare('SELECT COUNT(*) AS total FROM auth_users').first();
    return json({ publicKey, signingKeyError, registeredUsers: count.total,
      requests: requests.slice(0, 40) });
  }
  if (path === '/admin/migrate-users' && request.method === 'POST') {
    let body;
    try { body = await request.json(); }
    catch { return json({ error: 'bad_request' }, 400); }
    const cursor = body.cursor == null ? '' : String(body.cursor);
    if (cursor.length > 512) return json({ error: 'bad_cursor' }, 400);
    return json(await migrateLegacyUsers(env, cursor));
  }
  if (path === '/admin/token' && request.method === 'POST') {
    let body;
    try { body = await request.json(); }
    catch { return json({ error: 'bad_request' }, 400); }
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
<p id="keywarning" class="warn"></p>
<h2>Registered users in D1: <span id="usercount">0</span></h2>
<button class="alt" id="migrate">Copy existing KV accounts into D1</button>
<p class="note" id="migration">This copies old Gmail registrations in batches without deleting or writing to KV.</p>
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
 const d=await api('/admin/info');$('pub').value=d.publicKey;$('keywarning').textContent=d.signingKeyError?'Signing key: '+d.signingKeyError:'';$('usercount').textContent=d.registeredUsers;$('main').style.display='block';
 const box=$('reqs');box.textContent='';if(!d.requests.length)box.textContent='No requests yet.';
 for(const r of d.requests){const div=document.createElement('div');div.className='req';
  div.append('+'+r.whatsapp+' \\u00b7 '+r.days+' days \\u00b7 '+r.price+' \\u00b7 '+new Date(r.at).toLocaleString());
  div.append(document.createElement('br'));div.append('Device '+r.deviceId+' \\u00b7 '+r.email);div.append(document.createElement('br'));
  const b=document.createElement('button');b.className='alt';b.textContent='Use this';b.onclick=()=>show(r);div.append(b);box.append(div);}
}
$('go').onclick=async()=>{$('err').textContent='';pw=$('pw').value;try{await load();$('pw').style.display=$('go').style.display='none';}catch(e){$('err').textContent=e.message==='unauthorized'?'Wrong password.':'Error: '+e.message;}};
$('migrate').onclick=async()=>{
 $('migrate').disabled=true;let cursor='',seen=0,added=0;
 try{
  for(let round=0;round<1000;round++){
   const d=await api('/admin/migrate-users',{method:'POST',body:JSON.stringify({cursor})});
   if(!d.ok)throw new Error(d.error||'migration_failed');
   seen+=d.scanned;added+=d.added;
   $('migration').textContent='Scanned '+seen+' legacy entries; copied '+added+' new accounts to D1.';
   if(d.complete){$('migration').textContent+=' Finished.';break;}
   if(!d.cursor)throw new Error('missing_migration_cursor');
   cursor=d.cursor;
  }
  const stat=await api('/admin/info');$('usercount').textContent=stat.registeredUsers;
 }catch(e){$('migration').textContent+=' Stopped: '+e.message+'. Safe to retry.';}
 finally{$('migrate').disabled=false;}
};
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
    try {
      const path = new URL(request.url).pathname.replace(/\/+$/, '') || '/';
      if (path === '/admin' || path.startsWith('/admin/'))
        return await handleAdmin(request, env, path);
      if (path === '/health' && request.method === 'GET')
        return json({ ok: true, service: 'damimovies-auth', db: !!env.DB,
          legacyKv: !!env.USERS });
      if (request.method === 'GET') return json({ ok: true, service: 'damimovies-auth' });
      if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
      if (!env.DB || !env.USERS || !env.GOOGLE_WEB_CLIENT_ID)
        return json({ error: 'worker_not_configured' }, 503);

      let body;
      try { body = await request.json(); }
      catch { return json({ error: 'bad_request' }, 400); }
      const mode = body.mode === 'signup' ? 'signup' : 'login';
      const idToken = String(body.idToken || '');
      if (!idToken) return json({ error: 'missing_token' }, 400);
      const info = await verifyGoogleToken(idToken, env);
      if (!info) return json({ error: 'invalid_token' }, 401);
      if (body.action === 'token_request') return handleTokenRequest(body, info, env);

      // Check D1 first; on a miss, recognize and migrate a legacy KV account.
      const existing = await findAccount(env, info);
      if (mode === 'signup') {
        if (existing) return json({ error: 'exists' }, 409);
        const result = await env.DB.prepare(
          'INSERT OR IGNORE INTO auth_users (email, name, created_ms) VALUES (?, ?, ?)'
        ).bind(info.email, String(info.name).slice(0, 150), Date.now()).run();
        return result.meta?.changes === 1
          ? json({ ok: true, status: 'created' })
          : json({ error: 'exists' }, 409);
      }
      if (!existing) return json({ error: 'not_registered' }, 404);
      return json({ ok: true, status: 'ok' });
    } catch (error) {
      // Error details go only to Cloudflare Worker logs, never to users.
      console.error('auth_worker_error', error);
      return json({ error: 'service_unavailable' }, 503);
    }
  },
};
