import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'app_remote_config.dart';
import 'auth_service.dart';

class RedeemResult {
  final bool ok;
  final String message;
  final int days;
  const RedeemResult(this.ok, this.message, [this.days = 0]);
}

/// Ad-free time bought with a token. Tokens are signed by you (tool/token-admin.html)
/// for one phone's Device ID and checked offline against the public key in
/// app_config.json, so the APK never contains tokens or a signing secret.
class PremiumService extends ChangeNotifier {
  PremiumService._();
  static final PremiumService instance = PremiumService._();

  static const _kId = 'damimovies_install_id';
  static const _kUntil = 'damimovies_adfree_until';
  static const _kUsed = 'damimovies_tokens_used';
  static const _kSeen = 'damimovies_last_seen';
  static const int _day = 86400000;

  String _installId = '';
  int _untilMs = 0;
  int _lastSeenMs = 0;
  final Set<String> _used = {};

  String get installId => _installId;

  /// Never trust a clock that was moved backwards.
  int get _nowMs {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > _lastSeenMs ? now : _lastSeenMs;
  }

  bool get active => _untilMs > _nowMs;
  DateTime? get until => active ? DateTime.fromMillisecondsSinceEpoch(_untilMs) : null;
  int get daysLeft => active ? ((_untilMs - _nowMs) / _day).ceil() : 0;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _installId = prefs.getString(_kId) ?? '';
      if (_installId.isEmpty) {
        final random = Random.secure();
        final bytes = List<int>.generate(6, (_) => random.nextInt(256));
        final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
        _installId = '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
        await prefs.setString(_kId, _installId);
      }
      _untilMs = prefs.getInt(_kUntil) ?? 0;
      _lastSeenMs = prefs.getInt(_kSeen) ?? 0;
      _used
        ..clear()
        ..addAll(prefs.getStringList(_kUsed) ?? const []);
      await touch();
    } catch (error) {
      debugPrint('DamiMovies: premium state not loaded: $error');
    }
    notifyListeners();
  }

  /// Remember the latest time we have seen (used to catch clock rollbacks).
  Future<void> touch() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > _lastSeenMs) _lastSeenMs = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSeen, _lastSeenMs);
    } catch (_) {}
  }

  String _normId(String id) => id.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  List<int>? _b64(String value) {
    try {
      return base64Url.decode(base64Url.normalize(value.trim()));
    } catch (_) {
      return null;
    }
  }

  /// Sends the customer's WhatsApp number to the worker, which notifies you.
  Future<RedeemResult> requestToken({
    required String whatsapp,
    required RemovePlan plan,
    required String priceText,
  }) async {
    if (!AppConfig.authUrl.startsWith('http')) {
      return const RedeemResult(false, 'Token requests are not set up yet. Please contact support.');
    }
    final digits = whatsapp.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      return const RedeemResult(false, 'Start with your country code, not 0. Example: 2348012345678');
    }
    if (digits.length < 8 || digits.length > 15) {
      return const RedeemResult(false, 'Enter a valid WhatsApp number with country code.');
    }
    final idToken = await AuthService.instance.freshIdToken();
    if (idToken == null) {
      return const RedeemResult(false, 'Please sign out and sign in again, then retry.');
    }
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.authUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'token_request',
              'idToken': idToken,
              'whatsapp': digits,
              'days': plan.days,
              'price': priceText,
              'deviceId': _installId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return RedeemResult(true, 'Request sent. We will send your token to +$digits on WhatsApp.');
      }
      if (response.statusCode == 429) {
        return const RedeemResult(false, 'Too many requests today. Please try again tomorrow.');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const RedeemResult(false, 'Please sign out and sign in again, then retry.');
      }
      return const RedeemResult(false, 'Could not send your request. Please try again.');
    } catch (_) {
      return const RedeemResult(false, 'Could not reach the server. Check your internet and try again.');
    }
  }

  Future<RedeemResult> redeem(String input) async {
    final publicKey = RemoteConfig.instance.removeAds.publicKey;
    if (publicKey.isEmpty) {
      return const RedeemResult(false, 'Ad removal is not set up yet. Please contact support.');
    }
    final token = input.replaceAll(RegExp(r'\s'), '');
    final parts = token.split('.');
    if (parts.length != 2) return const RedeemResult(false, 'That token is not valid.');
    final payloadBytes = _b64(parts[0]);
    final sigBytes = _b64(parts[1]);
    final keyBytes = _b64(publicKey);
    if (payloadBytes == null || sigBytes == null || keyBytes == null) {
      return const RedeemResult(false, 'That token is not valid.');
    }
    try {
      final ok = await Ed25519().verify(
        payloadBytes,
        signature: Signature(sigBytes, publicKey: SimplePublicKey(keyBytes, type: KeyPairType.ed25519)),
      );
      if (!ok) return const RedeemResult(false, 'That token is not valid.');
    } catch (_) {
      return const RedeemResult(false, 'That token is not valid.');
    }
    final fields = utf8.decode(payloadBytes, allowMalformed: true).split('|');
    if (fields.length != 4 || fields[0] != 'v1') return const RedeemResult(false, 'That token is not valid.');
    if (_normId(fields[1]) != _normId(_installId)) {
      return const RedeemResult(false, 'This token was made for a different phone.');
    }
    final days = int.tryParse(fields[2]) ?? 0;
    if (days < 1 || days > 3650) return const RedeemResult(false, 'That token is not valid.');
    final nonce = fields[3];
    if (_used.contains(nonce)) return const RedeemResult(false, 'This token has already been used.');

    final now = _nowMs;
    final base = _untilMs > now ? _untilMs : now;
    _untilMs = base + days * _day;
    _used.add(nonce);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kUntil, _untilMs);
      await prefs.setStringList(_kUsed, _used.toList());
    } catch (_) {}
    notifyListeners();
    return RedeemResult(true, 'Ads removed for $days days.', days);
  }
}
