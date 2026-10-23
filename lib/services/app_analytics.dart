import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/movie.dart';

/// Sends anonymous usage counts to the existing Community Worker + D1.
/// Analytics must never interrupt navigation or playback.
/// A random installation ID is transmitted, not email, tokens, device IDs,
/// IP addresses, searches, movie titles, or player URLs.
class AppAnalytics {
  AppAnalytics._();
  static final AppAnalytics instance = AppAnalytics._();

  static const _installationKey = 'damimovies_anonymous_analytics_id_v1';
  static const _enabledKey = 'damimovies_analytics_enabled';

  Future<String>? _idFuture;

  Future<String> _installationId() {
    return _idFuture ??= _getOrCreateId();
  }

  Future<String> _getOrCreateId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationKey);
    if (existing != null && RegExp(r'^[A-Za-z0-9_-]{20,64}$').hasMatch(existing)) {
      return existing;
    }
    final secure = Random.secure();
    final bytes = List<int>.generate(24, (_) => secure.nextInt(256));
    final id = base64UrlEncode(bytes).replaceAll('=', '');
    await prefs.setString(_installationKey, id);
    return id;
  }

  /// A settings switch can turn this off by writing false to _enabledKey.
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  void track(String event, {String screen = '', String movieId = ''}) {
    unawaited(_send(event, screen: screen, movieId: movieId));
  }

  Future<void> _send(String event, {required String screen, required String movieId}) async {
    final base = AppConfig.communityUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!base.startsWith('https://')) return;
    try {
      if (!await isEnabled()) return;
      final visitorId = await _installationId();
      final uri = Uri.parse('$base/analytics/event');
      final res = await http
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'event': event,
              'screen': screen,
              'movieId': movieId,
              'visitorId': visitorId,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (kDebugMode && res.statusCode >= 400) {
        debugPrint('App analytics skipped (${res.statusCode})');
      }
    } catch (_) {
      // Best-effort telemetry; no dialogs, errors or retries in the UI.
    }
  }

  void appOpened() => track('app_open', screen: 'movies');
  void screenViewed(String screen) => track('screen_view', screen: screen);
  void movieDetailsViewed(Movie movie) => track(
        'movie_detail_view',
        screen: 'movie_details',
        movieId: movie.tmdbId?.toString() ?? '',
      );
  void playerOpened(Movie movie) => track(
        'movie_player_open',
        screen: 'movie_player',
        movieId: movie.tmdbId?.toString() ?? '',
      );
  void movieListRefreshed() => track('movies_refresh', screen: 'movies');
}
