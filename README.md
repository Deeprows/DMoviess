# DamiMovies (Flutter)

DamiMovies is a movie-and-series discovery app based on the movie-only portion of the Deeprowss/SB project. Football fixtures, live TV, match chat and unrelated local music/video features are intentionally excluded.

## Included app features

- **TMDB home:** trending titles, Top 10 Today (TMDB daily trending), Continue Watching, latest YouTube trailers, search, genre/type filters and movie posters.
- **Movie detail page:** synopsis, poster/backdrop, cast, ratings, runtime, release details, similar titles, Watch Later and share.
- **Player:** embedded streams, HLS (`m3u8`), DASH (`mpd`) and direct media playback where the host and Android WebView allow it; main/backup/third-source switching; reload and error recovery; landscape and fullscreen controls; player source/user-agent/referer fields in `assets/data/movies.json`; low-quality HLS option; best-effort popup/ad redirect blocking; screen-awake option; Android picture-in-picture; background media notification with play/pause, rewind, forward and stop controls.
- **Resume support:** the built-in HTML5 player saves playback progress locally and offers a resume prompt on reopen. Some third-party embedded players do not expose playback position and cannot be resumed by the app.
- **Browser and downloads:** in-app browser, downloads triggered from movie pages or websites, background download queue, progress, pause/resume/retry, open and delete actions.
- **Library:** Watch Later, watch history and Continue Watching progress, saved on-device.
- **Settings:** nine color themes, English/Arabic/French/Spanish/Portuguese/Hindi/Turkish/Hausa/Yoruba labels, popup shield, low-quality playback preference, screen-awake and background-playback switches, notice, update checker, share and About.

## Build APK using GitHub Actions

1. Push this project to your DamiMovies repository.
2. In GitHub repository **Settings → Secrets and variables → Actions**, set `TMDB_API_KEY` to a TMDB v3 API key if you want to override the built-in key.
3. Open **Actions → Build DamiMovies APK → Run workflow**.
4. Download the `DamiMovies-APK` artifact after the workflow succeeds.

The workflow generates the Android platform, patches the manifest and native activity for PiP and background media controls, gets packages and builds the release APK.

## Optional build configuration

Pass `--dart-define` values in the workflow to customise `APP_VERSION`, `PLAYER_USER_AGENT`, `PLAYER_ORIGIN`, `EMBED_BASE`, `ALT_EMBED_BASE`, `DOWNLOAD_BASE`, `REPLACE_HOSTS`, `SUPPORT_URL`, `UPDATE_URL` and `NOTICE_URL`. `UPDATE_URL` can point to a JSON manifest with `version`, `notes` and `apkUrl` fields, or to a direct link. `NOTICE_URL` can point to JSON containing `title` and `message`/`body`/`text`. Leaving support/update/notice URLs blank disables those external integrations gracefully.

## Movie catalogue fields

`assets/data/movies.json` accepts `name`/`title`, `tmdbId`, `type`, `url`, `altUrl`/`backupUrl`, `thirdUrl`, `downloadUrl`, `image`, `backdrop`, `rating`, `genre`, `overview`/`summary`, `referer`, `userAgent`, `altReferer`, `altUserAgent`, `thirdReferer`, and `thirdUserAgent`. Entries may omit stream URLs if they only need to appear as TMDB catalogue titles; playing requires a valid source. For TMDB IDs without a custom stream URL, the app uses the configured default embed/download URL patterns.

## Playback and content notice

Playback and downloads depend on the selected third-party source, its availability and its terms. Some sources may block Android WebView or restrict playback based on region, cookies or referrer. DamiMovies does not host or own movie/series media; use sources you are authorised to access.
