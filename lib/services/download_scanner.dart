import 'dart:async';
import 'dart:convert';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import 'download_manager.dart';

/// A direct file found on a third-party download page.
class FoundFile {
  final String url;
  final String referer;
  String label; // text of the link / button on the page
  String? fileName; // from the server, when it told us
  int? total; // bytes, when the server told us

  FoundFile(this.url, this.referer, this.label);

  String get host => Uri.tryParse(url)?.host ?? '';

  /// "1080p", "720p", "4K" ... read from the link text or the address.
  String? get quality {
    final m = RegExp(r'(2160p|4k|1440p|1080p|720p|480p|360p|240p)',
            caseSensitive: false)
        .firstMatch('$label $url');
    return m?.group(1)!.toUpperCase().replaceAll('P', 'p');
  }

  /// File extension, mp4 when nothing says otherwise.
  String get extension {
    final src = fileName ?? Uri.tryParse(url)?.path ?? url;
    final m = RegExp(r'\.([a-z0-9]{2,4})$', caseSensitive: false)
        .firstMatch(src.split('?').first);
    return (m?.group(1) ?? 'mp4').toLowerCase();
  }
}

class _PageLink {
  final String url;
  final String label;
  const _PageLink(this.url, this.label);
}

/// Opens a movie's download page in a hidden browser and looks for direct
/// download links by itself, so the person never has to tap through the
/// third-party site:
///
///  1. loads the page and reads every link / button / script on it (three
///     times, because many pages build their links after loading);
///  2. direct files (.mp4, .mkv, .zip ...) are listed straight away;
///  3. links that look like "Download / 720p / Server" are checked on the
///     network first (some hand out a file even without an extension) and
///     otherwise opened and scanned too, a few pages deep;
///  4. a page with only a plain "Download" button gets that button tapped.
///
/// Pop-ups and ad hosts are blocked while scanning.
class DownloadScanner extends ChangeNotifier {
  DownloadScanner();

  static const _maxVisits = 4; // pages opened one after another
  static const _maxProbes = 12; // links checked on the network
  static const _scanDelays = [
    Duration(milliseconds: 800),
    Duration(milliseconds: 3500),
    Duration(milliseconds: 8000),
  ];
  static const _overallTimeout = Duration(seconds: 50);

  final List<FoundFile> files = [];
  bool scanning = false;
  String status = 'Looking for download links…';
  String cookie = '';

  late final WebViewController controller;
  final Set<String> _visited = {};
  final Set<String> _probed = {};
  final List<_PageLink> _queue = [];
  String _current = '';
  int _visits = 0;
  int _gen = 0; // changes with every page load, stale timers stop
  bool _clicked = false;
  bool _disposed = false;
  Timer? _overall;

  static final _adHost = RegExp(
      r'(^|\.)(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adsterra\.com|propellerads\.com|popads\.net|popcash\.net|exoclick\.com|clickadu\.com|hilltopads\.net|trafficjunky\.net|onclkds\.com|profitablecpmrate\.com|highperformanceformat\.com)$',
      caseSensitive: false);
  static final _fileExt = RegExp(
      r'\.(mp4|mkv|avi|mov|m4v|webm|zip|rar|7z|apk)(?:$|[?#&])',
      caseSensitive: false);

  void init() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (url) {
          _current = url;
          _gen++;
          _clicked = false;
        },
        onUrlChange: (c) {
          if (c.url != null) _current = c.url!;
        },
        onPageFinished: (url) {
          _current = url;
          _installGuard();
          final gen = _gen;
          for (var i = 0; i < _scanDelays.length; i++) {
            Future.delayed(_scanDelays[i], () {
              if (_disposed || gen != _gen || !scanning) return;
              unawaited(_scan(gen, last: i == _scanDelays.length - 1));
            });
          }
        },
      ));
    final p = controller.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(true);
    }
  }

  NavigationDecision _onNavigation(NavigationRequest r) {
    final uri = Uri.tryParse(r.url);
    if (uri == null) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    if (scheme != 'http' && scheme != 'https') return NavigationDecision.prevent;
    if (_adHost.hasMatch(uri.host)) return NavigationDecision.prevent;
    if (_fileExt.hasMatch(uri.path) ||
        uri.queryParameters.values.any(_fileExt.hasMatch)) {
      _addFile(r.url, '', _current); // a file: list it, don't open it
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _installGuard() async {
    try {
      await controller.runJavaScript(r'''
(function(){
  if(window.__damiScan) return; window.__damiScan = true;
  window.open = function(){ return null; };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a') : null;
    if (a && a.target === '_blank') a.target = '_self';
  }, true);
})();
''');
    } catch (_) {}
  }

  // -------------------------------------------------------------- control

  Future<void> start(String pageUrl, {List<String> directUrls = const []}) async {
    scanning = true;
    status = 'Looking for download links…';
    for (final u in directUrls) {
      _addFile(u, '', pageUrl);
    }
    _overall = Timer(_overallTimeout, _finish);
    _notify();
    if (pageUrl.startsWith('http')) {
      _open(pageUrl);
    } else {
      _finish();
    }
  }

  Future<void> rescan(String pageUrl) async {
    _overall?.cancel();
    files.clear();
    _visited.clear();
    _probed.clear();
    _queue.clear();
    _visits = 0;
    await start(pageUrl);
  }

  void _open(String url) {
    _visited.add(url);
    _visits++;
    status = _visits == 1
        ? 'Looking for download links…'
        : 'Checking another page ($_visits/$_maxVisits)…';
    _notify();
    unawaited(controller.loadRequest(Uri.parse(url)));
  }

  void _finish() {
    if (!scanning) return;
    scanning = false;
    _overall?.cancel();
    status = files.isEmpty
        ? 'No direct download link found on this page.'
        : '${files.length} download${files.length == 1 ? '' : 's'} found';
    try {
      unawaited(controller.loadRequest(Uri.parse('about:blank')));
    } catch (_) {}
    _notify();
  }

  // ---------------------------------------------------------------- scan

  static const _scanJs = r'''
(function(){
  var EXT=/\.(mp4|mkv|avi|mov|m4v|webm|zip|rar|7z|apk)(?:$|[?#&])/i;
  var PG=/download|server|mirror|quality|link|\b(2160|1080|720|480|360)p?\b|4k|\bhd\b/i;
  var out={files:[],pages:[]}, seen={};
  function abs(u){ try{ return new URL(u, location.href).href; }catch(e){ return null; } }
  function txt(el){
    var t=(el.innerText||el.textContent||el.getAttribute('title')||el.getAttribute('aria-label')||'').replace(/\s+/g,' ').trim();
    if(!t && el.parentElement){ t=(el.parentElement.innerText||'').replace(/\s+/g,' ').trim(); }
    return t.slice(0,90);
  }
  function add(u,label){
    u=abs(u); if(!u||!/^https?:/i.test(u)||seen[u]) return; seen[u]=1;
    if(EXT.test(u)){ out.files.push({url:u,label:label||''}); }
    else if(u.split('#')[0]!==location.href.split('#')[0] && PG.test((label||'')+' '+u)){
      out.pages.push({url:u,label:label||''});
    }
  }
  var attrs=['href','data-href','data-url','data-link','data-download','data-src','src'];
  var els=document.querySelectorAll('a[href],[data-href],[data-url],[data-link],[data-download],[data-src],video[src],source[src],iframe[src]');
  for(var i=0;i<els.length;i++){
    var el=els[i], l=txt(el);
    for(var j=0;j<attrs.length;j++){ var v=el.getAttribute(attrs[j]); if(v) add(v,l); }
  }
  try{
    var html=document.documentElement.innerHTML.replace(/\\\//g,'/');
    var re=/https?:\/\/[^"'\s<>\\)]+?\.(?:mp4|mkv|avi|mov|m4v|webm|zip|rar|7z|apk)(?:\?[^"'\s<>\\)]*)?/gi, m;
    while((m=re.exec(html))){ add(m[0].replace(/&amp;/g,'&'),''); }
  }catch(e){}
  out.cookie=document.cookie||'';
  return JSON.stringify(out);
})();
''';

  static const _clickJs = r'''
(function(){
  var els=document.querySelectorAll('button,a,[role=button],input[type=button],input[type=submit]');
  for(var i=0;i<els.length;i++){
    var el=els[i], t=(el.innerText||el.value||'').trim();
    var h=el.getAttribute('href')||'';
    if(/^(start\s+)?(free\s+)?(download|get\s+link|generate)/i.test(t) && (!h||h==='#'||/^javascript/i.test(h))){
      el.click(); return true;
    }
  }
  return false;
})();
''';

  Future<void> _scan(int gen, {required bool last}) async {
    Map<String, dynamic>? data;
    try {
      final r = await controller.runJavaScriptReturningResult(_scanJs);
      dynamic v = jsonDecode(r.toString());
      if (v is String) v = jsonDecode(v);
      if (v is Map<String, dynamic>) data = v;
    } catch (_) {}
    if (_disposed || gen != _gen || !scanning) return;

    var foundPages = 0;
    if (data != null) {
      final c = '${data['cookie'] ?? ''}';
      if (c.isNotEmpty) cookie = c;
      for (final f in (data['files'] as List? ?? const [])) {
        if (f is Map) _addFile('${f['url']}', '${f['label']}', _current);
      }
      for (final p in (data['pages'] as List? ?? const [])) {
        if (p is! Map) continue;
        final url = '${p['url']}';
        final host = Uri.tryParse(url)?.host ?? '';
        if (host.isEmpty || _adHost.hasMatch(host)) continue;
        if (_visited.contains(url) || _queue.any((q) => q.url == url)) continue;
        _queue.add(_PageLink(url, '${p['label']}'));
        foundPages++;
      }
    }

    if (!last) return;

    // Nothing at all on this page: tap a plain "Download" button once.
    if (files.isEmpty && foundPages == 0 && _queue.isEmpty && !_clicked) {
      _clicked = true;
      try {
        await controller.runJavaScript(_clickJs);
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 3));
      if (_disposed || gen != _gen || !scanning) return;
      await _scan(gen, last: false);
    }
    await _next(gen);
  }

  /// Go on to the next promising link, or finish.
  Future<void> _next(int gen) async {
    while (_queue.isNotEmpty && _visits < _maxVisits && _probed.length < _maxProbes) {
      final link = _queue.removeAt(0);
      if (_visited.contains(link.url)) continue;
      _probed.add(link.url);
      final info = await DownloadManager.instance
          .checkLink(link.url, referer: _current, cookie: cookie);
      if (_disposed || !scanning) return;
      if (info.isFile) {
        _addFile(link.url, link.label, _current,
            fileName: info.fileName, total: info.total);
        continue;
      }
      // A web page: open it and scan it too.
      _open(link.url);
      return; // this page's own scan continues the search
    }
    _finish();
  }

  // --------------------------------------------------------------- files

  void _addFile(String url, String label, String referer,
      {String? fileName, int? total}) {
    final clean = url.trim();
    if (!clean.startsWith('http') || files.any((f) => f.url == clean)) return;
    final host = Uri.tryParse(clean)?.host ?? '';
    if (_adHost.hasMatch(host)) return;
    final f = FoundFile(clean, referer, label)
      ..fileName = fileName
      ..total = total;
    files.add(f);
    status = '${files.length} download${files.length == 1 ? '' : 's'} found';
    _notify();
    if (total == null) unawaited(_enrich(f));
  }

  /// Fills in the real size / name, and drops links that are really pages.
  Future<void> _enrich(FoundFile f) async {
    final info = await DownloadManager.instance
        .checkLink(f.url, referer: f.referer, cookie: cookie);
    if (_disposed) return;
    if (info.isPage) {
      files.remove(f);
    } else if (info.isFile) {
      f.total = info.total;
      f.fileName ??= info.fileName;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _overall?.cancel();
    try {
      unawaited(controller.loadRequest(Uri.parse('about:blank')));
    } catch (_) {}
    super.dispose();
  }
}
