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

class RemovePlan {
  final int days;
  final double usd;
  const RemovePlan(this.days, this.usd);
}

/// "removeAds" block of app_config.json: token-based ad removal.
class RemoveAdsConfig {
  final bool enabled;
  final String whatsapp; // digits with country code, e.g. 2348012345678
  final String publicKey; // base64url Ed25519 public key made by tool/token-admin.html
  final List<RemovePlan> plans;
  final Map<String, Map<String, double>> localPrices; // {"NGN": {"30": 1500}}

  const RemoveAdsConfig({
    this.enabled = true,
    this.whatsapp = '',
    this.publicKey = '',
    this.plans = const [RemovePlan(7, 0.5), RemovePlan(30, 1.5), RemovePlan(90, 4)],
    this.localPrices = const {},
  });

  factory RemoveAdsConfig.fromJson(Object? raw) {
    if (raw is! Map) return const RemoveAdsConfig();
    final plans = <RemovePlan>[];
    final rawPlans = raw['plans'];
    if (rawPlans is List) {
      for (final item in rawPlans) {
        if (item is! Map) continue;
        final days = item['days'] is num ? (item['days'] as num).toInt() : int.tryParse('${item['days']}');
        final usd = item['usd'] is num ? (item['usd'] as num).toDouble() : double.tryParse('${item['usd']}');
        if (days != null && days > 0 && usd != null && usd > 0) plans.add(RemovePlan(days, usd));
      }
    }
    final local = <String, Map<String, double>>{};
    final rawLocal = raw['localPrices'];
    if (rawLocal is Map) {
      rawLocal.forEach((code, value) {
        if (value is! Map) return;
        final inner = <String, double>{};
        value.forEach((days, amount) {
          final n = amount is num ? amount.toDouble() : double.tryParse('$amount');
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

class RemoteConfig extends ChangeNotifier {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  static const _kCache = 'damimovies_remote_config';

  AdsConfig _ads = const AdsConfig();
  AdsConfig get ads => _ads;
  RemoveAdsConfig _removeAds = const RemoveAdsConfig();
  RemoveAdsConfig get removeAds => _removeAds;

  void _apply(String text) {
    final data = jsonDecode(text);
    if (data is Map) {
      _ads = AdsConfig.fromJson(data['ads']);
      _removeAds = RemoveAdsConfig.fromJson(data['removeAds']);
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
