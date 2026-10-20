/// Classifies a source as a direct media stream or a provider-hosted embed.
/// Direct HLS, DASH and video URLs use Flutter's native video_player/ExoPlayer.
/// Provider embed pages remain in WebView because their actual stream URL is
/// hidden behind the provider's own player and authorization flow.
enum StreamKind { hls, dash, video, embed, invalid }

class ResolvedStream {
  final String url;
  final StreamKind kind;
  const ResolvedStream(this.url, this.kind);

  /// Direct media formats can be played directly by Flutter/Android ExoPlayer.
  bool get usesNativePlayer =>
      kind == StreamKind.hls ||
      kind == StreamKind.dash ||
      kind == StreamKind.video;

  String get label {
    switch (kind) {
      case StreamKind.hls:
        return 'Native HLS · m3u8';
      case StreamKind.dash:
        return 'Native DASH · mpd';
      case StreamKind.video:
        return 'Native video';
      case StreamKind.embed:
        return 'Web embed';
      case StreamKind.invalid:
        return 'Unknown';
    }
  }
}

class StreamResolver {
  static final _mediaExt = RegExp(
    r'\.(mp4|m4v|webm|mov|ogv|ogg|mkv|mp3|aac|m4a)(\?|#|$)',
    caseSensitive: false,
  );
  static final _http = RegExp(r'^https?://', caseSensitive: false);

  static ResolvedStream resolve(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const ResolvedStream('', StreamKind.invalid);
    final s = trimmed.split(RegExp(r'\s+')).first;

    var candidate = _extractInner(s) ?? s;
    if (candidate.startsWith('//')) candidate = 'https:$candidate';
    if (!_http.hasMatch(candidate)) {
      return ResolvedStream(candidate, StreamKind.invalid);
    }
    return ResolvedStream(candidate, _kindOf(candidate));
  }

  static StreamKind _kindOf(String url) {
    final l = url.toLowerCase();
    if (l.contains('.m3u8')) return StreamKind.hls;
    if (l.contains('.mpd')) return StreamKind.dash;
    if (_mediaExt.hasMatch(l)) return StreamKind.video;
    return StreamKind.embed;
  }

  /// Handles wrapper links such as
  ///   hls-player/player.html#https://host/live.m3u8
  ///   https://some-player/?url=https%3A%2F%2Fhost%2Flive.m3u8
  static String? _extractInner(String s) {
    final hash = s.indexOf('#');
    if (hash >= 0 && hash < s.length - 1) {
      var frag = s.substring(hash + 1);
      if (RegExp(r'^https?%3A', caseSensitive: false).hasMatch(frag)) {
        try {
          frag = Uri.decodeComponent(frag);
        } catch (_) {}
      }
      if (_http.hasMatch(frag)) return frag;
    }
    final uri = Uri.tryParse(s);
    if (uri != null && uri.hasQuery) {
      for (final k in ['url', 'src', 'file', 'source', 'stream']) {
        final v = uri.queryParameters[k];
        if (v != null && _http.hasMatch(v) && _kindOf(v) != StreamKind.embed) {
          return v;
        }
      }
    }
    return null;
  }
}
