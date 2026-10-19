# DamiMovies: Community + Remove-ads token setup

The app uses **two** Cloudflare Workers:

| Worker | File | App setting (GitHub secret) | Does |
|---|---|---|---|
| `damimovies-auth` | `cloudflare/auth-worker.js` | `AUTH_API_URL` | Gmail sign-up list + "request a token" Telegram alert |
| `damimovies-community` | `cloudflare/community-worker.js` | `COMMUNITY_API_URL` | Posts, likes, comments, profiles, Watch Together |

---
## Part A: Community worker

1. **Create the database.** Cloudflare dashboard -> *Storage & databases* -> *D1 SQL database* -> *Create* -> name `damimovies-community`.
2. Open it -> *Console* -> paste everything from `cloudflare/community-schema.sql` -> *Execute*.
3. **Create the worker.** *Workers & Pages* -> *Create* -> *Start with Hello World* -> name `damimovies-community` -> *Deploy* -> *Edit code*. Delete the sample, paste all of `cloudflare/community-worker.js`, *Deploy*.
4. **Bind the database.** Worker -> *Settings* -> *Bindings* -> *Add* -> *D1 database* -> variable name **`DB`** (capital letters) -> choose `damimovies-community` -> Save/Deploy.
5. **Variables** (Worker -> Settings -> Variables and Secrets):
   - `GOOGLE_WEB_CLIENT_ID` = the same Web client ID you use for the app (recommended).
   - `ADMIN_EMAILS` = your Gmail (lets you delete any post/comment). Optional.
6. **Test:** open `https://damimovies-community.<your-subdomain>.workers.dev/health`. You should see `{"ok":true,"service":"damimovies-community","db":true}`. If `db` is `false`, redo step 4.
7. **Connect the app:** GitHub repo -> Settings -> Secrets and variables -> Actions -> new secret **`COMMUNITY_API_URL`** = the worker address with no slash at the end, e.g. `https://damimovies-community.yourname.workers.dev`.
8. Run **Actions -> Build DamiMovies APK**, install, sign in with Gmail, open Community and post.

Reset a member locked to another phone (D1 console):
`UPDATE members SET key_hash = NULL WHERE email = 'person@gmail.com';`

---
## Part B: Remove-ads token

Tokens are signed offline, so the app and worker never hold a secret.

1. Open `tool/token-admin.html` in your phone/computer browser -> **Create new signing keys**.
2. Save the **private key** somewhere safe (never on GitHub). Copy the **public key**.
3. In `assets/data/app_config.json` set under `removeAds`:
   - `"publicKey": "<the public key>"`
   - `"whatsapp": "<your WhatsApp number with country code, digits only>"`
   - adjust `plans` / `localPrices` if you like.
4. Commit and rebuild the APK.
5. **Token request alerts** (auth worker, needs `AUTH_API_URL`): in `damimovies-auth` add KV binding `USERS`, variable `GOOGLE_WEB_CLIENT_ID`, and for Telegram: secret `TELEGRAM_BOT_TOKEN` + variable `TELEGRAM_CHAT_ID`. Create the bot with @BotFather, message it once, then get your chat id from @userinfobot.
6. **Selling a token:** customer opens *Remove ads*, enters WhatsApp number -> you get a Telegram message with their **Device ID** and days -> in `token-admin.html` paste private key, Device ID, days -> *Make token* -> *Send on WhatsApp*. The customer pastes it into the app.

A token only works on the phone whose Device ID it was made for, and only once.
