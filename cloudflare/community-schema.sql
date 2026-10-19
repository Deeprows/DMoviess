-- Run once in Cloudflare: Storage & databases -> D1 -> your database -> Console.
-- (Paste all of it and press Execute.)

CREATE TABLE IF NOT EXISTS members (
  email        TEXT PRIMARY KEY,
  name         TEXT NOT NULL DEFAULT '',
  photo        TEXT NOT NULL DEFAULT '',
  bio          TEXT NOT NULL DEFAULT '',
  key_hash     TEXT,
  profile_json TEXT,
  created_at   INTEGER NOT NULL,
  last_seen    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS posts (
  id          TEXT PRIMARY KEY,
  email       TEXT NOT NULL,
  kind        TEXT NOT NULL,
  text        TEXT NOT NULL DEFAULT '',
  movie_title TEXT NOT NULL DEFAULT '',
  movie_image TEXT NOT NULL DEFAULT '',
  movie_id    INTEGER,
  movie_type  TEXT NOT NULL DEFAULT '',
  rating      INTEGER,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS posts_time  ON posts (created_at DESC);
CREATE INDEX IF NOT EXISTS posts_email ON posts (email, created_at DESC);

CREATE TABLE IF NOT EXISTS likes (
  post_id    TEXT NOT NULL,
  email      TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, email)
);

CREATE TABLE IF NOT EXISTS comments (
  id         TEXT PRIMARY KEY,
  post_id    TEXT NOT NULL,
  email      TEXT NOT NULL,
  text       TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS comments_post ON comments (post_id, created_at);

CREATE TABLE IF NOT EXISTS rooms (
  id         TEXT PRIMARY KEY,
  host_email TEXT NOT NULL,
  movie_json TEXT NOT NULL,
  started_at INTEGER,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS room_people (
  room_id TEXT NOT NULL,
  email   TEXT NOT NULL,
  state   TEXT NOT NULL,
  PRIMARY KEY (room_id, email)
);

CREATE TABLE IF NOT EXISTS room_events (
  seq        INTEGER PRIMARY KEY AUTOINCREMENT,
  room_id    TEXT NOT NULL,
  kind       TEXT NOT NULL,
  email      TEXT NOT NULL,
  name       TEXT NOT NULL DEFAULT '',
  text       TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS room_events_room ON room_events (room_id, seq);
