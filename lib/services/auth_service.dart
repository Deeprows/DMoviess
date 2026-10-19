import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'community_service.dart';

class AuthUser {
  final String email;
  final String name;
  final String photo;
  const AuthUser({required this.email, this.name = '', this.photo = ''});

  /// The Gmail picture, or null when the account has none.
  String? get photoUrl => photo.isEmpty ? null : photo;
}

class AuthFailure {
  final String message;
  final String detail;
  /// 'signup' or 'login': which tab the screen should switch to.
  final String? switchTo;
  const AuthFailure(this.message, [this.detail = '', this.switchTo]);
}

/// Gmail sign-in for DamiMovies. "Log in" and "Sign up" use the same Google
/// flow: a first-time Gmail account is simply created on first use.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Optional: the *Web* OAuth client ID from Google Cloud. Pass it with
  /// --dart-define=GOOGLE_WEB_CLIENT_ID=... when you need an ID token.
  static const String _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static const _kEmail = 'damimovies_auth_email';
  static const _kName = 'damimovies_auth_name';
  static const _kPhoto = 'damimovies_auth_photo';
  static const _kRegistered = 'damimovies_registered_emails';

  final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: _webClientId.isEmpty ? null : _webClientId,
  );

  AuthUser? _user;
  bool _ready = false;

  AuthUser? get user => _user;
  bool get ready => _ready;
  bool get signedIn => _user != null;

  /// Loads the saved session so returning users go straight to the app, even
  /// offline, then quietly refreshes the Google account in the background.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_kEmail) ?? '';
      if (email.isNotEmpty) {
        _user = AuthUser(
          email: email,
          name: prefs.getString(_kName) ?? '',
          photo: prefs.getString(_kPhoto) ?? '',
        );
      }
    } catch (error) {
      debugPrint('DamiMovies: could not restore session: $error');
    }
    _ready = true;
    notifyListeners();
    if (_user != null) unawaited(_refreshSilently());
  }

  Future<void> _refreshSilently() async {
    try {
      final account = await _google.signInSilently().timeout(const Duration(seconds: 8));
      if (account != null) {
        _user = _fromAccount(account);
        await _save();
        notifyListeners();
      }
    } catch (_) {
      // Offline or Google unavailable: keep the saved session.
    }
  }

  AuthUser _fromAccount(GoogleSignInAccount account) => AuthUser(
        email: account.email,
        name: account.displayName ?? '',
        photo: account.photoUrl ?? '',
      );

  Future<void> _save() async {
    final user = _user;
    if (user == null) return;
    // A storage problem must never turn a successful Google sign-in into a failure.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEmail, user.email);
      await prefs.setString(_kName, user.name);
      await prefs.setString(_kPhoto, user.photo);
    } catch (error) {
      debugPrint('DamiMovies: could not save session: $error');
    }
  }

  bool _isGmail(String email) {
    final value = email.trim().toLowerCase();
    return value.endsWith('@gmail.com') || value.endsWith('@googlemail.com');
  }

  /// Checks the account against the sign-up list. Returns a failure when a
  /// Gmail that never signed up tries to log in, or one that already has an
  /// account tries to sign up again.
  Future<AuthFailure?> _checkRegistration(GoogleSignInAccount account, bool signUp) async {
    final email = account.email.trim().toLowerCase();
    if (AppConfig.authUrl.startsWith('http')) {
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        return const AuthFailure('Sign-in is missing the Google Web client ID. Add the GOOGLE_WEB_CLIENT_ID secret and rebuild.');
      }
      final response = await http
          .post(
            Uri.parse(AppConfig.authUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'mode': signUp ? 'signup' : 'login', 'idToken': idToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return null;
      if (response.statusCode == 404) {
        return AuthFailure('$email has not signed up yet. Please sign up first, then log in.', '', 'signup');
      }
      if (response.statusCode == 409) {
        return AuthFailure('$email already has an account. Please log in instead.', '', 'login');
      }
      return AuthFailure('Could not check your account. Please try again.', 'server ${response.statusCode}');
    }
    // No server configured: remember sign-ups on this phone.
    final prefs = await SharedPreferences.getInstance();
    final registered = (prefs.getStringList(_kRegistered) ?? const <String>[]).toSet();
    if (signUp) {
      if (registered.contains(email)) {
        return AuthFailure('$email already has an account. Please log in instead.', '', 'login');
      }
      registered.add(email);
      await prefs.setStringList(_kRegistered, registered.toList());
      return null;
    }
    if (!registered.contains(email)) {
      return AuthFailure('$email has not signed up yet. Please sign up first, then log in.', '', 'signup');
    }
    return null;
  }

  /// Returns null on success or when the user simply closes the account
  /// picker; returns a failure to show on screen otherwise.
  Future<AuthFailure?> signIn({required bool signUp}) async {
    try {
      // Clear any cached account so the Gmail picker always appears.
      try { await _google.signOut(); } catch (_) {}
      final account = await _google.signIn();
      if (account == null) return null;
      if (!_isGmail(account.email)) {
        try { await _google.signOut(); } catch (_) {}
        return const AuthFailure('Please continue with a Gmail address (@gmail.com).');
      }
      final failure = await _checkRegistration(account, signUp);
      if (failure != null) {
        try { await _google.signOut(); } catch (_) {}
        return failure;
      }
      _user = _fromAccount(account);
      await _save();
      notifyListeners();
      return null;
    } on PlatformException catch (error) {
      final code = error.code;
      final text = '${error.message ?? ''}';
      final detail = '$code ${error.message ?? ''}'.trim();
      if (code == 'sign_in_canceled') return null;
      if (code == 'network_error') {
        return AuthFailure('No internet connection. Check your network and try again.', detail);
      }
      if (RegExp(r'(^|\D)10(\D|$)').hasMatch(text) || text.contains('DEVELOPER_ERROR')) {
        return AuthFailure(
          'Google sign-in is not set up for this build yet. The app needs its Google OAuth client and signing SHA-1.',
          detail,
        );
      }
      return AuthFailure('Could not sign in. Check your internet and try again.', detail);
    } on TimeoutException {
      return const AuthFailure('The server took too long to answer. Check your internet and try again.');
    } catch (error) {
      return AuthFailure('Could not sign in. Check your internet and try again.', '$error');
    }
  }

  /// A fresh Google ID token for the signed-in account (used for token requests).
  Future<String?> freshIdToken() async {
    try {
      final account = _google.currentUser ?? await _google.signInSilently();
      final auth = await account?.authentication;
      final token = auth?.idToken;
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  /// Google ID token for the community server. Only available when the build
  /// has a Web client ID; otherwise the community uses this phone's own key.
  Future<String?> googleIdToken() async {
    if (_webClientId.isEmpty) return null;
    return freshIdToken();
  }

  Future<void> signOut() async {
    try { await _google.signOut(); } catch (_) {}
    CommunityService.instance.clear();
    _user = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kEmail);
      await prefs.remove(_kName);
      await prefs.remove(_kPhoto);
    } catch (_) {}
    notifyListeners();
  }
}
