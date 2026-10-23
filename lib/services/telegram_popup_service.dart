import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Remote-controlled promo, separate from app_config.json.
/// Changes to assets/data/telegram_popup.json on GitHub are picked up on the
/// next app visit, provided the installed APK includes this feature.
class TelegramPopupConfig {
  const TelegramPopupConfig({
    required this.enabled,
    required this.campaignId,
    required this.frequency,
    required this.delaySeconds,
    required this.title,
    required this.highlight,
    required this.subtitle,
    required this.buttonText,
    required this.telegramUrl,
    required this.imageUrl,
  });

  final bool enabled;
  final String campaignId;
  final String frequency; // once | daily | every_launch
  final int delaySeconds;
  final String title;
  final String highlight;
  final String subtitle;
  final String buttonText;
  final String telegramUrl;
  final String imageUrl;

  bool get active {
    final link = Uri.tryParse(telegramUrl);
    return enabled &&
        campaignId.isNotEmpty &&
        link != null &&
        link.scheme == 'https' &&
        (link.host == 't.me' || link.host == 'telegram.me');
  }

  factory TelegramPopupConfig.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Not a config object');
    String stringValue(String key, String fallback) =>
        (raw[key] is String ? (raw[key] as String).trim() : fallback);
    final seconds = raw['delaySeconds'] is num
        ? (raw['delaySeconds'] as num).toInt()
        : int.tryParse('${raw['delaySeconds'] ?? ''}') ?? 2;
    final frequency = stringValue('frequency', 'once').toLowerCase();
    return TelegramPopupConfig(
      enabled: raw['enabled'] == true,
      campaignId: stringValue('campaignId', ''),
      frequency: const ['once', 'daily', 'every_launch'].contains(frequency)
          ? frequency
          : 'once',
      delaySeconds: seconds.clamp(0, 30).toInt(),
      title: stringValue('title', 'JOIN OUR'),
      highlight: stringValue('highlight', 'TELEGRAM CHANNEL'),
      subtitle: stringValue('subtitle', ''),
      buttonText: stringValue('buttonText', 'JOIN CHANNEL'),
      telegramUrl: stringValue('telegramUrl', ''),
      imageUrl: stringValue('imageUrl', ''),
    );
  }
}

class TelegramPopupService {
  TelegramPopupService._();

  static const remoteUrl =
      'https://raw.githubusercontent.com/Deeprows/DMoviess/main/assets/data/telegram_popup.json';
  static const _cacheKey = 'damimovies_telegram_popup_last_valid_json';
  static const _seenPrefix = 'damimovies_telegram_popup_seen_';

  /// Bundled default -> last cached config -> fresh GitHub JSON.
  /// A network failure does not prevent the app homepage from opening.
  static Future<TelegramPopupConfig?> load() async {
    TelegramPopupConfig? config;
    try {
      config = TelegramPopupConfig.fromJson(jsonDecode(
        await rootBundle.loadString('assets/data/telegram_popup.json'),
      ));
    } catch (error) {
      debugPrint('Telegram promo bundled config: $error');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        config = TelegramPopupConfig.fromJson(jsonDecode(cached));
      }
    } catch (_) {}
    try {
      final uri = Uri.parse(remoteUrl).replace(
        queryParameters: {'v': '${DateTime.now().millisecondsSinceEpoch}'},
      );
      final response = await http.get(uri, headers: {
        'Cache-Control': 'no-cache',
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final fresh = TelegramPopupConfig.fromJson(jsonDecode(body));
        config = fresh;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, body);
      }
    } catch (error) {
      debugPrint('Telegram promo remote config: $error');
    }
    return config;
  }

  static String _seenKey(TelegramPopupConfig config) =>
      '$_seenPrefix${config.campaignId}';

  static Future<bool> shouldShow(TelegramPopupConfig config) async {
    if (!config.active) return false;
    if (config.frequency == 'every_launch') return true;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString(_seenKey(config));
    if (config.frequency == 'daily') {
      final now = DateTime.now();
      final date = '${now.year}-${now.month}-${now.day}';
      return seen != date;
    }
    return seen != 'done';
  }

  /// Mark only after the popup is closed, never merely because it was fetched.
  static Future<void> markSeen(TelegramPopupConfig config) async {
    if (config.frequency == 'every_launch') return;
    final prefs = await SharedPreferences.getInstance();
    if (config.frequency == 'daily') {
      final now = DateTime.now();
      await prefs.setString(
        _seenKey(config), '${now.year}-${now.month}-${now.day}',
      );
    } else {
      await prefs.setString(_seenKey(config), 'done');
    }
  }
}
