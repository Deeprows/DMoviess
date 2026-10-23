import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// A configurable playback provider. Only enabled, valid providers are shown.
/// Add as many providers as you need in assets/data/player_urls.json.
class PlayerProvider {
  const PlayerProvider({
    required this.id,
    required this.name,
    required this.movie,
    required this.tv,
    this.enabled = true,
    this.idType = 'auto',
    this.blockHeaderActions = false,
    this.referer = '',
    this.userAgent = '',
  });

  final String id;
  final String name;
  final String movie;
  final String tv;
  final bool enabled;
  /// auto: ID detected from the original URL; tmdb: numeric ID; imdb: tt ID.
  final String idType;
  /// Useful for third-party players with unwanted clickable header actions.
  final bool blockHeaderActions;
  final String referer;
  final String userAgent;

  String? urlFor({
    required bool isTv,
    required String? detectedId,
    required String? tmdbId,
    required String? imdbId,
    String season = '1',
    String episode = '1',
  }) {
    final id = switch (idType) {
      'tmdb' => tmdbId,
      'imdb' => imdbId,
      _ => detectedId ?? tmdbId,
    };
    if (id == null || id.isEmpty) return null;
    final template = isTv ? tv : movie;
    if (template.isEmpty) return null;
    return template
        .replaceAll('{id}', Uri.encodeComponent(id))
        .replaceAll('{season}', Uri.encodeComponent(season))
        .replaceAll('{episode}', Uri.encodeComponent(episode));
  }
}

/// Remote, ordered provider list. Works with the new `players` array and with
/// the older `primary` / `secondary` JSON object format.
class PlayerUrlsConfig {
  const PlayerUrlsConfig({required this.players});

  final List<PlayerProvider> players;

  static const defaults = PlayerUrlsConfig(players: [
    PlayerProvider(
      id: 'primary',
      name: 'Player 1',
      movie: '${AppConfig.embedBase}/movie/{id}',
      tv: '${AppConfig.embedBase}/tv/{id}',
    ),
    PlayerProvider(
      id: 'secondary',
      name: 'Player 2',
      movie: '${AppConfig.altEmbedBase}/movie/{id}',
      tv: '${AppConfig.altEmbedBase}/tv/{id}/{season}/{episode}',
      blockHeaderActions: true,
    ),
  ]);

  static const String remoteJsonUrl = String.fromEnvironment(
    'PLAYER_URLS_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Deeprows/DMoviess/main/assets/data/player_urls.json',
  );

  static PlayerUrlsConfig _cached = defaults;
  static DateTime? _lastChecked;
  static Future<PlayerUrlsConfig>? _pending;

  /// Check at most once every five minutes per running app session.
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
      // Keep the last working configuration if the network or JSON fails.
    }
    return _cached;
  }

  static bool _valid(String value) {
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        value.contains('{id}');
  }

  static PlayerProvider? _parseProvider(Map<dynamic, dynamic> data, int index) {
    if (data['enabled'] == false) return null;
    final movie = (data['movie'] ?? '').toString().trim();
    final tv = (data['tv'] ?? '').toString().trim();
    // A provider is valid when at least one media type has a usable URL.
    if (!_valid(movie) && !_valid(tv)) return null;
    final rawId = (data['id'] ?? 'player_${index + 1}').toString().trim();
    final id = rawId.isEmpty ? 'player_${index + 1}' : rawId;
    final rawName = (data['name'] ?? '').toString().trim();
    final rawType = (data['idType'] ?? 'auto').toString().trim().toLowerCase();
    return PlayerProvider(
      id: id,
      name: rawName.isEmpty ? 'Player ${index + 1}' : rawName,
      movie: _valid(movie) ? movie : '',
      tv: _valid(tv) ? tv : '',
      idType: {'auto', 'tmdb', 'imdb'}.contains(rawType) ? rawType : 'auto',
      blockHeaderActions: data['blockHeaderActions'] == true,
      referer: (data['referer'] ?? '').toString().trim(),
      userAgent: (data['userAgent'] ?? '').toString().trim(),
    );
  }

  factory PlayerUrlsConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['players'];
    if (raw is List) {
      final output = <PlayerProvider>[];
      final used = <String>{};
      for (var i = 0; i < raw.length; i++) {
        final entry = raw[i];
        if (entry is! Map) continue;
        final p = _parseProvider(entry, i);
        if (p != null && used.add(p.id)) output.add(p);
      }
      // An invalid or accidentally empty provider list shouldn't brick playback.
      return output.isEmpty ? defaults : PlayerUrlsConfig(players: output);
    }

    // Backwards compatibility with the original two-player JSON format.
    final primary = json['primary'];
    final secondary = json['secondary'];
    if (primary is! Map || secondary is! Map) return defaults;
    String template(Object? value, String fallback) {
      final candidate = (value ?? '').toString().trim();
      return _valid(candidate) ? candidate : fallback;
    }
    return PlayerUrlsConfig(players: [
      PlayerProvider(
        id: 'primary',
        name: 'Player 1',
        movie: template(primary['movie'], defaults.players[0].movie),
        tv: template(primary['tv'], defaults.players[0].tv),
      ),
      PlayerProvider(
        id: 'secondary',
        name: 'Player 2',
        movie: template(secondary['movie'], defaults.players[1].movie),
        tv: template(secondary['tv'], defaults.players[1].tv),
        blockHeaderActions: true,
      ),
    ]);
  }
}
