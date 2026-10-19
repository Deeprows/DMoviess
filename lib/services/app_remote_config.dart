import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// "ads" block of app_config.json (same fields as the SB / Deeprowss apps).
class AdsConfig {
  final bool enabled;
  final String supportUrl;
  final int intervalMinutes;
  final int skipAfterSeconds;

  const AdsConfig({
    this.enabled = true,
    this.supportUrl = '',
    this.intervalMinutes = 10,
    this.skipAfterSeconds = 6,
  });

  bool get hasAd => enabled && (supportUrl.startsWith('http://') || supportUrl.startsWith('https://'));

  /// A key that is missing falls back to the built-in default, so a bad edit
  /// can never break the app.
  factory AdsConfig.fromJson(Object? raw) {
    if (raw is! Map) return const AdsConfig();
    int number(Object? v, int fallback, int min, int max) {
      final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
      return (n ?? fallback).clamp(min, max).toInt();
    }
    return AdsConfig(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      supportUrl: ('${raw['supportUrl'] ?? ''}').trim(),
      intervalMinutes: number(raw['intervalMinutes'], 10, 1, 24 * 60),
      skipAfterSeconds: number(raw['skipAfterSeconds'], 6, 0, 60),
    );
  }
}

class RemoteConfig extends ChangeNotifier {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  static const _kCache = 'damimovies_remote_config';

  AdsConfig _ads = const AdsConfig();
  AdsConfig get ads => _ads;

  void _apply(String text) {
    final data = jsonDecode(text);
    if (data is Map) {
      _ads = AdsConfig.fromJson(data['ads']);
      notifyListeners();
    }
  }

  /// Bundled copy first, then the last saved copy, then refresh from GitHub.
  Future<void> load() async {
    try {
      _apply(await rootBundle.loadString('assets/data/app_config.json'));
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_kCache);
      if (cached != null && cached.isNotEmpty) _apply(cached);
    } catch (_) {}
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!AppConfig.configUrl.startsWith('http')) return;
    try {
      final response = await http.get(Uri.parse(AppConfig.configUrl)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final body = utf8.decode(response.bodyBytes);
      _apply(body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCache, body);
    } catch (error) {
      debugPrint('DamiMovies: remote config not refreshed: $error');
    }
  }
}
