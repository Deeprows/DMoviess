import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- Firebase
// Same Firebase project as the Deeprowss / Footbolive apps (deeprows-4d37c).
// These are public client identifiers, not secrets. Add an Android app with
// package com.damimovies.damimovies in the Firebase console and give its App
// ID to the build (GitHub repo variable FIREBASE_ANDROID_APP_ID). See
// PUSH_SETUP.md.
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
const _webApiKey = 'AIzaSyBs9eSquNu2drJjM3vqFGDX1QU-VE1_F7U';

FirebaseOptions get _options => FirebaseOptions(
      apiKey: _androidApiKey.isNotEmpty ? _androidApiKey : _webApiKey,
      appId: _androidAppId,
      messagingSenderId: '227439941748',
      projectId: 'deeprows-4d37c',
      storageBucket: 'deeprows-4d37c.firebasestorage.app',
    );

/// Runs when a message arrives while the app is closed. Android itself draws
/// notification messages; this only keeps Firebase initialised.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: _options);
}

/// What the user can subscribe to. `id` is the FCM topic name and must match
/// what the GitHub jobs publish to (see PUSH_SETUP.md).
enum PushTopic {
  trending('trending', 'Trending movie alerts',
      'When a new movie starts trending', Icons.local_fire_department_rounded),
  news('news', 'Announcements', 'News and messages from DamiMovies',
      Icons.campaign_rounded);

  const PushTopic(this.id, this.title, this.subtitle, this.icon);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  String get prefKey => 'push_topic_$id';
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// Lets the service show a banner while the app is open.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  Future<void>? _initFuture;
  bool _ready = false;
  bool get isReady => _ready;
  String? initError;

  /// Safe to call many times; the work runs once.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      if (_androidAppId.isEmpty) {
        throw StateError('FIREBASE_ANDROID_APP_ID was not set in the build');
      }
      await Firebase.initializeApp(options: _options);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      try {
        // Android 13+ permission prompt (no-op on older versions).
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      } catch (e) {
        debugPrint('Push permission request failed: $e');
      }
      FirebaseMessaging.onMessage.listen(_onForeground);
      _ready = true;
      initError = null;
      await syncTopics();
      messaging.onTokenRefresh.listen((_) => syncTopics());
    } catch (e, st) {
      initError = '$e';
      debugPrint('Push init failed: $e\n$st');
    }
  }

  Future<bool> isEnabled(PushTopic t) async =>
      (await SharedPreferences.getInstance()).getBool(t.prefKey) ?? true;

  /// Applies the saved choices to FCM (everything is on by default).
  Future<void> syncTopics() async {
    if (!_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final messaging = FirebaseMessaging.instance;
    for (final t in PushTopic.values) {
      try {
        if (prefs.getBool(t.prefKey) == false) {
          await messaging.unsubscribeFromTopic(t.id);
        } else {
          await messaging.subscribeToTopic(t.id);
        }
      } catch (e) {
        debugPrint('Topic ${t.id} sync failed: $e');
      }
    }
  }

  Future<void> setEnabled(PushTopic t, bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(t.prefKey, on);
    if (!_ready) return;
    if (on) {
      await FirebaseMessaging.instance.subscribeToTopic(t.id);
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic(t.id);
    }
  }

  /// App is open: Android does not draw FCM notifications itself, so show an
  /// in-app banner.
  void _onForeground(RemoteMessage m) {
    final title = (m.notification?.title ?? m.data['title'] ?? '').toString();
    final body = (m.notification?.body ?? m.data['body'] ?? '').toString();
    if (title.isEmpty && body.isEmpty) return;
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
      ));
  }
}
