import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/support_ad_screen.dart';
import 'ad_preloader.dart';
import 'app_remote_config.dart';
import 'auth_service.dart';
import 'currency_service.dart';
import 'premium_service.dart';

/// Support ads (free plan), driven by the "ads" block in app_config.json.
///
///  * CARD TAP: tapping a movie card shows the ad first (the first card tap
///    of every launch), then the movie opens. After an ad, the next one waits
///    `cardCooldownMinutes` (5); the first card tapped after that shows it
///    again. Call [guard] from the card's tap handler.
///  * TIMER: every `intervalMinutes` (15) of use the ad appears by itself,
///    YouTube style. The ad page is loaded in the background shortly before
///    it is due ([AdPreloader]) so it shows instantly.
///  * Any ad (card or timer) restarts the 15-minute clock. Premium people
///    never see ads; the clock only runs while the app is on screen.
class AdService with WidgetsBindingObserver {
  AdService._();
  static final AdService instance = AdService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const _kSeconds = 'ad_active_seconds';
  static const _step = Duration(seconds: 5);

  /// The ad page starts loading this many seconds before it is due.
  static const preloadLeadSeconds = 60;

  /// If the ad page cannot load, nobody is locked out; ask again after this.
  static const retryMinutes = 3;

  Timer? _timer;
  int _seconds = 0;
  int _unsaved = 0;
  int _holds = 0;
  bool _foreground = true;
  bool _showing = false;
  bool _started = false;
  bool _shownThisLaunch = false;
  DateTime? _lastAdAt;

  AdsConfig get _ads => RemoteConfig.instance.ads;
  int get _limit => _ads.intervalMinutes * 60;

  bool get _active =>
      _ads.hasAd &&
      AuthService.instance.signedIn &&
      !PremiumService.instance.active;

  bool get isShowing => _showing;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(PremiumService.instance.load());
    unawaited(CurrencyService.instance.load());
    await RemoteConfig.instance.load();
    try {
      final prefs = await SharedPreferences.getInstance();
      _seconds = prefs.getInt(_kSeconds) ?? 0;
    } catch (_) {}
    // Load the first ad page in the background so the first card tap is instant.
    if (_active) AdPreloader.instance.warmUp();
    _timer = Timer.periodic(_step, (_) => _onTick());
  }

  /// Pause the clock while a page that must not be interrupted is open
  /// (remove-ads page). Call [release] when it closes.
  void hold() => _holds++;
  void release() => _holds = math.max(0, _holds - 1);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(RemoteConfig.instance.refresh());
    } else {
      _foreground = false;
      unawaited(_save());
      unawaited(PremiumService.instance.touch());
    }
  }

  // ------------------------------------------------------------ card tap

  bool get _cardAdDue {
    if (!_shownThisLaunch) return true;
    final last = _lastAdAt;
    if (last == null) return true;
    final elapsed = DateTime.now().difference(last);
    // elapsed < 0: the phone clock was moved back, so don't trust it.
    return elapsed.isNegative ||
        elapsed >= Duration(minutes: _ads.cardCooldownMinutes);
  }

  /// Call from a movie card's tap handler:
  ///
  ///   AdService.instance.guard(context, () => openTheMovie());
  ///
  /// Shows the support ad when one is due, then runs [proceed] so the tapped
  /// movie still opens.
  Future<void> guard(BuildContext context, VoidCallback proceed) async {
    if (_showing) return; // a second tap while the ad is up
    if (!_active || _holds > 0 || !_cardAdDue || !context.mounted) {
      proceed();
      return;
    }
    await _present(context);
    proceed();
  }

  /// Gate an actual Download tap for non-premium users. A fresh ad loads,
  /// then the existing Skip in N -> Skip Ad control lets them continue.
  /// If the ad cannot load, the requested download can still proceed.
  Future<void> guardDownload(
    BuildContext context,
    Future<void> Function() proceed,
  ) => _guardIntent(context, proceed, 'download');

  /// Gate Play on the movie detail page using the SAME ad / Skip Ad flow.
  /// Premium users bypass the ad. There is no auto-continue on load.
  Future<void> guardPlay(
    BuildContext context,
    Future<void> Function() proceed,
  ) => _guardIntent(context, proceed, 'play');

  bool _intentInProgress = false;

  Future<void> _guardIntent(
    BuildContext context,
    Future<void> Function() proceed,
    String action,
  ) async {
    // Prevent repeat taps opening multiple ads or destination pages.
    if (_showing || _intentInProgress || !context.mounted) return;
    _intentInProgress = true;
    try {
      try {
        // Avoid showing ads to subscribers whose status is still loading.
        await PremiumService.instance.ensureLoaded();
        if (_active && _holds == 0 && context.mounted) {
          // A fresh ad prevents a previously preloaded page from short-
          // circuiting the Skip Ad countdown on each user action.
          await _present(context, freshIntentAd: true);
        }
      } catch (error) {
        debugPrint('DamiMovies: $action ad could not open: $error');
      }
      // SupportAdScreen only returns on Skip Ad / Continue after an error.
      // Never navigate merely because the ad page has finished loading.
      if (context.mounted) await proceed();
    } finally {
      _intentInProgress = false;
    }
  }

  // --------------------------------------------------------------- timer

  void _onTick() {
    if (!_foreground || _showing || _holds > 0 || !_active) return;
    _seconds += _step.inSeconds;
    _unsaved += _step.inSeconds;
    if (_unsaved >= 30) unawaited(_save());

    // Shortly before an ad is due (timer or card cooldown), load it quietly.
    var left = _limit - _seconds;
    final last = _lastAdAt;
    if (_shownThisLaunch && last != null) {
      final cardLeft = _ads.cardCooldownMinutes * 60 -
          DateTime.now().difference(last).inSeconds;
      left = math.min(left, cardLeft);
    }
    if (left <= preloadLeadSeconds) AdPreloader.instance.warmUp();

    if (_seconds >= _limit) unawaited(_fire());
  }

  Future<void> _fire() async {
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null || _showing) return; // retry next tick
    await _present(ctx);
  }

  // ------------------------------------------------------------ showing

  Future<void> _present(
    BuildContext context, {
    bool freshIntentAd = false,
  }) async {
    if (_showing) return;
    final ads = _ads;
    _showing = true;
    SupportResult? result;
    try {
      result = await Navigator.of(context, rootNavigator: true)
          .push<SupportResult>(MaterialPageRoute<SupportResult>(
        fullscreenDialog: true,
        builder: (_) => SupportAdScreen(
          url: ads.supportUrl,
          skipAfterSeconds: ads.skipAfterSeconds,
          // Preserve the Skip Ad countdown on Play and Download actions.
          // Do not use the special autoContinueOnLoad mode.
          preloaded: freshIntentAd ? null : AdPreloader.instance.take(),
        ),
      ));
    } finally {
      _showing = false;
    }
    _shownThisLaunch = true;
    final now = DateTime.now();
    if (result == SupportResult.failed) {
      // The page would not load: nobody is locked out, ask again soon.
      _seconds = math.max(0, _limit - retryMinutes * 60);
      _lastAdAt = now.subtract(Duration(
          minutes: math.max(0, ads.cardCooldownMinutes - retryMinutes)));
    } else {
      _seconds = 0;
      _lastAdAt = now;
    }
    await _save();
  }

  Future<void> _save() async {
    _unsaved = 0;
    try {
      (await SharedPreferences.getInstance()).setInt(_kSeconds, _seconds);
    } catch (_) {}
  }
}
