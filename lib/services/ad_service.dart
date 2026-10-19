import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/support_ad_screen.dart';
import 'app_remote_config.dart';
import 'auth_service.dart';
import 'currency_service.dart';
import 'premium_service.dart';

/// Support ads, driven by the "ads" block in app_config.json.
/// Every `intervalMinutes` of use the next tap opens the "We Need Your Support"
/// page, which shows `supportUrl` and offers Skip Ad after `skipAfterSeconds`.
class AdService with WidgetsBindingObserver {
  AdService._();
  static final AdService instance = AdService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const int _tickSeconds = 5;
  Timer? _timer;
  int _usageSeconds = 0;
  bool _due = false;
  bool _showing = false;
  bool _started = false;

  bool get _active =>
      RemoteConfig.instance.ads.hasAd && AuthService.instance.signedIn && !PremiumService.instance.active;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(RemoteConfig.instance.load());
    unawaited(PremiumService.instance.load());
    unawaited(CurrencyService.instance.load());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: _tickSeconds), (_) {
      if (!_active || _showing) return;
      _usageSeconds += _tickSeconds;
      if (_usageSeconds >= RemoteConfig.instance.ads.intervalMinutes * 60) _due = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(RemoteConfig.instance.refresh());
      _startTimer();
    } else {
      _timer?.cancel();
      unawaited(PremiumService.instance.touch());
    }
  }

  /// Called for every tap in the app; opens the ad only when one is due.
  void onUserTap() {
    if (!_due || _showing || !_active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null || _showing || !_due || PremiumService.instance.active) return;
    final ads = RemoteConfig.instance.ads;
    if (!ads.hasAd) return;
    _showing = true;
    _due = false;
    _usageSeconds = 0;
    try {
      await navigator.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SupportAdScreen(url: ads.supportUrl, skipAfterSeconds: ads.skipAfterSeconds),
      ));
    } finally {
      _showing = false;
      _usageSeconds = 0;
    }
  }
}
