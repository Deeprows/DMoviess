import 'dart:async';
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

/// Ad-free time bought with a token. Tokens are signed by you (the worker's /admin page)
/// for one phone's Device ID and checked offline against the public key in
/// app_config.json, so the APK never contains tokens or a signing secret.
class PremiumService extends ChangeNotifier {
  PremiumService._() {
    AuthService.instance.addListener(() => unawaited(_refreshAccountId()));
  }
  static final PremiumService instance = PremiumService._();

  static const _kId = 'damimovies_install_id';
  static const _kUntil = 'damimovies_adfree_until';
  static const _kUsed = 'damimovies_tokens_used';
  static const _kSeen = 'damimovies_last_seen';
  static const int _day = 86400000;

  String _installId = ''; // legacy per-install ID (old tokens were made for it)
  String _accountId = ''; // static ID derived from the signed-in Gmail
  int _untilMs = 0;
  int _lastSeenMs = 0;
  final Set<String> _used = {};

  /// The Device ID shown to the user and put in token requests. It is derived from the
  /// signed-in Gmail address, so it is the same on every phone, after reinstalling, and
  /// after the app's data is cleared. Before sign-in it falls back to the old install ID.
  String get installId => _accountId.isNotEmpty ? _accountId : _installId;

  /// Never trust a clock that was moved backwards.
  int get _nowMs {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > _lastSeenMs ? now : _lastSeenMs;
  }

  bool get active => _untilMs > _nowMs;
  DateTime? get until =>
      active ? DateTime.fromMillisecondsSinceEpoch(_untilMs) : null;
  int get daysLeft => active ? ((_untilMs - _nowMs) / _day).ceil() : 0;

  Future<void>? _loading;

  /// Makes sure the Device ID exists. Safe to call from anywhere, any number of times.
  Future<void> ensureLoaded() {
    if (installId.isNotEmpty) return Future.value();
    return load();
  }

  String _formatId(List<int> bytes) {
    final hex = bytes
        .take(6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
  }

  String _newInstallId() {
    final random = Random.secure();
    return _formatId(List<int>.generate(6, (_) => random.nextInt(256)));
  }

  /// Must match accountId() in cloudflare/auth-worker.js exactly.
  String _normEmail(String email) {
    var e = email.trim().toLowerCase();
    if (e.endsWith('@googlemail.com'))
      e = '${e.substring(0, e.length - 15)}@gmail.com';
    return e;
  }

  Future<void> _refreshAccountId() async {
    final email = _normEmail(AuthService.instance.user?.email ?? '');
    var next = '';
    if (email.isNotEmpty) {
      final hash = await Sha256().hash(utf8.encode('damimovies|acct|$email'));
      next = _formatId(hash.bytes);
    }
    if (next != _accountId) {
      _accountId = next;
      notifyListeners();
    }
  }

  /// Loads the saved state. Concurrent calls share one run.
  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('DamiMovies: premium storage not readable: $error');
    }
    // A saved legacy ID is never overwritten (tokens made before this update used it).
    var stored = '';
    try {
      stored = prefs?.getString(_kId) ?? '';
    } catch (_) {}
    if (stored.isNotEmpty) {
      _installId = stored;
    } else {
      _installId = _newInstallId();
      try {
        await prefs?.setString(_kId, _installId);
      } catch (_) {}
    }
    try {
      _untilMs = prefs?.getInt(_kUntil) ?? 0;
      _lastSeenMs = prefs?.getInt(_kSeen) ?? 0;
      _used
        ..clear()
        ..addAll(prefs?.getStringList(_kUsed) ?? []);
      await touch();
    } catch (error) {
      debugPrint('DamiMovies: premium state not loaded: $error');
    }
    await _refreshAccountId();
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

  String _normId(String id) =>
      id.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

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
      return const RedeemResult(
          false, 'Token requests are not set up yet. Please contact support.');
    }
    final digits = whatsapp.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      return const RedeemResult(
          false, 'Start with your country code, not 0. Example: 2348012345678');
    }
    if (digits.length < 8 || digits.length > 15) {
      return const RedeemResult(
          false, 'Enter a valid WhatsApp number with country code.');
    }
    await ensureLoaded();
    await _refreshAccountId();
    if (_accountId.isEmpty) {
      return const RedeemResult(false, 'Please sign in with Gmail first.');
    }
    final idToken = await AuthService.instance.freshIdToken();
    if (idToken == null) {
      return const RedeemResult(
          false, 'Please sign out and sign in again, then retry.');
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
              'deviceId': installId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return RedeemResult(true,
            'Request sent. We will send your token to +$digits on WhatsApp.');
      }
      if (response.statusCode == 429) {
        return const RedeemResult(
            false, 'Too many requests today. Please try again tomorrow.');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const RedeemResult(
            false, 'Please sign out and sign in again, then retry.');
      }
      return const RedeemResult(
          false, 'Could not send your request. Please try again.');
    } catch (_) {
      return const RedeemResult(false,
          'Could not reach the server. Check your internet and try again.');
    }
  }

  Future<RedeemResult> redeem(String input) async {
    await ensureLoaded();
    await _refreshAccountId();
    final publicKey = RemoteConfig.instance.removeAds.publicKey;
    if (publicKey.isEmpty) {
      return const RedeemResult(
          false, 'Ad removal is not set up yet. Please contact support.');
    }
    final token = input.replaceAll(RegExp(r'\s'), '');
    final parts = token.split('.');
    if (parts.length != 2)
      return const RedeemResult(false, 'That token is not valid.');
    final payloadBytes = _b64(parts[0]);
    final sigBytes = _b64(parts[1]);
    final keyBytes = _b64(publicKey);
    if (payloadBytes == null || sigBytes == null || keyBytes == null) {
      return const RedeemResult(false, 'That token is not valid.');
    }
    try {
      final ok = await Ed25519().verify(
        payloadBytes,
        signature: Signature(sigBytes,
            publicKey: SimplePublicKey(keyBytes, type: KeyPairType.ed25519)),
      );
      if (!ok) return const RedeemResult(false, 'That token is not valid.');
    } catch (_) {
      return const RedeemResult(false, 'That token is not valid.');
    }
    final fields = utf8.decode(payloadBytes, allowMalformed: true).split('|');
    if (fields.length != 4 || fields[0] != 'v1')
      return const RedeemResult(false, 'That token is not valid.');
    final tokenId = _normId(fields[1]);
    if (tokenId != _normId(installId) && tokenId != _normId(_installId)) {
      return const RedeemResult(
          false, 'This token was made for a different Gmail account.');
    }
    final days = int.tryParse(fields[2]) ?? 0;
    if (days < 1 || days > 3650)
      return const RedeemResult(false, 'That token is not valid.');
    final nonce = fields[3];
    if (_used.contains(nonce))
      return const RedeemResult(false, 'This token has already been used.');

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
