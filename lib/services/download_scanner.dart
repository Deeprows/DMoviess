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
  String label; // text printed next to the button, e.g. "HUBCDN | 480P | 390MB"
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

  /// Server name from the listing label, e.g. "HUBCDN" in "HUBCDN | 480P | 390MB".
  String? get server {
    if (!label.contains('|')) return null;
    final s = label.split('|').first.trim();
    return s.isEmpty || s.length > 20 ? null : s;
  }

  /// File extension, mp4 when nothing says otherwise.
  String get extension {
    final src = fileName ?? Uri.tryParse(url)?.path ?? url;
    final m = RegExp(r'\.([a-z0-9]{2,4})$', caseSensitive: false)
        .firstMatch(src.split('?').first);
    return (m?.group(1) ?? 'mp4').toLowerCase();
  }
}

class _Entry {
  final String? url; // null when the button has no link and must be tapped
  final String label; // e.g. "HUBCDN | 480P | 390MB"
  const _Entry(this.url, this.label);
}

/// Reads a movie's download page in a hidden browser and walks through the
/// in-between pages by itself, so the person never has to tap through the
/// third-party site.
///
/// For a listing like web.nxsha.app (Servers > "HUBCDN | 480P" + Download):
///
///  1. the listing is opened, collapsed servers are expanded and every
///     "Download" button/link is collected with its quality/size label;
///  2. each entry is followed in turn: a link is probed (some hand out the
///     file directly), otherwise its page is opened; a button with no link
///     is tapped on the listing;
///  3. on every in-between page the real file links are looked for, and the
///     best "Generate / Direct download / Continue" button is tapped (also
///     waiting for countdown buttons), a few pages deep;
///  4. every file found shows up in the list with the entry's label.
///
/// Pop-ups and ad hosts are blocked while scanning.
class DownloadScanner extends ChangeNotifier {
  DownloadScanner();

  static const _maxEntries = 12; // listing entries followed
  static const _maxRounds = 14; // look/tap rounds per entry
  static const _maxProbes = 60; // links checked on the network
  static const _entryTimeout = Duration(seconds: 40);
  static const _overallTimeout = Duration(minutes: 8);

  final List<FoundFile> files = [];
  bool scanning = false;
  String status = 'Looking for download links…';
  String cookie = '';

  late final WebViewController controller;
  final Set<String> _probed = {};
  String _current = '';
  String _entryLabel = '';
  int _gen = 0; // changes with every page load
  int _run = 0; // changes with every scan, older scans stop
  Completer<void>? _loaded;
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
          if (_loaded == null || _loaded!.isCompleted) _loaded = Completer<void>();
        },
        onUrlChange: (c) {
          if (c.url != null) _current = c.url!;
        },
        onPageFinished: (url) {
          _current = url;
          unawaited(_installGuard());
          if (_loaded != null && !_loaded!.isCompleted) _loaded!.complete();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true &&
              _loaded != null &&
              !_loaded!.isCompleted) {
            _loaded!.complete();
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
      _addFile(r.url, _entryLabel, _current); // a file: list it, don't open it
      return NavigationDecision.prevent;
    }
    // A page without an extension may still be the file (the webview would
    // silently drop it as a download), so check it quietly on the side.
    if (scanning) unawaited(_probeNavigation(r.url));
    return NavigationDecision.navigate;
  }

  Future<void> _probeNavigation(String url) async {
    if (_probed.contains(url) || _probed.length >= _maxProbes) return;
    _probed.add(url);
    final info = await DownloadManager.instance
        .checkLink(url, referer: _current, cookie: cookie);
    if (_disposed || !info.isFile) return;
    _addFile(url, _entryLabel, _current,
        fileName: info.fileName, total: info.total);
  }

  Future<void> _installGuard() async {
    // window.open used to be blocked, but many sites open the in-between page
    // that way. It now loads in this same hidden browser instead (ad hosts are
    // refused by the navigation filter above).
    await _js(r'''
(function(){
  if(window.__damiScan) return 0; window.__damiScan = true;
  window.open = function(u){ try{ if(u) location.href = u; }catch(e){} return null; };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a') : null;
    if (a && a.target === '_blank') a.target = '_self';
  }, true);
  return 1;
})();
''');
  }

  // -------------------------------------------------------------- control

  bool _alive(int run) => !_disposed && run == _run && scanning;

  Future<void> start(String pageUrl, {List<String> directUrls = const []}) async {
    final run = ++_run;
    scanning = true;
    status = 'Looking for download links…';
    for (final u in directUrls) {
      _addFile(u, '', pageUrl);
    }
    _overall?.cancel();
    _overall = Timer(_overallTimeout, () {
      if (run == _run) _finish();
    });
    _notify();
    if (!pageUrl.startsWith('http')) {
      _finish();
      return;
    }
    try {
      await _scanSite(pageUrl, run);
    } catch (_) {}
    if (run == _run) _finish();
  }

  Future<void> rescan(String pageUrl) async {
    _run++; // stops the scan in progress
    _overall?.cancel();
    files.clear();
    _probed.clear();
    _entryLabel = '';
    await start(pageUrl);
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

  // ---------------------------------------------------------------- steps

  Future<void> _scanSite(String pageUrl, int run) async {
    await _load(pageUrl, run);
    if (!_alive(run)) return;

    // The nxsha listing renders server cards lazily. Keep scanning after the
    // first button appears: expanding one server can reveal more cards, and
    // the page may hydrate its remaining buttons a moment later.
    final entries = <String, _Entry>{};
    var stableRounds = 0;
    for (var round = 0; round < 8 && _alive(run); round++) {
      await _wait(round == 0 ? 1800 : 1300);
      if (!_alive(run)) return;
      final before = entries.length;
      for (var pass = 0; pass < 3; pass++) {
        for (final e in await _collectEntries()) {
          final key = '${e.url ?? ''}|${e.label}';
          entries.putIfAbsent(key, () => e);
        }
        final opened = await _js(_expandJs);
        if (opened is! num || opened <= 0) break;
        await _wait(500);
      }
      await _scanPageFiles(pageUrl, probePages: false);
      if (entries.length == before) {
        stableRounds++;
      } else {
        stableRounds = 0;
      }
      // Require two quiet passes so a late-rendered server card isn't missed.
      if (stableRounds >= 2) break;
    }
    if (!_alive(run)) return;

    if (entries.isEmpty) {
      // Not a listing: treat the page itself as an in-between page.
      await _walk(run, pageUrl);
      return;
    }

    final list = entries.values.take(_maxEntries).toList();
    for (var i = 0; i < list.length && _alive(run); i++) {
      final e = list[i];
      _entryLabel = e.label;
      status = 'Checking ${e.label.isEmpty ? 'link' : e.label} '
          '(${i + 1}/${list.length})'
          '${files.isEmpty ? '' : ' · ${files.length} found'}…';
      _notify();
      try {
        await _resolveEntry(e, pageUrl, run);
      } catch (_) {}
    }
  }

  /// Follows one Download button of the listing to the real file(s).
  Future<void> _resolveEntry(_Entry e, String listUrl, int run) async {
    if (e.url != null) {
      final info = await DownloadManager.instance
          .checkLink(e.url!, referer: listUrl, cookie: cookie);
      if (!_alive(run)) return;
      if (info.isFile) {
        _addFile(e.url!, e.label, listUrl,
            fileName: info.fileName, total: info.total);
        return;
      }
      await _load(e.url!, run, referer: listUrl);
    } else {
      // A button without a link: tap it on a freshly opened listing.
      await _load(listUrl, run);
      if (!_alive(run)) return;
      await _wait(1500);
      await _js(_expandJs);
      await _wait(600);
      final now = await _collectEntries();
      final idx = now.indexWhere((n) => n.label == e.label);
      if (idx < 0) return;
      final gen = _gen;
      await _js('''(function(){var el=document.querySelector('[data-dami="$idx"]');
        if(el){el.scrollIntoView&&el.scrollIntoView();el.click();return 1}return 0})();''');
      await _wait(1200);
      if (_gen != gen) await _waitLoaded();
    }
    if (!_alive(run)) return;
    await _walk(run, listUrl);
  }

  /// On an in-between page: look for files, otherwise tap the best button
  /// ("Generate direct link", "Continue", a counting-down "Download" ...) and
  /// look again, until a file shows up or nothing is left to try.
  Future<void> _walk(int run, String referer) async {
    final deadline = DateTime.now().add(_entryTimeout);
    var idle = 0;
    for (var round = 0; round < _maxRounds; round++) {
      if (!_alive(run) || DateTime.now().isAfter(deadline)) return;
      await _wait(round == 0 ? 1500 : 2500);
      if (!_alive(run)) return;
      if (await _scanPageFiles(referer) > 0) return;
      final gen = _gen;
      final clicked = await _js(_clickJs);
      if (clicked is String && clicked.isNotEmpty) {
        idle = 0;
        await _wait(1200);
        if (_gen != gen) await _waitLoaded();
      } else if (++idle >= 3) {
        return;
      }
    }
  }

  Future<void> _load(String url, int run, {String? referer}) async {
    _loaded = Completer<void>();
    try {
      await controller.loadRequest(Uri.parse(url),
          headers: referer == null ? const {} : {'Referer': referer});
    } catch (_) {}
    await _waitLoaded();
  }

  Future<void> _waitLoaded() async {
    final c = _loaded;
    if (c == null) return;
    try {
      await c.future.timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<dynamic> _js(String code) async {
    try {
      final r = await controller.runJavaScriptReturningResult(code);
      dynamic v = r is String ? r : r.toString();
      for (var i = 0; i < 2 && v is String; i++) {
        try {
          v = jsonDecode(v);
        } catch (_) {
          break;
        }
      }
      return v;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ JS

  /// Opens collapsed server sections. Returns how many it opened.
  static const _expandJs = r'''
(function(){
  var n=0, done=window.__damiExp||(window.__damiExp=[]);
  function dl(el){
    var a=el.querySelectorAll('a,button,[role=button]');
    for(var i=0;i<a.length;i++){ if(/^\s*download/i.test(a[i].innerText||'')) return true; }
    return false;
  }
  [].slice.call(document.querySelectorAll('[aria-expanded="false"]')).forEach(function(el){
    if(done.indexOf(el)<0){ done.push(el); try{el.click(); n++;}catch(e){} }
  });
  [].slice.call(document.querySelectorAll('details:not([open])')).forEach(function(d){
    d.open=true; n++;
  });
  [].slice.call(document.querySelectorAll('button,[role=button]')).forEach(function(el){
    if(done.indexOf(el)>=0) return;
    var t=(el.innerText||'').trim();
    if(t || !el.querySelector('svg,img,i')) return;
    var c=el, ok=false;
    for(var i=0;i<3&&c.parentElement;i++){ c=c.parentElement; if(dl(c)){ ok=false; break; } ok=true; }
    if(ok && /server|hd|sd|fhd|[0-9]{3,4}p|4k|bkl|cdn|drive/i.test((c.innerText||'').slice(0,120))){
      done.push(el); try{el.click(); n++;}catch(e){}
    }
  });
  // nxsha server panels often use clickable divs instead of native buttons.
  [].slice.call(document.querySelectorAll('div,section,article')).forEach(function(el){
    if(done.indexOf(el)>=0) return;
    var t=(el.innerText||'').replace(/\s+/g,' ').trim();
    if(!t||t.length>100||!/\b(server|4k|hd\/sd\/fhd|bkl|cdn|drive|\d{3,4}p)\b/i.test(t)) return;
    if(el.querySelectorAll('a,button,[role=button]').length>0) return;
    var r=el.getBoundingClientRect();
    if(r.width<180||r.height<35||r.height>180) return;
    done.push(el); try{el.click();n++;}catch(e){}
  });
  return n;
})();
''';

  /// Every "Download" button/link of the listing, with the quality/size label
  /// printed next to it. Each one is tagged data-dami="index" for tapping.
  static const _entriesJs = r'''
(function(){
  var DL=/download|get\s+link|direct\s+download/i;
  var all=[].slice.call(document.querySelectorAll('a,button,[role=button],input[type=button],input[type=submit]'));
  function text(el){return (el.innerText||el.textContent||el.value||el.getAttribute('aria-label')||'').replace(/\s+/g,' ').trim();}
  function isDl(el){var t=text(el);return t.length>0&&t.length<=55&&DL.test(t);}
  function visible(el){var r=el.getBoundingClientRect(),s=getComputedStyle(el);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';}
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
  var out=[], seen={};
  all.forEach(function(el){
    if(!isDl(el)||!visible(el))return;
    var url=null;
    if(el.tagName==='A'){
      var h=el.getAttribute('href')||'';
      if(h&&h!=='#'&&!/^javascript/i.test(h)){try{url=new URL(h,location.href).href}catch(e){}}
    }
    if(url&&url.split('#')[0]===location.href.split('#')[0])url=null;
    var label=labelFor(el);
    // Include link-less Download buttons: these are common on nxsha's server cards.
    var key=(url||'button')+'|'+label;
    if(seen[key])return;
    seen[key]=1;
    el.setAttribute('data-dami',String(out.length));
    out.push({url:url,label:label});
  });
  return JSON.stringify(out);
})();
''';

  /// Direct files / "Download [Server]" links on the current page.
  static const _scanJs = r'''
(function(){
  var EXT=/\.(mp4|mkv|avi|mov|m4v|webm|zip|rar|7z|apk)(?:$|[?#&])/i;
  var PG=/download|server|mirror|direct|instant|fsl|pixel|gbps|cdn|\bhd\b|\b(2160|1080|720|480|360)p?\b|4k/i;
  var BAD=/telegram|whatsapp|join|login|register|trailer|torrent|magnet|facebook|twitter|instagram|youtube/i;
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
    else if(u.split('#')[0]!==location.href.split('#')[0] && PG.test(label||'') && !BAD.test((label||'')+' '+u)){
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

  /// Taps the most promising button of an in-between page, once per element.
  /// Returns its text, or '' when there is nothing worth tapping.
  static const _clickJs = r'''
(function(){
  var BAD=/telegram|whatsapp|join|log\s?in|sign\s?in|register|subscribe|trailer|watch|stream|torrent|magnet|close|cancel|report|dmca|contact|share|home|back|premium|vpn|install|adblock|resume/i;
  var GOOD=[
    /generate.*(link|download)|get\s+(the\s+)?(download\s+)?link|create.*link/i,
    /direct\s*download|instant\s*download|fast\s*download|download\s*(now|file|\[|link)|start\s*download|click\s*(here\s*)?(to\s*)?download/i,
    /^(continue|proceed|verify|go\s+to\s+(link|download)|get\s+started|next)\b/i,
    /download/i
  ];
  var done=window.__damiDone||(window.__damiDone=[]);
  var els=[].slice.call(document.querySelectorAll('a,button,[role=button],input[type=button],input[type=submit]'));
  var best=null, bs=99, bt='';
  els.forEach(function(el){
    if(done.indexOf(el)>=0) return;
    if(el.disabled||el.getAttribute('aria-disabled')==='true') return;
    var cs=window.getComputedStyle(el);
    if(cs.display==='none'||cs.visibility==='hidden') return;
    var t=(el.innerText||el.value||'').replace(/\s+/g,' ').trim();
    if(!t||t.length>70||BAD.test(t)) return;
    for(var i=0;i<GOOD.length;i++){
      if(GOOD[i].test(t)){ if(i<bs){ bs=i; best=el; bt=t; } break; }
    }
  });
  if(!best) return '';
  done.push(best);
  try{ best.scrollIntoView&&best.scrollIntoView(); }catch(e){}
  best.click();
  return bt;
})();
''';

  Future<List<_Entry>> _collectEntries() async {
    final v = await _js(_entriesJs);
    final out = <_Entry>[];
    if (v is List) {
      for (final e in v) {
        if (e is Map) {
          final u = e['url'];
          out.add(_Entry(u is String && u.isNotEmpty ? u : null, '${e['label'] ?? ''}'));
        }
      }
    }
    return out;
  }

  /// Lists the files on the current page. Returns how many it recognised
  /// (new or already listed), so the caller knows this page delivered.
  Future<int> _scanPageFiles(String referer, {bool probePages = true}) async {
    final data = await _js(_scanJs);
    if (!scanning || data is! Map) return 0;
    var hits = 0;
    final c = '${data['cookie'] ?? ''}';
    if (c.isNotEmpty) cookie = c;
    final here = _current;
    for (final f in (data['files'] as List? ?? const [])) {
      if (f is Map) {
        final l = '${f['label']}';
        _addFile('${f['url']}', _entryLabel.isEmpty ? l : _entryLabel, here);
        hits++;
      }
    }
    if (!probePages) return hits;
    // "Download [Server]" links without an extension: ask the server.
    var probes = 0;
    for (final p in (data['pages'] as List? ?? const [])) {
      if (p is! Map || probes >= 8 || _probed.length >= _maxProbes) continue;
      final url = '${p['url']}';
      final host = Uri.tryParse(url)?.host ?? '';
      if (host.isEmpty || _adHost.hasMatch(host) || _probed.contains(url)) continue;
      _probed.add(url);
      probes++;
      final info = await DownloadManager.instance
          .checkLink(url, referer: here, cookie: cookie);
      if (_disposed || !scanning) return hits;
      if (info.isFile) {
        final l = '${p['label']}';
        _addFile(url, _entryLabel.isEmpty ? l : _entryLabel, here,
            fileName: info.fileName, total: info.total);
        hits++;
      }
    }
    return hits;
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
    if (!scanning) {
      status = '${files.length} download${files.length == 1 ? '' : 's'} found';
    }
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
    _run++;
    _overall?.cancel();
    try {
      unawaited(controller.loadRequest(Uri.parse('about:blank')));
    } catch (_) {}
    super.dispose();
  }
}

