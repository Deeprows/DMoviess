import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/movie_detail_screen.dart';
import 'ad_service.dart';
import 'auth_service.dart';
import 'movie_library.dart';
import 'tmdb_service.dart';

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

  // A notification may arrive before Firebase, the login screen, or the app
  // navigator is ready. Keep its movie here and open it after sign-in.
  _MovieDestination? _pendingMovie;
  String? _lastTappedMessageId;
  bool _navigationReady = false;
  bool _navigationScheduled = false;

  /// Called once after the startup splash hands control to AuthGate.
  void onNavigationReady() {
    _navigationReady = true;
    _openPendingMovie();
  }

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
      FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);
      AuthService.instance.addListener(_openPendingMovie);
      _ready = true;

      // A tap that launched the app from a terminated state isn't delivered
      // through onMessageOpenedApp; it must be read once here instead.
      try {
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) _onNotificationOpened(initialMessage);
      } catch (e) {
        debugPrint('Could not read launch notification: $e');
      }
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

  /// Process a tap on a system notification (background/cold start), or on
  /// the "View movie" action in our foreground in-app banner.
  void _onNotificationOpened(RemoteMessage message) {
    final destination = _MovieDestination.fromData(message.data);
    if (destination == null) {
      // General announcements still open the app normally.
      return;
    }

    final messageId = message.messageId;
    if (messageId != null && messageId == _lastTappedMessageId) return;
    _lastTappedMessageId = messageId;
    _pendingMovie = destination;
    _openPendingMovie();
  }

  void _openPendingMovie() {
    if (!_navigationReady ||
        _pendingMovie == null ||
        !AuthService.instance.signedIn ||
        _navigationScheduled) {
      return;
    }

    _navigationScheduled = true;
    // Let AuthGate build the signed-in home page before pushing the details
    // route. This also works when the app is resumed from the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      final navigator = AdService.instance.navigatorKey.currentState;
      final destination = _pendingMovie;
      if (navigator == null ||
          !navigator.mounted ||
          destination == null ||
          !AuthService.instance.signedIn) {
        return;
      }

      _pendingMovie = null;
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => _NotificationMovieLoader(destination: destination),
      ));
    });
  }

  /// Android handles a background notification's display. When the app is in
  /// the foreground, show the same alert with a tappable movie action.
  void _onForeground(RemoteMessage message) {
    final title = (message.notification?.title ?? message.data['title'] ?? '')
        .toString();
    final body = (message.notification?.body ?? message.data['body'] ?? '')
        .toString();
    if (title.isEmpty && body.isEmpty) return;

    final hasMovie = _MovieDestination.fromData(message.data) != null;
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
        action: hasMovie
            ? SnackBarAction(
                label: 'View movie',
                onPressed: () => _onNotificationOpened(message),
              )
            : null,
      ));
  }
}

/// Identifies one movie without relying on the notification's visible text.
/// All values in an FCM `data` payload must be strings.
class _MovieDestination {
  const _MovieDestination({required this.id, required this.mediaType});

  final int id;
  final String mediaType;

  static _MovieDestination? fromData(Map<String, dynamic> data) {
    // Accept existing/common naming conventions. Prefer an explicit movie ID.
    String? movieId;
    for (final key in [
      'movieId',
      'movie_id',
      'tmdbId',
      'tmdb_id',
    ]) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        movieId = value;
        break;
      }
    }

    final eventType = (data['type'] ?? data['notificationType'] ?? '')
        .toString()
        .toLowerCase();
    if (movieId == null &&
        (eventType == 'trending_movie' ||
            eventType == 'movie' ||
            eventType == 'trending')) {
      movieId = data['id']?.toString().trim();
    }

    final id = int.tryParse(movieId ?? '');
    if (id == null || id <= 0) return null;

    final rawType = (data['mediaType'] ??
            data['media_type'] ??
            data['movieType'] ??
            data['movie_type'] ??
            '')
        .toString()
        .toLowerCase();
    return _MovieDestination(
      id: id,
      mediaType: rawType == 'tv' || rawType == 'series' ? 'tv' : 'movie',
    );
  }
}

/// Opens directly into a requested movie, not a generic movie catalogue.
/// A small loading/error page prevents a slow connection from looking like
/// an ignored tap. No provider names or technical errors appear in the UI.
class _NotificationMovieLoader extends StatefulWidget {
  const _NotificationMovieLoader({required this.destination});

  final _MovieDestination destination;

  @override
  State<_NotificationMovieLoader> createState() =>
      _NotificationMovieLoaderState();
}

class _NotificationMovieLoaderState extends State<_NotificationMovieLoader> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _openMovie();
  }

  Future<void> _openMovie() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final movie = await TmdbService()
          .movieById(widget.destination.id,
              mediaType: widget.destination.mediaType)
          .timeout(const Duration(seconds: 19), onTimeout: () => null);
      if (!mounted) return;
      if (movie == null) {
        setState(() => _loading = false);
        return;
      }

      bool saved = false;
      try {
        await MovieLibrary.instance.load().timeout(const Duration(seconds: 4));
        saved = MovieLibrary.instance.isSaved(movie);
      } catch (_) {
        // The movie can still be opened if saved-list storage is unavailable.
      }
      if (!mounted) return;

      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => MovieDetailScreen(
          movie: movie,
          saved: saved,
          onToggleSaved: () async {
            try {
              await MovieLibrary.instance.load();
              await MovieLibrary.instance.toggleSaved(movie);
            } catch (e) {
              debugPrint('Could not update saved movies: $e');
            }
          },
        ),
      ));
    } catch (e) {
      debugPrint('Could not open notification movie: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('DamiMovies')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 18),
                      Text('Opening movie…'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 44),
                      const SizedBox(height: 14),
                      const Text(
                        'Unable to open this movie right now.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _openMovie,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
          ),
        ),
      );
}
