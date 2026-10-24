import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import 'app_remote_config.dart';

/// An ad page that was loaded in the background and is ready to be shown.
class PreloadedAd {
  final WebViewController controller;

  /// True when the page (redirects included) had finished loading already.
  final bool finished;
  const PreloadedAd(this.controller, this.finished);
}

/// Loads the support-ad page in the background shortly BEFORE an ad is due
/// (YouTube style), so it appears instantly instead of making the person wait.
///
///  * [warmUp] is safe to call often: it does nothing while a fresh copy is
///    already loading / loaded.
///  * [take] hands the loaded page to the ad screen and forgets it, so the
///    next ad gets a new page.
///  * A copy older than [maxAgeSeconds] is thrown away and loaded again.
class AdPreloader {
  AdPreloader._();
  static final AdPreloader instance = AdPreloader._();

  static const maxAgeSeconds = 240;
  static const _settleDelay = Duration(milliseconds: 400);

  WebViewController? _wc;
  String? _loadedUrl;
  DateTime? _startedAt;
  bool _finished = false;
  bool _failed = false;
  Timer? _settle;

  bool get _isStale {
    final t = _startedAt;
    if (t == null) return true;
    return DateTime.now().difference(t).inSeconds > maxAgeSeconds;
  }

  void warmUp() {
    final url = RemoteConfig.instance.ads.supportUrl;
    if (!RemoteConfig.instance.ads.hasAd) return;
    if (_wc != null && _loadedUrl != url) _discard(); // link was changed
    if (_wc != null && !_failed && !_isStale) return;
    _discard();

    final wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final s = (Uri.tryParse(r.url)?.scheme ?? '').toLowerCase();
          const ok = {'http', 'https', 'about', 'data', 'blob'};
          return ok.contains(s)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          _settle?.cancel();
          _finished = false;
        },
        onProgress: (p) {
          if (p >= 100) _scheduleSettle();
        },
        onPageFinished: (_) => _scheduleSettle(),
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && !_finished) _failed = true;
        },
      ));

    final p = wc.platform;
    if (p is AndroidWebViewController) {
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }

    _wc = wc;
    _startedAt = DateTime.now();
    try {
      _loadedUrl = url;
      unawaited(wc.loadRequest(Uri.parse(url)));
    } catch (_) {
      _failed = true;
    }
  }

  void _scheduleSettle() {
    _settle?.cancel();
    _settle = Timer(_settleDelay, () => _finished = true);
  }

  /// Gives the background page to the ad screen. Null = nothing usable, the
  /// ad screen then loads the page itself.
  PreloadedAd? take() {
    final wc = _wc;
    if (wc == null ||
        _failed ||
        _isStale ||
        _loadedUrl != RemoteConfig.instance.ads.supportUrl) {
      _discard();
      return null;
    }
    final ad = PreloadedAd(wc, _finished);
    _settle?.cancel();
    _wc = null;
    _startedAt = null;
    _finished = false;
    _failed = false;
    return ad;
  }

  void _discard() {
    _settle?.cancel();
    final wc = _wc;
    _wc = null;
    _startedAt = null;
    _finished = false;
    _failed = false;
    if (wc != null) {
      try {
        unawaited(wc.loadRequest(Uri.parse('about:blank')));
      } catch (_) {}
    }
  }
}
