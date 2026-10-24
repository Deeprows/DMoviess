import 'dart:convert';

import 'package:http/http.dart' as http;

/// Independently configurable download destination templates.
/// Changes to the GitHub JSON are picked up without an APK update.
class DownloadUrlsConfig {
  const DownloadUrlsConfig({
    required this.enabled,
    required this.movie,
    required this.tv,
  });

  final bool enabled;
  final String movie;
  final String tv;

  static const defaults = DownloadUrlsConfig(
    enabled: true,
    movie: 'https://web.nxsha.app/dl/movie/{id}',
    tv: 'https://web.nxsha.app/dl/tv/{id}/{season}/{episode}',
  );

  static const remoteUrl = String.fromEnvironment(
    'DOWNLOAD_URLS_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Deeprows/DMoviess/main/assets/data/download_urls.json',
  );

  static DownloadUrlsConfig _cached = defaults;
  static DateTime? _lastChecked;
  static Future<DownloadUrlsConfig>? _pending;

  static bool _validTemplate(String value, {required bool tv}) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        !value.contains('{id}')) return false;
    return !tv || (value.contains('{season}') && value.contains('{episode}'));
  }

  static DownloadUrlsConfig _parse(Object? data) {
    if (data is! Map) return _cached;
    final movie = (data['movie'] ?? '').toString().trim();
    final tv = (data['tv'] ?? '').toString().trim();
    return DownloadUrlsConfig(
      enabled: data['enabled'] != false,
      movie: _validTemplate(movie, tv: false) ? movie : '',
      tv: _validTemplate(tv, tv: true) ? tv : '',
    );
  }

  static Future<DownloadUrlsConfig> load() {
    if (_lastChecked != null &&
        DateTime.now().difference(_lastChecked!) < const Duration(minutes: 5)) {
      return Future.value(_cached);
    }
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  static Future<DownloadUrlsConfig> _fetch() async {
    _lastChecked = DateTime.now();
    try {
      final uri = Uri.parse(remoteUrl);
      if (uri.scheme != 'https') return _cached;
      final fresh = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'v': '${DateTime.now().millisecondsSinceEpoch}',
      });
      final result = await http.get(fresh).timeout(const Duration(seconds: 5));
      if (result.statusCode == 200) {
        _cached = _parse(jsonDecode(utf8.decode(result.bodyBytes)));
      }
    } catch (_) {
      // Keep the last valid settings (or the built-in defaults) offline.
    }
    return _cached;
  }

  /// Only use a positive numeric TMDB ID; don't mistake episode IDs for show IDs.
  String? urlFor({
    required int? tmdbId,
    int? season,
    int? episode,
  }) {
    if (!enabled || tmdbId == null || tmdbId <= 0) return null;
    final isTv = season != null || episode != null;
    if (isTv && (season == null || season < 0 || episode == null || episode <= 0)) {
      return null;
    }
    final template = isTv ? tv : movie;
    if (!_validTemplate(template, tv: isTv)) return null;
    final link = template
        .replaceAll('{id}', '$tmdbId')
        .replaceAll('{season}', '${season ?? 1}')
        .replaceAll('{episode}', '${episode ?? 1}');
    final uri = Uri.tryParse(link);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? link : null;
  }
}
