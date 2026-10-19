import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthUser {
  final String email;
  final String name;
  final String photo;
  const AuthUser({required this.email, this.name = '', this.photo = ''});
}

class AuthFailure {
  final String message;
  final String detail;
  const AuthFailure(this.message, [this.detail = '']);
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

  /// Returns null on success or when the user simply closes the account
  /// picker; returns a failure to show on screen otherwise.
  Future<AuthFailure?> signIn() async {
    try {
      // Clear any cached account so the Gmail picker always appears.
      try { await _google.signOut(); } catch (_) {}
      final account = await _google.signIn();
      if (account == null) return null;
      if (!_isGmail(account.email)) {
        try { await _google.signOut(); } catch (_) {}
        return const AuthFailure('Please continue with a Gmail address (@gmail.com).');
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
    } catch (error) {
      return AuthFailure('Could not sign in. Check your internet and try again.', '$error');
    }
  }

  Future<void> signOut() async {
    try { await _google.signOut(); } catch (_) {}
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
