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
  final int intervalMinutes; // timer ad: every N minutes of use (YouTube style)
  final int cardCooldownMinutes; // card-tap ad: at most once per N minutes
  final int skipAfterSeconds;

  const AdsConfig({
    this.enabled = true,
    this.supportUrl = '',
    this.intervalMinutes = 15,
    this.cardCooldownMinutes = 5,
    this.skipAfterSeconds = 6,
  });

  bool get hasAd =>
      enabled &&
      (supportUrl.startsWith('http://') || supportUrl.startsWith('https://'));

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
      intervalMinutes: number(raw['intervalMinutes'], 15, 1, 24 * 60),
      cardCooldownMinutes: number(raw['cardCooldownMinutes'], 5, 0, 24 * 60),
      skipAfterSeconds: number(raw['skipAfterSeconds'], 6, 0, 60),
    );
  }
}

class RemovePlan {
  final int days;
  final double usd;
  const RemovePlan(this.days, this.usd);
}

/// "removeAds" block of app_config.json: token-based ad removal.
class RemoveAdsConfig {
  final bool enabled;
  final String whatsapp; // digits with country code, e.g. 2348012345678
  final String
      publicKey; // base64url Ed25519 public key made by tool/token-admin.html
  final List<RemovePlan> plans;
  final Map<String, Map<String, double>> localPrices; // {"NGN": {"30": 1500}}

  const RemoveAdsConfig({
    this.enabled = true,
    this.whatsapp = '',
    this.publicKey = '',
    this.plans = const [
      RemovePlan(7, 0.5),
      RemovePlan(30, 1.5),
      RemovePlan(90, 4)
    ],
    this.localPrices = const {},
  });

  factory RemoveAdsConfig.fromJson(Object? raw) {
    if (raw is! Map) return const RemoveAdsConfig();
    final plans = <RemovePlan>[];
    final rawPlans = raw['plans'];
    if (rawPlans is List) {
      for (final item in rawPlans) {
        if (item is! Map) continue;
        final days = item['days'] is num
            ? (item['days'] as num).toInt()
            : int.tryParse('${item['days']}');
        final usd = item['usd'] is num
            ? (item['usd'] as num).toDouble()
            : double.tryParse('${item['usd']}');
        if (days != null && days > 0 && usd != null && usd > 0)
          plans.add(RemovePlan(days, usd));
      }
    }
    final local = <String, Map<String, double>>{};
    final rawLocal = raw['localPrices'];
    if (rawLocal is Map) {
      rawLocal.forEach((code, value) {
        if (value is! Map) return;
        final inner = <String, double>{};
        value.forEach((days, amount) {
          final n =
              amount is num ? amount.toDouble() : double.tryParse('$amount');
          if (n != null && n > 0) inner['$days'] = n;
        });
        if (inner.isNotEmpty) local['$code'.toUpperCase()] = inner;
      });
    }
    return RemoveAdsConfig(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      whatsapp: ('${raw['whatsapp'] ?? ''}').replaceAll(RegExp(r'[^0-9]'), ''),
      publicKey: ('${raw['publicKey'] ?? ''}').trim(),
      plans: plans.isEmpty ? const RemoveAdsConfig().plans : plans,
      localPrices: local,
    );
  }
}

/// "notice" block of app_config.json: a message shown once to every user.
/// Change "id" to send a new one; set "enabled" to false to stop showing it.
class NoticeConfig {
  final bool enabled;
  final String id;
  final String title;
  final String message;
  final String buttonText;
  final String buttonUrl;
  final bool dismissible;
  final DateTime? expires;

  const NoticeConfig({
    this.enabled = false,
    this.id = '',
    this.title = '',
    this.message = '',
    this.buttonText = '',
    this.buttonUrl = '',
    this.dismissible = true,
    this.expires,
  });

  bool get hasButton =>
      buttonText.isNotEmpty &&
      (buttonUrl.startsWith('http://') || buttonUrl.startsWith('https://'));

  /// True when this notice should be shown to users right now.
  bool get active =>
      enabled &&
      id.isNotEmpty &&
      message.isNotEmpty &&
      (expires == null || DateTime.now().isBefore(expires!));

  factory NoticeConfig.fromJson(Object? raw) {
    if (raw is! Map) return const NoticeConfig();
    String text(Object? v) => '${v ?? ''}'.trim();
    return NoticeConfig(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : false,
      id: text(raw['id']),
      title: text(raw['title']),
      message: text(raw['message'] ?? raw['body'] ?? raw['text']),
      buttonText: text(raw['buttonText']),
      buttonUrl: text(raw['buttonUrl']),
      dismissible: raw['dismissible'] is bool ? raw['dismissible'] as bool : true,
      expires: DateTime.tryParse(text(raw['expires'])),
    );
  }
}

class RemoteConfig extends ChangeNotifier {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  static const _kCache = 'damimovies_remote_config';

  AdsConfig _ads = const AdsConfig();
  AdsConfig get ads => _ads;
  RemoveAdsConfig _removeAds = const RemoveAdsConfig();
  RemoveAdsConfig get removeAds => _removeAds;
  NoticeConfig _notice = const NoticeConfig();
  NoticeConfig get notice => _notice;

  void _apply(String text) {
    final data = jsonDecode(text);
    if (data is Map) {
      _ads = AdsConfig.fromJson(data['ads']);
      _removeAds = RemoveAdsConfig.fromJson(data['removeAds']);
      _notice = NoticeConfig.fromJson(data['notice']);
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
      final response = await http
          .get(Uri.parse(AppConfig.configUrl))
          .timeout(const Duration(seconds: 8));
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
