import '../utils/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../main.dart';
import '../services/ad_preloader.dart';
import '../services/premium_service.dart';
import 'remove_ads_screen.dart';

/// How the ad page ended.
enum SupportResult {
  /// It was shown and the person skipped it.
  completed,

  /// It could not load at all (offline / dead link): nobody is locked out.
  failed,
}

/// YouTube-style ad page.
///
///  1. The page is normally PRELOADED in the background shortly before it is
///     due, so it appears instantly. If not, "please wait" shows while it
///     loads; Back is ignored until it can be skipped.
///  2. Once loaded: an "Ad" badge, a progress line and a "Skip in N" button
///     that turns into "Skip Ad" after [skipAfterSeconds].
///  3. Normal ads stay up until Skip Ad. Download-triggered ads instead
///     auto-close when the page is ready (or fail open on a short timeout).
class SupportAdScreen extends StatefulWidget {
  final String url;
  final int skipAfterSeconds;

  /// Download flow: open the originally requested page as soon as this ad
  /// reaches its loaded state, without displaying the normal Skip countdown.
  final bool autoContinueOnLoad;

  /// Page loaded in the background by [AdPreloader] (null = load it here).
  final PreloadedAd? preloaded;
  const SupportAdScreen({
    super.key,
    required this.url,
    required this.skipAfterSeconds,
    this.autoContinueOnLoad = false,
    this.preloaded,
  });

  @override
  State<SupportAdScreen> createState() => _SupportAdScreenState();
}

enum _Phase { loading, ready, error }

class _SupportAdScreenState extends State<SupportAdScreen> {
  static const _settleDelay = Duration(milliseconds: 1400);
  static const _maxLoadSeconds = 40;
  static const _yellow = Color(0xFFFFCC00);
  static const _waitText = 'Ad loading… please wait';

  late final WebViewController _wc;
  _Phase _phase = _Phase.loading;
  final ValueNotifier<int> _progress = ValueNotifier<int>(0);
  final ValueNotifier<double> _elapsed = ValueNotifier<double>(0);

  Timer? _settle;
  Timer? _maxLoad;
  Timer? _tick;
  DateTime? _begin;

  bool _started = false;
  bool _everLoaded = false;
  bool _done = false;
  bool _engaged = false; // the person tapped the ad

  @override
  void initState() {
    super.initState();
    final pre = widget.preloaded;
    _wc = pre?.controller ?? WebViewController();
    _wc
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => _route(r.url),
        onPageStarted: (_) {
          _started = true;
          _makeClickable();
          _onNewPage();
        },
        onProgress: (p) {
          _progress.value = p;
          if (p >= 100) _scheduleSettle();
        },
        onPageFinished: (_) {
          _started = true;
          _makeClickable();
          _scheduleSettle();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && !_everLoaded && mounted) _fail();
        },
      ));

    if (pre == null) {
      final p = _wc.platform;
      if (p is AndroidWebViewController) {
        final cookies = WebViewCookieManager().platform;
        if (cookies is AndroidWebViewCookieManager) {
          cookies.setAcceptThirdPartyCookies(p, true);
        }
      }
      _wc.loadRequest(Uri.parse(widget.url));
    } else {
      // Already loaded in the background: show it straight away.
      _started = true;
      _makeClickable();
      if (pre.finished) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _markLoaded());
      } else {
        _scheduleSettle();
      }
    }
    _armMaxLoad();
  }

  /// A page still loading after [_maxLoadSeconds] is treated as loaded (if it
  /// showed anything) so it can never hold the person for ever.
  void _armMaxLoad() {
    _maxLoad?.cancel();
    final timeout = widget.autoContinueOnLoad
        ? const Duration(seconds: 12)
        : const Duration(seconds: _maxLoadSeconds);
    _maxLoad = Timer(timeout, () {
      if (_done || !mounted || _phase != _Phase.loading) return;
      if (widget.autoContinueOnLoad) {
        // A slow or broken ad never holds the requested download hostage.
        _continueAnyway();
      } else if (_started) {
        _markLoaded();
      } else {
        _fail();
      }
    });
  }

  // ------------------------------------------------------------ loading

  /// A new page starting after the ad is showing means the person tapped it.
  void _onNewPage() {
    _settle?.cancel();
    if (_done || !mounted) return;
    if (_phase == _Phase.ready && !_engaged) setState(() => _engaged = true);
  }

  void _scheduleSettle() {
    if (_done || !mounted || _phase == _Phase.error) return;
    _settle?.cancel();
    _settle = Timer(_settleDelay, _markLoaded);
  }

  void _markLoaded() {
    if (_done || !mounted || _phase == _Phase.error) return;
    _everLoaded = true;
    _maxLoad?.cancel();
    if (_phase == _Phase.ready && _begin != null) return;
    setState(() => _phase = _Phase.ready);
    if (widget.autoContinueOnLoad) {
      // Pop on the next frame to avoid navigating during a WebView callback.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_done) _finish();
      });
      return;
    }
    _startCountdown();
  }

  void _startCountdown() {
    _tick?.cancel();
    _begin = DateTime.now();
    _elapsed.value = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final e = DateTime.now().difference(_begin!).inMilliseconds / 1000;
      _elapsed.value = e;
      if (e >= widget.skipAfterSeconds) t.cancel();
    });
  }

  void _fail() {
    if (_done || !mounted) return;
    if (widget.autoContinueOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_done) _continueAnyway();
      });
      return;
    }
    _tick?.cancel();
    _settle?.cancel();
    setState(() => _phase = _Phase.error);
  }

  // ------------------------------------------------------------- closing

  bool get _canSkip =>
      _phase == _Phase.ready && _elapsed.value >= widget.skipAfterSeconds;

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.completed);
  }

  void _continueAnyway() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.failed);
  }

  void _retry() {
    _started = false;
    _everLoaded = false;
    _engaged = false;
    _progress.value = 0;
    setState(() => _phase = _Phase.loading);
    _armMaxLoad();
    _wc.loadRequest(Uri.parse(widget.url));
  }

  Future<void> _removeAds() async {
    await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const RemoveAdsScreen()));
    if (mounted && PremiumService.instance.active) _finish();
  }

  @override
  void dispose() {
    _settle?.cancel();
    _maxLoad?.cancel();
    _tick?.cancel();
    _progress.dispose();
    _elapsed.dispose();
    // Stop the ad's sound / scripts now that it is closed.
    try {
      _wc.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    super.dispose();
  }

  // ----------------------------------------------------------- web page

  /// Links that ask for a new tab / window would do nothing inside the app,
  /// so open them in this same page.
  static const _clickFix = '''
(function(){
  if (window.__spFix) return; window.__spFix = true;
  window.open = function(u){ if (u) { location.href = u; } return window; };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
    if (a && a.target !== '_self') { a.target = '_self'; }
  }, true);
})();
''';

  void _makeClickable() {
    try {
      _wc.runJavaScript(_clickFix);
    } catch (_) {}
  }

  /// Web links go through. App links (intent://, market://) become their web
  /// page so tapping them still goes somewhere; the rest is ignored.
  NavigationDecision _route(String url) {
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (const {'http', 'https', 'about', 'data', 'blob'}.contains(scheme)) {
      return NavigationDecision.navigate;
    }
    String? web;
    if (scheme == 'intent') {
      final fb = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
      if (fb != null) {
        web = Uri.decodeComponent(fb.group(1)!);
      } else {
        final sch = RegExp(r'scheme=(https?);').firstMatch(url)?.group(1);
        final body = url.substring('intent://'.length).split('#Intent').first;
        if (sch != null && body.isNotEmpty) web = '$sch://$body';
      }
    } else if (scheme == 'market') {
      final id = uri?.queryParameters['id'];
      if (id != null && id.isNotEmpty) {
        web = 'https://play.google.com/store/apps/details?id=$id';
      }
    }
    final target = web == null ? null : Uri.tryParse(web);
    if (target != null &&
        (target.scheme == 'http' || target.scheme == 'https')) {
      _wc.loadRequest(target);
    }
    return NavigationDecision.prevent;
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_phase == _Phase.ready && _canSkip) _finish();
          if (_phase == _Phase.error) _continueAnyway();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(children: [
              _bar(),
              Expanded(
                child: _phase == _Phase.error
                    ? _errorView()
                    : Stack(children: [
                        Positioned.fill(child: WebViewWidget(controller: _wc)),
                        // Hide the half-built page while it is still loading.
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: _phase != _Phase.loading,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              opacity: _phase == _Phase.loading ? 1 : 0,
                              child: Container(
                                color: appBg,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 3, color: appRed),
                                    ),
                                    SizedBox(height: 14),
                                    Text(_waitText,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_phase == _Phase.ready)
                          Positioned(
                              right: 0, bottom: 22, child: _skipButton()),
                      ]),
              ),
            ]),
          ),
        ),
      );

  /// YouTube's "Skip in 5" -> "Skip Ad" button.
  Widget _skipButton() => ValueListenableBuilder<double>(
        valueListenable: _elapsed,
        builder: (_, e, __) {
          final wait = widget.skipAfterSeconds - e;
          final ready = wait <= 0;
          return Material(
            color: Colors.black.withValues(alpha: .78),
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: Colors.white70, width: 1),
              borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
            ),
            child: InkWell(
              onTap: ready ? _finish : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    ready
                        ? (_engaged ? 'Continue' : 'Skip Ad')
                        : 'Skip in ${wait.ceil()}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ready ? Colors.white : Colors.white60,
                    ),
                  ),
                  if (ready) ...[
                    SizedBox(width: 6),
                    Icon(Icons.skip_next_rounded,
                        size: 22, color: Colors.white),
                  ],
                ]),
              ),
            ),
          );
        },
      );

  Widget _bar() {
    final loading = _phase != _Phase.ready;
    return Container(
      color: appSurface,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _yellow,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('Ad'.tr,
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w900)),
            ),
            SizedBox(width: 10),
            Expanded(
              child: loading
                  ? Text(_waitText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800))
                  : ValueListenableBuilder<double>(
                      valueListenable: _elapsed,
                      builder: (_, e, __) => Text(
                        _engaged
                            ? 'Ad · tap Continue when you are done'
                            : (e >= widget.skipAfterSeconds
                                ? 'Ad · tap Skip Ad to continue'
                                : 'Ad'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800),
                      ),
                    ),
            ),
            TextButton.icon(
              onPressed: _removeAds,
              icon: Icon(Icons.block_rounded, size: 16),
              label: Text('Remove ads'.tr),
            ),
          ]),
        ),
        // Loading: page progress. Showing: yellow ad-progress line.
        loading
            ? ValueListenableBuilder<int>(
                valueListenable: _progress,
                builder: (_, p, __) => LinearProgressIndicator(
                  minHeight: 3,
                  value: p <= 0 ? null : p / 100,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(appRed),
                ),
              )
            : ValueListenableBuilder<double>(
                valueListenable: _elapsed,
                builder: (_, e, __) => LinearProgressIndicator(
                  minHeight: 3,
                  value: _engaged
                      ? 1.0
                      : (widget.skipAfterSeconds <= 0
                              ? 1.0
                              : e / widget.skipAfterSeconds)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(_yellow),
                ),
              ),
      ]),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_rounded, size: 44, color: Colors.white54),
            SizedBox(height: 12),
            Text('The ad page could not load'.tr,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('Check your internet connection, or continue without it.'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            SizedBox(height: 16),
            Wrap(spacing: 10, children: [
              FilledButton(onPressed: _retry, child: Text('Retry'.tr)),
              OutlinedButton(
                  onPressed: _continueAnyway, child: Text('Continue'.tr)),
            ]),
          ]),
        ),
      );
}
