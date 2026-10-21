// Sends one notification to a topic. Use it from GitHub:
// Actions > "Send push notification" > Run workflow.
// Also the way to send your own message to every user (topic "news").
import { initializeApp, cert } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";

const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!raw) { console.error("FIREBASE_SERVICE_ACCOUNT secret is missing in this repository"); process.exit(1); }

const topic = (process.env.TOPIC || "news").trim();
try {
  initializeApp({ credential: cert(JSON.parse(raw)) });
  const id = await getMessaging().send({
    topic,
    notification: {
      title: process.env.TITLE || "DamiMovies",
      body: process.env.BODY || "Push notifications are working.",
    },
    data: { type: topic },
    android: { priority: "high", notification: { channelId: topic === "trending" ? "trending" : "news" } },
  });
  console.log(`Sent to topic "${topic}":`, id);
} catch (e) {
  console.error("FAILED:", e.code || "", e.message);
  process.exit(1);
}
