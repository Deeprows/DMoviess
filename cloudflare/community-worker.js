// DamiMovies Community — Cloudflare Worker + D1
// Posts, comments, likes, profiles, private Watch Together
// and public Watch Now rooms.

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
      'cache-control': 'no-store',
    },
  });

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

const fail = (status, code) => {
  throw new HttpError(status, code);
};

const nowSec = () => Math.floor(Date.now() / 1000);
const DAY = 86400;

async function sha256(text) {
  const buf = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(text)
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function newId() {
  const b = crypto.getRandomValues(new Uint8Array(9));
  return [...b]
    .map((x) => x.toString(16).padStart(2, '0'))
    .join('');
}

function decode(v) {
  try {
    return decodeURIComponent(v || '');
  } catch {
    return '';
  }
}

const clean = (v, max) =>
  String(v ?? '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .trim()
    .slice(0, max);

// ---------------- AUTHENTICATION ----------------

async function verifyGoogleToken(idToken, env) {
  try {
    const res = await fetch(
      'https://oauth2.googleapis.com/tokeninfo?id_token=' +
      encodeURIComponent(idToken)
    );
    if (!res.ok) return null;

    const t = await res.json();
    if (t.aud !== env.GOOGLE_WEB_CLIENT_ID) return null;
    if (t.email_verified !== 'true' &&
        t.email_verified !== true) return null;
    if (Number(t.exp) * 1000 < Date.now()) return null;

    return String(t.email || '').toLowerCase();
  } catch {
    return null;
  }
}

async function authenticate(request, env) {
  const h = (n) => request.headers.get(n) || '';
  const email = h('x-community-email').trim().toLowerCase();

  if (!/^[a-z0-9._%+-]+@(gmail|googlemail)\.com$/.test(email)) {
    fail(401, 'google_required');
  }

  const name = clean(decode(h('x-community-name')), 60);
  let photo = decode(h('x-community-photo'));
  if (!photo.startsWith('https://') || photo.length > 400) {
    photo = '';
  }

  const keyHeader = h('x-community-key').trim();
  let verified = false;

  const bearer = /^Bearer\s+(.+)$/i.exec(h('authorization'));
  if (bearer && env.GOOGLE_WEB_CLIENT_ID) {
    const gEmail = await verifyGoogleToken(bearer[1], env);
    if (gEmail && gEmail === email) verified = true;
  }

  const row = await env.DB.prepare(
    'SELECT * FROM members WHERE email = ?'
  ).bind(email).first();

  const hasKey = /^[0-9a-f]{32,64}$/i.test(keyHeader);
  const keyHash = hasKey ? await sha256(keyHeader) : null;

  if (!verified) {
    if (!hasKey) fail(401, 'sign_in_required');
    if (row && row.key_hash && row.key_hash !== keyHash) {
      fail(403, 'community_key_mismatch');
    }
  }

  const t = nowSec();
  const newKey = keyHash || (row && row.key_hash) || null;

  const changed =
    !row ||
    (name && row.name !== name) ||
    (photo && row.photo !== photo) ||
    row.key_hash !== newKey ||
    t - (row.last_seen || 0) > 600;

  if (changed) {
    await env.DB.prepare(
      `INSERT INTO members
       (email, name, photo, key_hash, created_at, last_seen)
       VALUES (?1, ?2, ?3, ?4, ?5, ?5)
       ON CONFLICT(email) DO UPDATE SET
       name = CASE WHEN ?2 != '' THEN ?2 ELSE members.name END,
       photo = CASE WHEN ?3 != '' THEN ?3 ELSE members.photo END,
       key_hash = ?4,
       last_seen = ?5`
    ).bind(email, name, photo, newKey, t).run();
  }

  const admins = String(env.ADMIN_EMAILS || '')
    .toLowerCase()
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  return {
    email,
    name: name || (row && row.name) || '',
    admin: admins.includes(email),
  };
}

// ---------------- COMMUNITY POSTS ----------------

const POST_SELECT = `
  SELECT p.*, m.name AS name, m.photo AS photo,
    (SELECT COUNT(*) FROM likes l
     WHERE l.post_id = p.id) AS like_count,
    (SELECT COUNT(*) FROM comments c
     WHERE c.post_id = p.id) AS comment_count,
    EXISTS(
      SELECT 1 FROM likes l
      WHERE l.post_id = p.id AND l.email = ?1
    ) AS liked
  FROM posts p
  LEFT JOIN members m ON m.email = p.email`;

function postView(r, me) {
  return {
    id: r.id,
    email: r.email,
    name: r.name || '',
    photoUrl: r.photo || '',
    kind: r.kind,
    text: r.text,
    movieTitle: r.movie_title || '',
    movieImage: r.movie_image || '',
    movieId: r.movie_id,
    movieType: r.movie_type || '',
    rating: r.rating,
    createdAt: r.created_at,
    likeCount: r.like_count || 0,
    commentCount: r.comment_count || 0,
    likedByMe: !!r.liked,
    mine: r.email === me,
  };
}

async function getPost(env, id, me) {
  const r = await env.DB.prepare(
    POST_SELECT + ' WHERE p.id = ?2'
  ).bind(me, id).first();
  return r ? postView(r, me) : null;
}

async function listPosts(env, me, url) {
  const kind = url.searchParams.get('kind');

  const rows =
    kind === 'tweet' || kind === 'recommendation'
      ? await env.DB.prepare(
          POST_SELECT +
          ' WHERE p.kind = ?2 ORDER BY p.created_at DESC LIMIT 60'
        ).bind(me, kind).all()
      : await env.DB.prepare(
          POST_SELECT +
          ' ORDER BY p.created_at DESC LIMIT 60'
        ).bind(me).all();

  return {
    posts: rows.results.map((r) => postView(r, me)),
  };
}

async function createPost(env, user, body) {
  const kind =
    body.kind === 'recommendation' ? 'recommendation' : 'tweet';

  const text = clean(body.text, 500);
  const movieTitle = clean(body.movieTitle, 160);

  let movieImage = clean(body.movieImage, 400);
  if (!movieImage.startsWith('https://')) movieImage = '';

  const movieId =
    body.movieId != null && Number.isFinite(Number(body.movieId))
      ? Math.trunc(Number(body.movieId))
      : null;

  const movieType =
    body.movieType === 'tv' ? 'tv' : movieTitle ? 'movie' : '';

  let rating = Math.trunc(Number(body.rating));
  rating =
    movieTitle && rating >= 1 && rating <= 10 ? rating : null;

  if (kind === 'recommendation' && !movieTitle) {
    fail(400, 'recommendation_needs_a_movie');
  }
  if (!text && !movieTitle) fail(400, 'empty');

  const recent = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM posts WHERE email = ? AND created_at > ?'
  ).bind(user.email, nowSec() - 600).first();

  if (recent.n >= 8) fail(429, 'slow_down');

  const id = newId();

  await env.DB.prepare(
    `INSERT INTO posts
     (id, email, kind, text, movie_title, movie_image,
      movie_id, movie_type, rating, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    id, user.email, kind, text, movieTitle, movieImage,
    movieId, movieType, rating, nowSec()
  ).run();

  return { post: await getPost(env, id, user.email) };
}

async function deletePost(env, user, body) {
  const id = clean(body.postId, 40);

  const p = await env.DB.prepare(
    'SELECT email FROM posts WHERE id = ?'
  ).bind(id).first();

  if (!p) return { ok: true };
  if (p.email !== user.email && !user.admin) {
    fail(403, 'forbidden');
  }

  await env.DB.batch([
    env.DB.prepare('DELETE FROM likes WHERE post_id = ?').bind(id),
    env.DB.prepare('DELETE FROM comments WHERE post_id = ?').bind(id),
    env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(id),
  ]);

  return { ok: true };
}

async function toggleLike(env, user, body) {
  const id = clean(body.postId, 40);

  const p = await env.DB.prepare(
    'SELECT id FROM posts WHERE id = ?'
  ).bind(id).first();

  if (!p) fail(404, 'not_found');

  const had = await env.DB.prepare(
    'SELECT 1 AS x FROM likes WHERE post_id = ? AND email = ?'
  ).bind(id, user.email).first();

  if (had) {
    await env.DB.prepare(
      'DELETE FROM likes WHERE post_id = ? AND email = ?'
    ).bind(id, user.email).run();
  } else {
    await env.DB.prepare(
      'INSERT INTO likes (post_id, email, created_at) VALUES (?, ?, ?)'
    ).bind(id, user.email, nowSec()).run();
  }

  const n = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM likes WHERE post_id = ?'
  ).bind(id).first();

  return { liked: !had, likeCount: n.n };
}

// ---------------- COMMENTS ----------------

async function listComments(env, user, url) {
  const postId = clean(url.searchParams.get('postId'), 40);

  const post = await env.DB.prepare(
    'SELECT email FROM posts WHERE id = ?'
  ).bind(postId).first();

  if (!post) fail(404, 'not_found');

  const rows = await env.DB.prepare(
    `SELECT c.*, m.name AS name, m.photo AS photo
     FROM comments c
     LEFT JOIN members m ON m.email = c.email
     WHERE c.post_id = ?
     ORDER BY c.created_at ASC LIMIT 200`
  ).bind(postId).all();

  return {
    comments: rows.results.map((c) => ({
      id: c.id,
      email: c.email,
      name: c.name || '',
      photoUrl: c.photo || '',
      text: c.text,
      createdAt: c.created_at,
      mine: c.email === user.email,
      canDelete:
        c.email === user.email ||
        post.email === user.email ||
        user.admin,
    })),
  };
}

async function addComment(env, user, body) {
  const postId = clean(body.postId, 40);
  const text = clean(body.text, 300);

  if (!text) fail(400, 'empty');

  const post = await env.DB.prepare(
    'SELECT id FROM posts WHERE id = ?'
  ).bind(postId).first();

  if (!post) fail(404, 'not_found');

  const recent = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM comments WHERE email = ? AND created_at > ?'
  ).bind(user.email, nowSec() - 120).first();

  if (recent.n >= 10) fail(429, 'slow_down');

  await env.DB.prepare(
    `INSERT INTO comments
     (id, post_id, email, text, created_at)
     VALUES (?, ?, ?, ?, ?)`
  ).bind(newId(), postId, user.email, text, nowSec()).run();

  const n = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM comments WHERE post_id = ?'
  ).bind(postId).first();

  return { ok: true, commentCount: n.n };
}

async function deleteComment(env, user, body) {
  const id = clean(body.id, 40);

  const c = await env.DB.prepare(
    `SELECT c.email AS email, p.email AS owner
     FROM comments c
     JOIN posts p ON p.id = c.post_id
     WHERE c.id = ?`
  ).bind(id).first();

  if (!c) return { ok: true };

  if (
    c.email !== user.email &&
    c.owner !== user.email &&
    !user.admin
  ) {
    fail(403, 'forbidden');
  }

  await env.DB.prepare(
    'DELETE FROM comments WHERE id = ?'
  ).bind(id).run();

  return { ok: true };
}

// ---------------- PROFILES ----------------

async function getProfile(env, user, url) {
  const email = clean(
    url.searchParams.get('email'), 120
  ).toLowerCase();

  const m = await env.DB.prepare(
    'SELECT email, name, photo, bio FROM members WHERE email = ?'
  ).bind(email).first();

  if (!m) fail(404, 'not_found');

  const rows = await env.DB.prepare(
    POST_SELECT +
    ' WHERE p.email = ?2 ORDER BY p.created_at DESC LIMIT 40'
  ).bind(user.email, email).all();

  const posts = rows.results.map(
    (r) => postView(r, user.email)
  );

  const likes = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM likes l
     JOIN posts p ON p.id = l.post_id
     WHERE p.email = ?`
  ).bind(email).first();

  const count = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM posts WHERE email = ?'
  ).bind(email).first();

  return {
    profile: {
      email: m.email,
      name: m.name || '',
      photoUrl: m.photo || '',
      bio: m.bio || '',
      mine: email === user.email,
      postCount: count.n,
      likeCount: likes.n,
      lastTweet:
        posts.find((p) => p.kind === 'tweet') || null,
      lastRecommendation:
        posts.find((p) => p.kind === 'recommendation') || null,
      posts,
    },
  };
}

async function saveProfileData(env, user, body) {
  const data = body.data;

  if (!data || typeof data !== 'object') {
    fail(400, 'bad_request');
  }

  const text = JSON.stringify(data);
  if (text.length > 30000) fail(413, 'too_large');

  await env.DB.prepare(
    'UPDATE members SET profile_json = ? WHERE email = ?'
  ).bind(text, user.email).run();

  return { ok: true };
}

async function getProfileData(env, url) {
  const email = clean(
    url.searchParams.get('email'), 120
  ).toLowerCase();

  const m = await env.DB.prepare(
    'SELECT profile_json FROM members WHERE email = ?'
  ).bind(email).first();

  let data = null;
  try {
    data = m && m.profile_json
      ? JSON.parse(m.profile_json)
      : null;
  } catch {}

  return { data };
}

async function listPeople(env, user) {
  const rows = await env.DB.prepare(
    `SELECT m.email, m.name, m.photo,
      (SELECT COUNT(*) FROM posts p
       WHERE p.email = m.email) AS post_count
     FROM members m
     WHERE m.email != ?
     ORDER BY m.last_seen DESC LIMIT 300`
  ).bind(user.email).all();

  return {
    people: rows.results.map((r) => ({
      email: r.email,
      name: r.name || '',
      photoUrl: r.photo || '',
      postCount: r.post_count,
    })),
  };
}

// ---------------- WATCH TOGETHER / WATCH NOW ----------------

async function roomView(env, roomId) {
  const r = await env.DB.prepare(
    'SELECT * FROM rooms WHERE id = ?'
  ).bind(roomId).first();

  if (!r) return null;

  const ppl = await env.DB.prepare(
    `SELECT rp.email, rp.state, m.name, m.photo
     FROM room_people rp
     LEFT JOIN members m ON m.email = rp.email
     WHERE rp.room_id = ?
     ORDER BY
       CASE rp.state
         WHEN 'host' THEN 0
         WHEN 'accepted' THEN 1
         WHEN 'invited' THEN 2
         ELSE 3
       END, rp.rowid`
  ).bind(roomId).all();

  const host = ppl.results.find(
    (p) => p.email === r.host_email
  );

  let movie = {};
  try {
    movie = JSON.parse(r.movie_json);
  } catch {}

  return {
    id: r.id,
    hostEmail: r.host_email,
    hostName: (host && host.name) || '',
    movie,
    status: r.started_at ? 'playing' : 'waiting',
    isPublic: Number(r.is_public) === 1,
    viewerCount: ppl.results.filter(
      (p) => p.state === 'host' || p.state === 'accepted'
    ).length,
    startedAt: r.started_at,
    createdAt: r.created_at,
    people: ppl.results
      .filter((p) => p.state !== 'declined')
      .map((p) => ({
        email: p.email,
        name: p.name || '',
        photoUrl: p.photo || '',
        state: p.state,
      })),
  };
}

async function myState(env, roomId, email) {
  const r = await env.DB.prepare(
    `SELECT state FROM room_people
     WHERE room_id = ? AND email = ?`
  ).bind(roomId, email).first();

  return r ? r.state : null;
}

async function createRoom(env, user, body) {
  const m =
    body.movie && typeof body.movie === 'object'
      ? body.movie
      : {};

  const title = clean(m.title, 160);
  if (!title) fail(400, 'bad_request');

  const movie = {
    title,
    url: clean(m.url, 500),
    image: clean(m.image, 400),
    tmdbId:
      m.tmdbId != null && Number.isFinite(Number(m.tmdbId))
        ? Math.trunc(Number(m.tmdbId))
        : null,
    type: m.type === 'tv' ? 'tv' : 'movie',
  };

  const isPublic = body.isPublic === true;

  const invitees = [
    ...new Set(
      (Array.isArray(body.invitees) ? body.invitees : [])
        .map((e) => clean(e, 120).toLowerCase())
    ),
  ]
    .filter((e) => e && e !== user.email)
    .slice(0, 20);

  const open = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM rooms
     WHERE host_email = ? AND created_at > ?`
  ).bind(user.email, nowSec() - 3600).first();

  if (open.n >= 5) fail(429, 'slow_down');

  const id = newId();

  const stmts = [
    env.DB.prepare(
      `INSERT INTO rooms
       (id, host_email, movie_json, started_at, created_at, is_public)
       VALUES (?, ?, ?, NULL, ?, ?)`
    ).bind(
      id, user.email, JSON.stringify(movie),
      nowSec(), isPublic ? 1 : 0
    ),

    env.DB.prepare(
      `INSERT INTO room_people (room_id, email, state)
       VALUES (?, ?, 'host')`
    ).bind(id, user.email),
  ];

  for (const e of invitees) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO room_people (room_id, email, state)
         SELECT ?1, ?2, 'invited'
         WHERE EXISTS (
           SELECT 1 FROM members WHERE email = ?2
         )`
      ).bind(id, e)
    );
  }

  await env.DB.batch(stmts);

  return { room: await roomView(env, id) };
}

// Public rooms available to community members.
async function publicRooms(env) {
  const rows = await env.DB.prepare(
    `SELECT id FROM rooms
     WHERE is_public = 1 AND created_at > ?
     ORDER BY created_at DESC LIMIT 40`
  ).bind(nowSec() - DAY).all();

  const rooms = [];

  for (const row of rows.results) {
    const room = await roomView(env, row.id);
    if (room) rooms.push(room);
  }

  return { rooms };
}

// Anyone authenticated can join a public room.
async function joinPublicRoom(env, user, body) {
  const id = clean(body.roomId, 40);
  if (!id) fail(400, 'bad_request');

  const room = await env.DB.prepare(
    `SELECT id FROM rooms
     WHERE id = ?
       AND is_public = 1
       AND created_at > ?`
  ).bind(id, nowSec() - DAY).first();

  if (!room) fail(404, 'not_found');

  await env.DB.prepare(
    `INSERT INTO room_people (room_id, email, state)
     VALUES (?, ?, 'accepted')
     ON CONFLICT(room_id, email)
     DO UPDATE SET state = 'accepted'
     WHERE state != 'host'`
  ).bind(id, user.email).run();

  return { room: await roomView(env, id) };
}

async function listInvitations(env, user) {
  const rows = await env.DB.prepare(
    `SELECT r.id FROM rooms r
     JOIN room_people rp ON rp.room_id = r.id
     WHERE rp.email = ?
       AND rp.state = 'invited'
       AND r.created_at > ?
     ORDER BY r.created_at DESC LIMIT 20`
  ).bind(user.email, nowSec() - DAY).all();

  const invitations = [];

  for (const r of rows.results) {
    const v = await roomView(env, r.id);
    if (v) invitations.push({
      ...v,
      roomId: v.id,
    });
  }

  return { invitations };
}

async function respondInvitation(env, user, body) {
  const roomId = clean(body.roomId, 40);
  const st = await myState(env, roomId, user.email);

  if (!st) fail(404, 'not_found');

  if (
    st === 'invited' ||
    st === 'declined' ||
    st === 'accepted'
  ) {
    await env.DB.prepare(
      `UPDATE room_people SET state = ?
       WHERE room_id = ? AND email = ?`
    ).bind(
      body.accept ? 'accepted' : 'declined',
      roomId,
      user.email
    ).run();
  }

  return { room: await roomView(env, roomId) };
}

async function getRoom(env, user, url) {
  const id = clean(url.searchParams.get('id'), 40);

  if (!(await myState(env, id, user.email))) {
    fail(403, 'forbidden');
  }

  const room = await roomView(env, id);
  if (!room) fail(404, 'not_found');

  return { room };
}

async function myRooms(env, user) {
  const rows = await env.DB.prepare(
    `SELECT r.id FROM rooms r
     JOIN room_people rp ON rp.room_id = r.id
     WHERE rp.email = ?
       AND rp.state IN ('host','accepted')
       AND r.created_at > ?
     ORDER BY r.created_at DESC LIMIT 10`
  ).bind(user.email, nowSec() - DAY).all();

  const rooms = [];

  for (const r of rows.results) {
    const v = await roomView(env, r.id);
    if (v) rooms.push(v);
  }

  return { rooms };
}

// ---------------- ROOM CHAT AND REACTIONS ----------------

async function postEvent(env, user, body) {
  const roomId = clean(body.roomId, 40);
  const kind = body.kind;
  const st = await myState(env, roomId, user.email);

  if (st !== 'host' && st !== 'accepted') {
    fail(403, 'forbidden');
  }

  const t = nowSec();

  if (kind === 'start') {
    if (st !== 'host') fail(403, 'forbidden');

    await env.DB.prepare(
      `UPDATE rooms SET started_at = ?
       WHERE id = ? AND started_at IS NULL`
    ).bind(t, roomId).run();

    await env.DB.prepare(
      `INSERT INTO room_events
       (room_id, kind, email, name, text, created_at)
       VALUES (?, 'start', ?, ?, '', ?)`
    ).bind(roomId, user.email, user.name, t).run();

    return { ok: true };
  }

  if (kind !== 'msg' && kind !== 'react') {
    fail(400, 'bad_request');
  }

  const text = clean(
    body.text, kind === 'react' ? 8 : 300
  );

  if (!text) fail(400, 'empty');

  const recent = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM room_events
     WHERE room_id = ? AND email = ? AND created_at > ?`
  ).bind(roomId, user.email, t - 10).first();

  if (recent.n >= 12) fail(429, 'slow_down');

  await env.DB.prepare(
    `INSERT INTO room_events
     (room_id, kind, email, name, text, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(
    roomId, kind, user.email, user.name, text, t
  ).run();

  return { ok: true };
}

async function getEvents(env, user, url) {
  const roomId = clean(
    url.searchParams.get('roomId'), 40
  );

  const since = Math.max(
    0,
    parseInt(url.searchParams.get('since') || '0', 10) || 0
  );

  if (!(await myState(env, roomId, user.email))) {
    fail(403, 'forbidden');
  }

  const room = await env.DB.prepare(
    'SELECT started_at FROM rooms WHERE id = ?'
  ).bind(roomId).first();

  if (!room) fail(404, 'not_found');

  const rows =
    since > 0
      ? await env.DB.prepare(
          `SELECT seq, kind, email, name, text
           FROM room_events
           WHERE room_id = ? AND seq > ?
           ORDER BY seq ASC LIMIT 100`
        ).bind(roomId, since).all()
      : await env.DB.prepare(
          `SELECT * FROM (
             SELECT seq, kind, email, name, text
             FROM room_events
             WHERE room_id = ?
             ORDER BY seq DESC LIMIT 40
           ) ORDER BY seq ASC`
        ).bind(roomId).all();

  return {
    events: rows.results,
    startedAt: room.started_at,
    now: nowSec(),
  };
}

// ---------------- CLEANUP ----------------

async function cleanup(env) {
  const cut = nowSec() - 2 * DAY;

  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM room_events
       WHERE room_id IN (
         SELECT id FROM rooms WHERE created_at < ?
       )`
    ).bind(cut),

    env.DB.prepare(
      `DELETE FROM room_people
       WHERE room_id IN (
         SELECT id FROM rooms WHERE created_at < ?
       )`
    ).bind(cut),

    env.DB.prepare(
      'DELETE FROM rooms WHERE created_at < ?'
    ).bind(cut),
  ]);
}

// ---------------- MAIN ROUTER ----------------

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': '*',
          'access-control-allow-methods': 'GET,POST,OPTIONS',
        },
      });
    }

    if (path === '/' || path === '/health') {
      return json({
        ok: true,
        service: 'damimovies-community',
        db: !!env.DB,
      });
    }

    if (!env.DB) {
      return json({ error: 'worker_not_configured' }, 503);
    }

    if (!path.startsWith('/community/')) {
      return json({ error: 'not_found' }, 404);
    }

    try {
      const user = await authenticate(request, env);
      let body = {};

      if (request.method === 'POST') {
        try {
          body = await request.json();
        } catch {
          fail(400, 'bad_request');
        }
      }

      const get = request.method === 'GET';
      const post = request.method === 'POST';
      let out;

      if (get && path === '/community/posts')
        out = await listPosts(env, user.email, url);

      else if (post && path === '/community/posts')
        out = await createPost(env, user, body);

      else if (post && path === '/community/delete')
        out = await deletePost(env, user, body);

      else if (post && path === '/community/like')
        out = await toggleLike(env, user, body);

      else if (get && path === '/community/comments')
        out = await listComments(env, user, url);

      else if (post && path === '/community/comments')
        out = await addComment(env, user, body);

      else if (post && path === '/community/comments/delete')
        out = await deleteComment(env, user, body);

      else if (get && path === '/community/profile')
        out = await getProfile(env, user, url);

      else if (get && path === '/community/profile/data')
        out = await getProfileData(env, url);

      else if (post && path === '/community/profile/data')
        out = await saveProfileData(env, user, body);

      else if (get && path === '/community/people')
        out = await listPeople(env, user);

      // Public Watch Now
      else if (get && path === '/community/watch/public')
        out = await publicRooms(env);

      else if (post && path === '/community/watch/join')
        out = await joinPublicRoom(env, user, body);

      // Private and public room creation
      else if (post && path === '/community/watch/rooms')
        out = await createRoom(env, user, body);

      else if (get && path === '/community/watch/invitations')
        out = await listInvitations(env, user);

      else if (post && path === '/community/watch/respond')
        out = await respondInvitation(env, user, body);

      else if (get && path === '/community/watch/room')
        out = await getRoom(env, user, url);

      else if (get && path === '/community/watch/mine')
        out = await myRooms(env, user);

      else if (post && path === '/community/watch/event')
        out = await postEvent(env, user, body);

      else if (get && path === '/community/watch/events')
        out = await getEvents(env, user, url);

      else fail(404, 'not_found');

      if (Math.random() < 0.02) {
        ctx.waitUntil(cleanup(env));
      }

      return json(out);
    } catch (e) {
      if (e instanceof HttpError) {
        return json({ error: e.code }, e.status);
      }
      return json({ error: 'server_error' }, 500);
    }
  },
};
