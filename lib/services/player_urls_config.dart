import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Two editable playback URL templates, fetched from a public JSON file.
/// Edit assets/data/player_urls.json in GitHub to change the providers
/// without rebuilding the APK. If the request fails, current defaults work.
class PlayerUrlsConfig {
  const PlayerUrlsConfig({
    required this.primaryMovie,
    required this.primaryTv,
    required this.secondaryMovie,
    required this.secondaryTv,
  });

  final String primaryMovie;
  final String primaryTv;
  final String secondaryMovie;
  final String secondaryTv;

  static const defaults = PlayerUrlsConfig(
    primaryMovie: '${AppConfig.embedBase}/movie/{id}',
    primaryTv: '${AppConfig.embedBase}/tv/{id}',
    secondaryMovie: '${AppConfig.altEmbedBase}/movie/{id}',
    secondaryTv: '${AppConfig.altEmbedBase}/tv/{id}/{season}/{episode}',
  );

  /// You can override this at build time with --dart-define=PLAYER_URLS_URL=...
  /// The default is the raw file in your public DMoviess GitHub repository.
  static const String remoteJsonUrl = String.fromEnvironment(
    'PLAYER_URLS_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Deeprows/DMoviess/main/assets/data/player_urls.json',
  );

  static PlayerUrlsConfig _cached = defaults;
  static DateTime? _lastChecked;
  static Future<PlayerUrlsConfig>? _pending;

  /// Check at most once every five minutes during a running app session.
  static Future<PlayerUrlsConfig> load() {
    if (_lastChecked != null &&
        DateTime.now().difference(_lastChecked!) < const Duration(minutes: 5)) {
      return Future.value(_cached);
    }
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  static Future<PlayerUrlsConfig> _fetch() async {
    _lastChecked = DateTime.now();
    final uri = Uri.tryParse(remoteJsonUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return _cached;
    }

    try {
      // The query parameter prevents an out-of-date cached GitHub response.
      final freshUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'updated': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await http.get(freshUri).timeout(
            const Duration(seconds: 4),
          );
      if (response.statusCode != 200) return _cached;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return _cached;
      _cached = PlayerUrlsConfig.fromJson(decoded);
    } catch (_) {
      // Keep previously fetched settings, or the built-in default URLs.
    }
    return _cached;
  }

  factory PlayerUrlsConfig.fromJson(Map<String, dynamic> json) {
    final primary = json['primary'];
    final secondary = json['secondary'];
    if (primary is! Map || secondary is! Map) return defaults;

    String validTemplate(Object? value, String fallback) {
      final candidate = (value ?? '').toString().trim();
      final uri = Uri.tryParse(candidate);
      // Ignore missing/broken entries rather than disabling every player.
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          !candidate.contains('{id}')) {
        return fallback;
      }
      return candidate;
    }

    return PlayerUrlsConfig(
      primaryMovie: validTemplate(primary['movie'], defaults.primaryMovie),
      primaryTv: validTemplate(primary['tv'], defaults.primaryTv),
      secondaryMovie:
          validTemplate(secondary['movie'], defaults.secondaryMovie),
      secondaryTv: validTemplate(secondary['tv'], defaults.secondaryTv),
    );
  }

  String urlFor({
    required bool primary,
    required bool isTv,
    required String id,
    String season = '1',
    String episode = '1',
  }) {
    final template = primary
        ? (isTv ? primaryTv : primaryMovie)
        : (isTv ? secondaryTv : secondaryMovie);
    return template
        .replaceAll('{id}', Uri.encodeComponent(id))
        .replaceAll('{season}', Uri.encodeComponent(season))
        .replaceAll('{episode}', Uri.encodeComponent(episode));
  }
}
