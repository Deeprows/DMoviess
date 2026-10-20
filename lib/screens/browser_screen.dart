import '../utils/l10n.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../main.dart';
import '../services/download_manager.dart';
import 'downloads_screen.dart';
import 'download_scanner_screen.dart';

final RegExp _directFile = RegExp(r'\.(apk|zip|rar|7z|tar|gz|iso|exe|msi|dmg|torrent|mkv|mp4|avi|mov|m4v|webm|mp3|m4a|pdf|jpg|png|epub)(?:$|[?#])', caseSensitive: false);
bool isDirectMovieDownload(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (_directFile.hasMatch(uri.path)) return true;
  return uri.queryParameters.values.any((v) => _directFile.hasMatch(v));
}

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const BrowserScreen({super.key, this.initialUrl});
  @override State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _address = TextEditingController();
  String _url = '';
  String _pageTitle = 'DamiMovies Browser';
  String? _errorText;
  int _progress = 0;
  bool _canBack = false, _canForward = false, _shieldEnabled = true;
  bool _isDownloadOptionsPage = false;
  int _pageDetectionGeneration = 0;
  Timer? _progressTimeout;

  @override void initState() {
    super.initState();
    final start = widget.initialUrl == null ? 'about:blank' : _normalise(widget.initialUrl!);
    _url = start;
    _address.text = start;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(appBg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (url) {
          if (mounted) setState(() { _url = url; _progress = 8; _errorText = null; });
          _address.text = url;
          _applyShield();
          _progressTimeout?.cancel();
          _progressTimeout = Timer(const Duration(seconds: 25), () {
            if (mounted && _progress < 100) setState(() => _progress = 100);
          });
        },
        onProgress: (p) { if (mounted) setState(() => _progress = p); _applyShield(); },
        onPageFinished: (url) async {
          _progressTimeout?.cancel();
          final title = await _controller.getTitle();
          await _refreshNav();
          if (!mounted) return;
          setState(() { _url = url; _pageTitle = (title == null || title.isEmpty) ? 'DamiMovies Browser' : title; _progress = 100; });
          _address.text = url;
          _detectDownloadOptionsPage();
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (mounted && _url == url) _detectDownloadOptionsPage();
          });
          _applyShield();
        },
        onUrlChange: (change) {
          final value = change.url;
          if (value != null && mounted) { setState(() => _url = value); _address.text = value; }
          _refreshNav();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) setState(() => _errorText = 'This page could not be loaded. Check the connection or try another link.');
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
      final result = await _controller.runJavaScriptReturningResult(r'''(function(){
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
      if (_isDownloadOptionsPage != detected) setState(() => _isDownloadOptionsPage = detected);
    } catch (_) {
      if (mounted && generation == _pageDetectionGeneration && _isDownloadOptionsPage) setState(() => _isDownloadOptionsPage = false);
    }
  }

  void _openScanner() {
    if (_url.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => DownloadScannerScreen(pageUrl: _url)));
  }

  String _normalise(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return 'https://www.google.com';
    if (value == 'about:blank') return value;
    if (!value.contains('://')) {
      if (value.contains(' ') || (!value.contains('.') && value.toLowerCase() != 'localhost')) {
        value = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(value)}';
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
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') return NavigationDecision.navigate;
    if (scheme != 'http' && scheme != 'https') return NavigationDecision.prevent;
    if (_shieldEnabled && _isAdHost(uri.host)) return NavigationDecision.prevent;
    if (request.isMainFrame && isDirectMovieDownload(request.url)) {
      unawaited(_startDownload(request.url));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  bool _isAdHost(String host) => RegExp(r'(^|\.)(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adsterra\.com|propellerads\.com|popads\.net|popcash\.net|exoclick\.com|clickadu\.com|hilltopads\.net|trafficjunky\.net|onclkds\.com|profitablecpmrate\.com|highperformanceformat\.com)$', caseSensitive: false).hasMatch(host);

  Future<void> _applyShield() async {
    if (!_shieldEnabled) return;
    try {
      await _controller.runJavaScript("""
        (function(){
          if(window.__damiShieldInstalled)return; window.__damiShieldInstalled=true;
          window.open=function(){return null};
          document.addEventListener('click',function(e){var a=e.target&&e.target.closest?e.target.closest('a'):null;if(a&&a.target==='_blank')a.target='_self'},true);
        })();
      """);
    } catch (_) {}
  }

  Future<void> _refreshNav() async {
    try {
      final back = await _controller.canGoBack();
      final forward = await _controller.canGoForward();
      if (mounted) setState(() { _canBack = back; _canForward = forward; });
    } catch (_) {}
  }

  Future<String> _cookies() async {
    try { final result = await _controller.runJavaScriptReturningResult('document.cookie'); return result.toString().replaceAll(RegExp(r'^"|"$'), ''); } catch (_) { return ''; }
  }

  Future<void> _startDownload(String url) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing download…'.tr)));
    final error = await DownloadManager.instance.enqueue(url, referer: _url, cookie: await _cookies());
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), duration: const Duration(seconds: 8))); 
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download started'.tr), action: SnackBarAction(label: 'VIEW', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())))));
    }
  }

  Future<void> _go() async {
    final value = _normalise(_address.text);
    _address.text = value;
    FocusScope.of(context).unfocus();
    setState(() { _progress = 1; _errorText = null; });
    try { await _controller.loadRequest(Uri.parse(value)); } catch (_) { if (mounted) setState(() => _errorText = 'Invalid address. Enter a complete website URL or search term.'); }
  }

  @override void dispose() { _progressTimeout?.cancel(); _address.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 12,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        if (!_isDownloadOptionsPage) Text(Uri.tryParse(_url)?.host ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ]),
      actions: [
        IconButton(tooltip: 'Scan download options on this page', onPressed: _url.isEmpty ? null : _openScanner, icon: const Icon(Icons.manage_search_rounded)),
        PopupMenuButton<String>(onSelected: (v) async {
          if (v == 'shield') setState(() => _shieldEnabled = !_shieldEnabled);
          if (v == 'external') { final u = Uri.tryParse(_url); if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication); }
          if (v == 'copy') await Clipboard.setData(ClipboardData(text: _url));
          if (v == 'downloads' && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
          if (v == 'scan' && mounted) _openScanner();
        }, itemBuilder: (_) => [
          PopupMenuItem(value: 'shield', child: Text(_shieldEnabled ? 'Disable pop-up shield' : 'Enable pop-up shield')),
          const PopupMenuItem(value: 'external', child: Text('Open in phone browser'.tr)),
          const PopupMenuItem(value: 'copy', child: Text('Copy page link'.tr)),
          const PopupMenuItem(value: 'downloads', child: Text('Downloads'.tr)),
          const PopupMenuItem(value: 'scan', child: Text('Scan download options'.tr)),
        ]),
      ],
      bottom: _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress <= 0 ? null : _progress / 100, minHeight: 2, color: appRed, backgroundColor: appSurface)) : null,
    ),
    body: Column(children: [
      if (_isDownloadOptionsPage)
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _openScanner,
          icon: const Icon(Icons.manage_search_rounded),
          label: Text('SCAN DOWNLOAD OPTIONS'.tr, style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .3)),
          style: FilledButton.styleFrom(backgroundColor: appRed, padding: const EdgeInsets.symmetric(vertical: 14)),
        )))
      else
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: Row(children: [
          Expanded(child: TextField(controller: _address, keyboardType: TextInputType.url, textInputAction: TextInputAction.go, onSubmitted: (_) => _go(), decoration: InputDecoration(prefixIcon: const Icon(Icons.language_rounded), hintText: 'Search or enter website', suffixIcon: IconButton(onPressed: () { _address.clear(); }, icon: const Icon(Icons.close_rounded)), contentPadding: const EdgeInsets.symmetric(vertical: 10), isDense: true))),
          const SizedBox(width: 7), IconButton.filled(onPressed: _go, icon: const Icon(Icons.arrow_forward_rounded), style: IconButton.styleFrom(backgroundColor: appRed)),
        ])),
      Expanded(child: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_errorText != null) Center(child: Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(18)), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.white60), const SizedBox(height: 12), Text(_errorText!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: () { setState(() => _errorText = null); _controller.reload(); }, icon: const Icon(Icons.refresh), label: Text('Retry'.tr))]))),
      ])),
      Container(height: 54, decoration: const BoxDecoration(color: Color(0xFF0E121A), border: Border(top: BorderSide(color: Colors.white10))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        IconButton(tooltip: 'Back', onPressed: _canBack ? () { _controller.goBack(); _refreshNav(); } : null, icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19)),
        IconButton(tooltip: 'Forward', onPressed: _canForward ? () { _controller.goForward(); _refreshNav(); } : null, icon: const Icon(Icons.arrow_forward_ios_rounded, size: 19)),
        IconButton(tooltip: 'Home', onPressed: () { _address.text = 'https://www.google.com'; _go(); }, icon: const Icon(Icons.home_outlined)),
        IconButton(tooltip: 'Reload', onPressed: () { setState(() { _progress = 5; _errorText = null; }); _controller.reload(); }, icon: const Icon(Icons.refresh_rounded)),
      ])),
    ]),
  );
}

