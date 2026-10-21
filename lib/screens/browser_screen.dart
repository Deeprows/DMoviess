import '../utils/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../main.dart';
import '../services/ad_shield.dart';
import '../services/download_manager.dart';
import '../utils/external_link.dart' show openInExternalBrowser;
import 'downloads_screen.dart';
import 'download_scanner_screen.dart';

final RegExp _directFile = RegExp(
    r'\.(apk|zip|rar|7z|tar|gz|iso|exe|msi|dmg|torrent|mkv|mp4|avi|mov|m4v|webm|mp3|m4a|pdf|jpg|png|epub)(?:$|[?#])',
    caseSensitive: false);
bool isDirectMovieDownload(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (_directFile.hasMatch(uri.path)) return true;
  return uri.queryParameters.values.any((v) => _directFile.hasMatch(v));
}

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const BrowserScreen({super.key, this.initialUrl});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  String _url = '';
  String _pageTitle = 'DamiMovies Browser';
  String? _errorText;
  int _progress = 0;
  bool _canBack = false, _canForward = false, _shieldEnabled = true;
  bool _isDownloadOptionsPage = false;
  bool _leaving = false;
  bool _scannerOpen = false;
  int _backStuck = 0;
  int _blocked = 0;
  DateTime _lastBlockNote = DateTime.fromMillisecondsSinceEpoch(0);
  // What the person really tapped last, used to tell their own navigation
  // from an ad script hijacking the page right after a tap.
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastTapHref = '';
  DateTime _trustUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? _allowDownloadNavigationOnce;
  int _pageDetectionGeneration = 0;
  Timer? _progressTimeout;

  @override
  void initState() {
    super.initState();
    final start = widget.initialUrl == null
        ? 'about:blank'
        : _normalise(widget.initialUrl!);
    _url = start;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(appBg)
      ..addJavaScriptChannel('DamiBridge',
          onMessageReceived: (message) => _onBridge(message.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (url) {
          if (mounted)
            setState(() {
              _url = url;
              _progress = 8;
              _errorText = null;
            });
          _applyShield();
          _refreshNav();
          _progressTimeout?.cancel();
          _progressTimeout = Timer(const Duration(seconds: 25), () {
            if (mounted && _progress < 100) setState(() => _progress = 100);
          });
        },
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
          _applyShield();
        },
        onPageFinished: (url) async {
          _progressTimeout?.cancel();
          final title = await _controller.getTitle();
          await _refreshNav();
          if (!mounted) return;
          setState(() {
            _url = url;
            _pageTitle =
                (title == null || title.isEmpty) ? 'DamiMovies Browser' : title;
            _progress = 100;
          });
          _detectDownloadOptionsPage();
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (mounted && _url == url) _detectDownloadOptionsPage();
          });
          _applyShield();
        },
        onUrlChange: (change) {
          final value = change.url;
          if (value != null && mounted) {
            setState(() => _url = value);
          }
          _refreshNav();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted)
            setState(() => _errorText =
                'This page could not be loaded. Check the connection or try another link.');
        },
      ));
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    _controller.loadRequest(Uri.parse(start));
  }

  Future<void> _detectDownloadOptionsPage() async {
    final generation = ++_pageDetectionGeneration;
    try {
      final result =
          await _controller.runJavaScriptReturningResult(r'''(function(){
        var els=[].slice.call(document.querySelectorAll('a,button,[role="button"],input[type="button"],input[type="submit"]'));
        var hits=0, cards=0;
        els.forEach(function(el){
          var t=(el.innerText||el.textContent||el.value||el.getAttribute('aria-label')||'').replace(/\s+/g,' ').trim();
          var r=el.getBoundingClientRect();
          if(!/^(download|download now|direct download|get download)$/i.test(t)||r.width<30||r.height<15)return;
          hits++;
          var p=el;
          for(var i=0;i<5&&p.parentElement;i++){
            p=p.parentElement;
            var txt=(p.innerText||'').replace(/\s+/g,' ').trim();
            if(txt.length<400&&(/\b\d{3,4}\s*p\b|\b4k\b|\b\d+(?:\.\d+)?\s*(mb|gb)\b|hevc|webrip|h264/i.test(txt))){cards++;break;}
          }
        });
        return hits>=2&&cards>=1;
      })()''');
      if (!mounted || generation != _pageDetectionGeneration) return;
      final detected = result == true || result.toString() == 'true';
      if (_isDownloadOptionsPage != detected)
        setState(() => _isDownloadOptionsPage = detected);
    } catch (_) {
      if (mounted &&
          generation == _pageDetectionGeneration &&
          _isDownloadOptionsPage)
        setState(() => _isDownloadOptionsPage = false);
    }
  }

  void _openScanner() {
    if (_url.isEmpty) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => DownloadScannerScreen(pageUrl: _url)));
  }

  String _normalise(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return 'https://www.google.com';
    if (value == 'about:blank') return value;
    if (!value.contains('://')) {
      if (value.contains(' ') ||
          (!value.contains('.') && value.toLowerCase() != 'localhost')) {
        value =
            'https://www.google.com/search?q=${Uri.encodeQueryComponent(value)}';
      } else {
        value = 'https://$value';
      }
    }
    return value;
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    if (scheme != 'http' && scheme != 'https') {
      return NavigationDecision.prevent;
    }
    if (_shieldEnabled && (_isAdHost(uri.host) || AdShield.isAdUrl(request.url))) {
      if (request.isMainFrame) _noteBlocked();
      return NavigationDecision.prevent;
    }
    if (_allowDownloadNavigationOnce == request.url) {
      _allowDownloadNavigationOnce = null;
      return NavigationDecision.navigate;
    }
    if (isDirectMovieDownload(request.url) && request.isMainFrame) {
      unawaited(_startDownload(request.url));
      return NavigationDecision.prevent;
    }
    // An ad script that sends the whole page somewhere else right after a tap.
    if (_shieldEnabled && request.isMainFrame && _isHijack(uri)) {
      _noteBlocked(url: request.url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  bool _isAdHost(String host) => RegExp(
          r'(^|\.)(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adsterra\.com|propellerads\.com|popads\.net|popcash\.net|exoclick\.com|clickadu\.com|hilltopads\.net|trafficjunky\.net|onclkds\.com|profitablecpmrate\.com|highperformanceformat\.com)$',
          caseSensitive: false)
      .hasMatch(host);

  /// "example.co.uk" / "www.example.com" -> comparable site name.
  String _site(String host) {
    final parts =
        host.toLowerCase().split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return parts.join('.');
    const second = {'co', 'com', 'org', 'net', 'gov', 'ac'};
    final last = parts[parts.length - 1];
    final prev = parts[parts.length - 2];
    if (second.contains(prev) && last.length == 2) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return '$prev.$last';
  }

  bool _sameSite(String a, String b) =>
      a.isNotEmpty && b.isNotEmpty && _site(a) == _site(b);

  bool _tapMatches(Uri uri) {
    if (_lastTapHref.isEmpty) return false;
    final tapped = Uri.tryParse(_lastTapHref);
    if (tapped == null) return false;
    return tapped.host.toLowerCase() == uri.host.toLowerCase();
  }

  /// True when the page is being sent to ANOTHER site within a moment of a
  /// tap that was not a link to that site. Normal links, server redirects of
  /// a tapped link, and pages that redirect on their own are all allowed.
  bool _isHijack(Uri uri) {
    final now = DateTime.now();
    if (now.isBefore(_trustUntil)) return false;
    if (now.difference(_lastTapAt) > const Duration(milliseconds: 2500)) {
      return false;
    }
    final current = Uri.tryParse(_url);
    if (current != null && _sameSite(uri.host, current.host)) return false;
    if (_tapMatches(uri)) {
      _trustUntil = now.add(const Duration(seconds: 10));
      return false;
    }
    return true;
  }

  void _noteBlocked({String? url}) {
    _blocked++;
    if (!mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastBlockNote) < const Duration(seconds: 4)) return;
    _lastBlockNote = now;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Blocked an ad redirect'.tr),
      duration: const Duration(seconds: 3),
      action: url == null
          ? null
          : SnackBarAction(
              label: 'ALLOW',
              onPressed: () {
                _trustUntil = DateTime.now().add(const Duration(seconds: 10));
                final target = Uri.tryParse(url);
                if (target != null) _controller.loadRequest(target);
              }),
    ));
  }

  // --------------------------------------------------- page <-> app bridge

  void _onBridge(String raw) {
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (data == null || !mounted) return;
    switch ('${data['t']}') {
      case 'tap':
        _lastTapAt = DateTime.now();
        _lastTapHref = '${data['href'] ?? ''}';
        break;
      case 'popup':
        _onPopup('${data['url'] ?? ''}');
        break;
      case 'download':
        _onDownloadTap('${data['href'] ?? ''}', '${data['label'] ?? ''}');
        break;
    }
  }

  /// window.open() from the page. It never replaces the page the person is on.
  void _onPopup(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !mounted) return;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return;
    if (isDirectMovieDownload(url)) {
      unawaited(_startDownload(url));
      return;
    }
    if (_shieldEnabled) {
      if (_isAdHost(uri.host) || AdShield.isAdUrl(url)) {
        _noteBlocked();
        return;
      }
      final current = Uri.tryParse(_url);
      if (current == null || !_sameSite(uri.host, current.host)) {
        _noteBlocked(url: url);
        return;
      }
    }
    _controller.loadRequest(uri);
  }

  /// The person tapped "Download" on a quality/server card. The page's own
  /// click handler (where the ad redirects live) is stopped; the app follows
  /// the link itself in a hidden browser and starts the download.
  void _onDownloadTap(String href, String label) {
    if (!mounted) return;
    final link = href.trim();
    if (link.isNotEmpty && isDirectMovieDownload(link)) {
      unawaited(_startDownload(link));
      return;
    }
    if (_scannerOpen) return;
    _scannerOpen = true;
    unawaited(Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DownloadScannerScreen(
                      pageUrl: _url,
                      entryUrl: link.isEmpty ? null : link,
                      entryLabel: label,
                      autoDownload: true,
                    )))
        .whenComplete(() => _scannerOpen = false));
  }

  static const String _shieldJs = r"""
(function(){
  if (window.__damiShield2) return;
  window.__damiShield2 = true;
  function post(o){ try{ DamiBridge.postMessage(JSON.stringify(o)); }catch(e){} }
  function anchorHref(el){
    var a = el && el.closest ? el.closest('a[href]') : null;
    if (!a) return '';
    try { return new URL(a.getAttribute('href'), location.href).href; } catch(e){ return ''; }
  }
  function txt(el){
    return (el.innerText||el.textContent||el.value||el.getAttribute('aria-label')||'').replace(/\s+/g,' ').trim();
  }
  // Same label the download scanner builds, so it can find the same button again.
  function labelFor(el){
    var c=el, best='';
    for(var i=0;i<8&&c.parentElement;i++){
      c=c.parentElement;
      var t=(c.innerText||c.textContent||'').replace(/\s+/g,' ').trim();
      if(t.length>0&&t.length<260&&(/\b\d{3,4}\s*p\b|\b4k\b|\b\d+\s*(mb|gb)\b|\b(10bit|hevc|h264)\b/i.test(t))){
        best=t.replace(/download/ig,'').replace(/\s+/g,' ').trim().slice(0,130);
        if(c.querySelectorAll('a,button,[role=button]').length<=3) break;
      }
    }
    return best;
  }
  // 1. pop-ups never take over the page; the app decides what to do with them
  window.open = function(u){
    try{ if(u){ post({t:'popup', url:new URL(u, location.href).href}); } }catch(e){}
    return null;
  };
  // 2. remember what was really tapped
  document.addEventListener('pointerdown', function(e){
    post({t:'tap', href:anchorHref(e.target)});
  }, {capture:true, passive:true});
  // 3. "Download" on a quality/server card is handled by the app
  document.addEventListener('click', function(e){
    var t = e.target;
    var a = t && t.closest ? t.closest('a[target=_blank]') : null;
    if (a) a.target = '_self';
    var el = t && t.closest ? t.closest('a,button,[role="button"],input[type="button"],input[type="submit"]') : null;
    if (!el) return;
    if (!/^(download|download now|direct download|get download|get link)$/i.test(txt(el))) return;
    var label = labelFor(el);
    if (!label) return;
    e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
    var href = '';
    if (el.tagName === 'A') {
      var h = el.getAttribute('href') || '';
      if (h && h !== '#' && !/^javascript/i.test(h)) { try{ href = new URL(h, location.href).href; }catch(x){} }
    }
    post({t:'download', href:href, label:label});
  }, true);
  var style = document.createElement('style');
  style.textContent = 'iframe[src*="doubleclick.net"],iframe[src*="adsterra"],iframe[src*="popads.net"],iframe[src*="exoclick"],iframe[src*="propellerads"]{display:none!important}';
  (document.head || document.documentElement).appendChild(style);
})();
""";

  Future<void> _applyShield() async {
    if (!_shieldEnabled) return;
    try {
      await _controller.runJavaScript(_shieldJs);
      await _controller.runJavaScript(AdShield.adShieldLightJs);
    } catch (_) {}
  }

  // -------------------------------------------------------------- back / exit

  void _exit() {
    if (!mounted || _leaving) return;
    _leaving = true;
    Navigator.of(context).pop();
  }

  Future<void> _backInsideBrowser() async {
    if (_leaving) return;
    try {
      if (await _controller.canGoBack()) {
        final before = _url;
        await _controller.goBack();
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted || _leaving) return;
        if (_url == before) {
          // Ad pages can trap the back button by pushing the same page again.
          _backStuck++;
          if (_backStuck >= 2) {
            _exit();
          } else {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                  content: Text('Tap back again to leave this page'.tr),
                  duration: const Duration(seconds: 2)));
          }
          return;
        }
        _backStuck = 0;
        await _refreshNav();
        return;
      }
    } catch (_) {}
    _exit();
  }

  Future<void> _refreshNav() async {
    try {
      final back = await _controller.canGoBack();
      final forward = await _controller.canGoForward();
      if (mounted)
        setState(() {
          _canBack = back;
          _canForward = forward;
        });
    } catch (_) {}
  }

  Future<String> _cookies() async {
    try {
      final result =
          await _controller.runJavaScriptReturningResult('document.cookie');
      return result.toString().replaceAll(RegExp(r'^"|"$'), '');
    } catch (_) {
      return '';
    }
  }

  Future<void> _startDownload(String url) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Preparing download…'.tr)));
    final error = await DownloadManager.instance
        .enqueue(url, referer: _url, cookie: await _cookies());
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (error != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(error),
        duration: const Duration(seconds: 7),
        action: SnackBarAction(
            label: 'OPEN IN BROWSER',
            onPressed: () => openInExternalBrowser(context, url)),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
          content: Text('Download started'.tr),
          action: SnackBarAction(
              label: 'VIEW',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DownloadsScreen())))));
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() { _progress = 5; _errorText = null; });
    await _controller.reload();
  }

  @override
  void dispose() {
    _progressTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _backInsideBrowser();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _backInsideBrowser,
            ),
            title: const Text('Download',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                tooltip: 'Find downloadable files',
                onPressed: _openScanner,
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
              IconButton(
                tooltip: 'My downloads',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DownloadsScreen())),
                icon: const Icon(Icons.file_download_done_rounded),
              ),
              IconButton(
                tooltip: _shieldEnabled ? 'Ad protection on' : 'Ad protection off',
                onPressed: () {
                  setState(() => _shieldEnabled = !_shieldEnabled);
                  if (_shieldEnabled) {
                    _applyShield();
                  } else {
                    _reload();
                  }
                },
                icon: Icon(_shieldEnabled
                    ? Icons.shield_rounded : Icons.shield_outlined,
                    color: _shieldEnabled ? appRed : Colors.white70),
              ),
            ],
            bottom: _progress < 100
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(2),
                    child: LinearProgressIndicator(
                      value: _progress <= 0 ? null : _progress / 100,
                      minHeight: 2, color: appRed,
                      backgroundColor: appSurface,
                    ))
                : null,
          ),
          body: Column(children: [
            if (_isDownloadOptionsPage)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Find download links'),
                    style: FilledButton.styleFrom(backgroundColor: appRed),
                  ),
                ),
              ),
            Expanded(child: Stack(children: [
              WebViewWidget(controller: _controller),
              if (_errorText != null)
                Center(child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: appSurface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_rounded,
                        size: 40, color: Colors.white60),
                    const SizedBox(height: 12),
                    Text(_errorText!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: Text('Retry'.tr),
                    ),
                  ]),
                )),
            ])),
            Container(
              // Keep the buttons above the phone's own navigation bar.
              height: 54 + MediaQuery.of(context).viewPadding.bottom,
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
              decoration: const BoxDecoration(
                color: Color(0xFF0E121A),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Previous webpage',
                    onPressed: _backInsideBrowser,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Next webpage',
                    onPressed: _canForward ? () async {
                      await _controller.goForward();
                      await _refreshNav();
                    } : null,
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Reload page',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Download manager',
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const DownloadsScreen())),
                    icon: const Icon(Icons.download_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close browser',
                    onPressed: _exit,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
}
