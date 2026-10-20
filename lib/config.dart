/// Movie-only app configuration. Optional external links can be supplied as
/// Dart defines in a release build rather than hard-coded into UI code.
class AppConfig {
  static const String appName = 'DamiMovies';
  static const String appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static const String appUrl = 'https://github.com/Deeprows/SB';

  static const String userAgent = String.fromEnvironment(
    'PLAYER_USER_AGENT',
    defaultValue:
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
  );
  static const String playerOrigin = String.fromEnvironment(
    'PLAYER_ORIGIN',
    defaultValue: 'https://vsembed.su',
  );
  static const String embedBase = String.fromEnvironment(
    'EMBED_BASE',
    defaultValue: 'https://vsembed.su/embed',
  );
  static const String altEmbedBase = String.fromEnvironment(
    'ALT_EMBED_BASE',
    defaultValue: 'https://web.nxsha.app/embed',
  );
  static const String downloadBase = String.fromEnvironment(
    'DOWNLOAD_BASE',
    defaultValue: 'https://web.nxsha.app/dl',
  );
  static const String replaceHostsCsv = String.fromEnvironment(
    'REPLACE_HOSTS',
    defaultValue: 'vsembed.ru,vsembed.su',
  );
  static List<String> get replaceHosts => replaceHostsCsv
      .split(',')
      .map((host) => host.trim().toLowerCase())
      .where((host) => host.isNotEmpty)
      .toList(growable: false);

  /// Optional integrations described in the upstream repo. Blank links disable
  /// the relevant external feature gracefully without affecting playback.
  /// Optional remote config address (same format as assets/data/app_config.json).
  /// Blank = the app only uses the bundled copy.
  /// Address of cloudflare/auth-worker.js. Blank = accounts are remembered on
  /// this phone only.
  static const String authUrl = String.fromEnvironment('AUTH_API_URL');

  /// Address of the server that stores the community (posts, likes, comments,
  /// profiles, Watch Together rooms). Pass it at build time with
  /// --dart-define=COMMUNITY_API_URL=... Blank = the Community screens say it
  /// is not set up yet. See COMMUNITY_SETUP.md.
  static const String communityUrl =
      String.fromEnvironment('COMMUNITY_API_URL');

  static const String configUrl = String.fromEnvironment(
    'CONFIG_URL',
    defaultValue: '',
  );

  static const String supportUrl =
      String.fromEnvironment('SUPPORT_URL', defaultValue: '');
  static const String updateUrl =
      String.fromEnvironment('UPDATE_URL', defaultValue: '');
  static const String noticeUrl =
      String.fromEnvironment('NOTICE_URL', defaultValue: '');
}
