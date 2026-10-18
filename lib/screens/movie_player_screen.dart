import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../main.dart';
import '../models/movie.dart';
import '../services/ad_shield.dart';
import '../services/app_preferences.dart';
import '../services/background_playback.dart';
import '../services/download_manager.dart';
import '../services/movie_library.dart';
import '../services/player_html.dart';
import '../services/stream_resolver.dart';
import 'browser_screen.dart';

class MoviePlayerScreen extends StatefulWidget {
  final Movie movie;
  const MoviePlayerScreen({super.key, required this.movie});

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _pip = MethodChannel('damimovies/pip');

  late final WebViewController _controller;
  late final List<({String url, String referer, String agent})> _sources;
  int _sourceIndex = 0;
  int _progress = 0;
  bool _loading = true;
  bool _error = false;
  bool _fullscreen = false;
  bool _landscape = false;
  bool _pipAvailable = false;
  bool _switching = false;
  bool _playbackServiceActive = false;
  bool _videoPlaying = false;
  bool _resumePrompted = false;
  String? _errorDetail;
  Timer? _loadTimeout;
  Widget? _fullscreenWidget;
  VoidCallback? _fullscreenHidden;

  String get _currentUrl => _sources.isEmpty ? '' : _sources[_sourceIndex.clamp(0, _sources.length - 1).toInt()].url;
  String get _currentReferer => _sources.isEmpty ? '' : _sources[_sourceIndex.clamp(0, _sources.length - 1).toInt()].referer;
  String get _currentAgent => _sources.isEmpty ? '' : _sources[_sourceIndex.clamp(0, _sources.length - 1).toInt()].agent;
  ResolvedStream get _stream => StreamResolver.resolve(_currentUrl);
  bool get _isImmersive => _fullscreen || _landscape || _fullscreenWidget != null;

  List<({String url, String referer, String agent})> _buildSources() {
    final m = widget.movie;
    final result = <({String url, String referer, String agent})>[];
    void add(String url, String referer, String agent) {
      final clean = url.trim();
      if (clean.isEmpty || result.any((entry) => entry.url == clean)) return;
      result.add((url: clean, referer: referer.trim(), agent: agent.trim()));
    }

    add(m.url, m.referer, m.userAgent);
    add(m.altUrl, m.altReferer.isNotEmpty ? m.altReferer : m.referer,
        m.altUserAgent.isNotEmpty ? m.altUserAgent : m.userAgent);
    add(m.thirdUrl, m.thirdReferer, m.thirdUserAgent);
    return result;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sources = _buildSources();
    unawaited(MovieLibrary.instance.recordOpened(widget.movie));
    _checkPip();
    if (AppPreferences.instance.keepScreenAwake) unawaited(WakelockPlus.enable());

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(AppConfig.userAgent)
      ..addJavaScriptChannel('DamiPlayback', onMessageReceived: _onPlaybackMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            _loading = true;
            _progress = 5;
            _error = false;
            _errorDetail = null;
          });
          _armTimeout();
          _keepVisible();
          _applyShield();
        },
        onProgress: (value) {
          if (mounted) setState(() => _progress = value.clamp(0, 100).toInt());
          _applyShield();
        },
        onPageFinished: (url) {
          _loadTimeout?.cancel();
          if (mounted) setState(() {
            _loading = false;
            _progress = 100;
          });
          _keepVisible();
          _applyShield();
          _installVideoHooks();
          if (_stream.usesHtmlPlayer) unawaited(_offerResume());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            _loadTimeout?.cancel();
            setState(() {
              _loading = false;
              _error = true;
              _errorDetail = 'The video page could not be loaded. Try Reload or Switch player.';
            });
          }
        },
      ));

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: _showCustomFullscreen,
        onHideCustomWidget: _hideCustomFullscreen,
      );
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        unawaited(cookies.setAcceptThirdPartyCookies(platform, true));
      }
    }

    if (AppPreferences.instance.backgroundPlayback) {
      _startBackgroundControls();
    }
    _loadSource();
  }

  Future<void> _startBackgroundControls() async {
    if (!AppPreferences.instance.backgroundPlayback) return;
    await BackgroundPlayback.start(
      widget.movie.title,
      _onStopTapped,
      onPlay: () => _runVideoAction('play'),
      onPause: () => _runVideoAction('pause'),
      onSeekBy: (seconds) => _runVideoAction('seekBy', seconds: seconds),
    );
    _playbackServiceActive = true;
  }

  Future<void> _onStopTapped() async {
    try { await _controller.runJavaScript(_videosJs('v.pause()')); } catch (_) {}
    if (mounted) await Navigator.of(context).maybePop();
  }

  String _videosJs(String action) =>
      "document.querySelectorAll('video').forEach(function(v){try{$action}catch(e){}});";

  void _runVideoAction(String action, {int seconds = 0}) {
    if (action == 'seekBy') {
      _controller.runJavaScript(
        "document.querySelectorAll('video').forEach(function(v){try{v.currentTime=Math.max(0,(v.currentTime||0)+($seconds))}catch(e){}});",
      ).catchError((_) {});
    } else {
      _controller.runJavaScript(_videosJs(action == 'play' ? 'v.play()' : 'v.pause()')).catchError((_) {});
    }
  }

  Future<void> _offerResume() async {
    if (_resumePrompted) return;
    _resumePrompted = true;
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    final fraction = await MovieLibrary.instance.resumeFraction(widget.movie);
    if (!mounted || fraction < 0.02 || fraction > 0.97) return;
    final percent = (fraction * 100).round();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Continue from $percent%?'),
      duration: const Duration(seconds: 12),
      action: SnackBarAction(
        label: 'RESUME',
        onPressed: () => unawaited(_seekToFraction(fraction)),
      ),
    ));
  }

  Future<void> _seekToFraction(double fraction) async {
    final progress = fraction.clamp(0.0, 0.97).toDouble();
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted) return;
      try {
        final result = await _controller.runJavaScriptReturningResult(
          '(function(){var v=document.querySelector("video");if(!v||!isFinite(v.duration)||v.duration<=0)return "wait";v.currentTime=v.duration*$progress;var p=v.play();if(p&&p.catch)p.catch(function(){});return "ok";})()',
        );
        if (result.toString().contains('ok')) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This video source does not support resume playback.')),
      );
    }
  }

  void _onPlaybackMessage(JavaScriptMessage message) {
    try {
      final value = jsonDecode(message.message);
      if (value is! Map) return;
      final position = (value['position'] as num?)?.toDouble() ?? 0;
      final duration = (value['duration'] as num?)?.toDouble() ?? 0;
      final playing = value['playing'] == true;
      if (playing != _videoPlaying) {
        _videoPlaying = playing;
        if (_playbackServiceActive) unawaited(BackgroundPlayback.setPlaying(playing));
      }
      if (duration > 0 && position >= 0) {
        unawaited(MovieLibrary.instance.setProgress(widget.movie, position, duration));
      }
    } catch (_) {}
  }

  void _installVideoHooks() {
    _controller.runJavaScript(r'''
      (function(){
        function hook(v){
          if(!v || v.__damiPlaybackHooked)return;
          v.__damiPlaybackHooked=true;
          var last=0;
          function send(){try{
            if(window.DamiPlayback){var n=Date.now();if(n-last<12000&&!v.ended)return;last=n;
              DamiPlayback.postMessage(JSON.stringify({position:v.currentTime||0,duration:v.duration||0,playing:!v.paused,ended:!!v.ended}));}
          }catch(e){}}
          ['timeupdate','play','pause','ended','durationchange'].forEach(function(e){v.addEventListener(e,send)});
        }
        function scan(){document.querySelectorAll('video').forEach(hook)}
        scan();
        if(!window.__damiVideoObserver){window.__damiVideoObserver=new MutationObserver(scan);window.__damiVideoObserver.observe(document.documentElement||document.body,{childList:true,subtree:true})}
      })();
    ''').catchError((_) {});
  }

  void _keepVisible() {
    _controller.runJavaScript(BackgroundPlayback.keepVisibleJs).catchError((_) {});
  }

  void _rememberPlaying() {
    _controller.runJavaScript(BackgroundPlayback.rememberPlayingJs).catchError((_) {});
  }

  void _resumePlaying() {
    _controller.runJavaScript(BackgroundPlayback.resumePlayingJs).catchError((_) {});
  }

  void _armTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 28), () {
      if (!mounted || !_loading) return;
      setState(() {
        _loading = false;
        _progress = 100;
        _error = true;
        _errorDetail = 'This source is taking too long to respond. Try switching to another player.';
      });
    });
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob' || scheme == 'javascript') {
      return NavigationDecision.navigate;
    }
    if (scheme != 'http' && scheme != 'https') return NavigationDecision.prevent;
    if (AppPreferences.instance.adShield && AdShield.isAdUrl(request.url)) {
      return NavigationDecision.prevent;
    }
    if (!request.isMainFrame && AppPreferences.instance.adShield && AdShield.isAdSubframe(request.url)) {
      return NavigationDecision.prevent;
    }
    if (request.isMainFrame && isDirectMovieDownload(request.url)) {
      unawaited(_startDownload(request.url));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _applyShield() async {
    if (!AppPreferences.instance.adShield) return;
    try { await _controller.runJavaScript(AdShield.adShieldJs); } catch (_) {}
  }

  Future<void> _checkPip() async {
    try {
      final available = await _pip.invokeMethod<bool>('isAvailable') ?? false;
      if (mounted) setState(() => _pipAvailable = available);
    } catch (_) {}
  }

  String _playerBase(String streamUrl) {
    if (_currentReferer.startsWith('http://') || _currentReferer.startsWith('https://')) {
      return _currentReferer;
    }
    if (streamUrl.toLowerCase().startsWith('http://')) {
      return AppConfig.playerOrigin.replaceFirst('https://', 'http://');
    }
    return AppConfig.playerOrigin;
  }

  Future<void> _loadSource() async {
    _loadTimeout?.cancel();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _progress = 5;
      _error = false;
      _errorDetail = null;
    });
    _armTimeout();
    final stream = _stream;
    if (stream.kind == StreamKind.invalid) {
      _loadTimeout?.cancel();
      setState(() {
        _loading = false;
        _error = true;
        _errorDetail = 'This title does not have a valid playback URL.';
      });
      return;
    }
    try {
      await _controller.setUserAgent(_currentAgent.isNotEmpty ? _currentAgent : AppConfig.userAgent);
      if (stream.usesHtmlPlayer) {
        await _controller.loadHtmlString(
          buildPlayerHtml(stream, lowQuality: AppPreferences.instance.lowQuality),
          baseUrl: _playerBase(stream.url),
        );
      } else {
        final headers = <String, String>{
          if (_currentReferer.isNotEmpty) 'Referer': _currentReferer,
        };
        await _controller.loadRequest(Uri.parse(stream.url), headers: headers);
      }
    } catch (_) {
      _loadTimeout?.cancel();
      if (mounted) setState(() {
        _loading = false;
        _error = true;
        _errorDetail = 'Could not open this video source.';
      });
    }
  }

  Future<void> _switchSource() async {
    if (_sources.length < 2 || _switching) {
      if (_sources.length < 2 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No backup player is configured for this title.')));
      }
      return;
    }
    setState(() {
      _switching = true;
      _sourceIndex = (_sourceIndex + 1) % _sources.length;
    });
    await _loadSource();
    if (mounted) setState(() => _switching = false);
  }

  Future<void> _toggleLandscape() async {
    final next = !_landscape;
    setState(() {
      _landscape = next;
      _fullscreen = next;
    });
    await SystemChrome.setPreferredOrientations(next
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (!mounted) return;
    setState(() => _fullscreen = enabled);
    await SystemChrome.setEnabledSystemUIMode(enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (!enabled && _landscape) {
      setState(() => _landscape = false);
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
  }

  void _showCustomFullscreen(Widget child, void Function() onHidden) {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = child;
      _fullscreenHidden = onHidden;
    });
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _hideCustomFullscreen() {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = null;
      _fullscreenHidden = null;
    });
    SystemChrome.setPreferredOrientations(_landscape
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(_isImmersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  void _onBack() {
    if (_fullscreenWidget != null) {
      _fullscreenHidden?.call();
      _hideCustomFullscreen();
    } else if (_landscape) {
      _toggleLandscape();
    } else if (_fullscreen) {
      _setFullscreen(false);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _currentUrl));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Player link copied')));
  }

  Future<void> _share() async {
    await Share.share('${widget.movie.title}\nWatch on DamiMovies\n${widget.movie.url}');
  }

  Future<void> _cast() async {
    for (final action in const ['android.settings.CAST_SETTINGS', 'android.settings.WIFI_DISPLAY_SETTINGS']) {
      try {
        await AndroidIntent(action: action).launch();
        return;
      } catch (_) {}
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open Cast or Smart View from your phone quick settings.')));
  }

  Future<void> _enterPip() async {
    try {
      final ok = await _pip.invokeMethod<bool>('enter') ?? false;
      if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Picture-in-picture is not available on this device.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Picture-in-picture is not available in this build.')));
    }
  }

  Future<void> _startDownload(String url) async {
    final error = await DownloadManager.instance.enqueue(url, referer: _currentReferer.isNotEmpty ? _currentReferer : _currentUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Download started'), duration: const Duration(seconds: 6)));
  }

  Future<void> _saveWatchLater() async {
    final added = await MovieLibrary.instance.toggleSaved(widget.movie);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? 'Saved to Watch Later' : 'Removed from Watch Later')));
  }

  Future<void> _downloadPage() async {
    final url = widget.movie.downloadUrl.trim();
    if (url.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No download page is available for this title.')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(initialUrl: url)));
  }

  Future<void> _openBrowser() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(initialUrl: _currentUrl)));
  }

  Future<void> _toggleQuality() async {
    final prefs = AppPreferences.instance;
    await prefs.setLowQuality(!prefs.lowQuality);
    if (_stream.usesHtmlPlayer) await _loadSource();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(prefs.lowQuality ? 'Low quality enabled for direct HLS streams' : 'Automatic quality enabled')));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.inactive) {
      _rememberPlaying();
      unawaited(WakelockPlus.disable());
      for (final ms in const [400, 1500]) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (mounted && AppPreferences.instance.backgroundPlayback) _resumePlaying();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (AppPreferences.instance.keepScreenAwake) unawaited(WakelockPlus.enable());
      _resumePlaying();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadTimeout?.cancel();
    if (_playbackServiceActive) unawaited(BackgroundPlayback.stop(_onStopTapped));
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black.withValues(alpha: .28), child: Center(child: CircularProgressIndicator(color: appRed))))),
          if (_error) Positioned.fill(child: Container(
            color: const Color(0xE6080B10),
            padding: const EdgeInsets.all(26),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.play_disabled_rounded, color: Colors.white60, size: 46),
              const SizedBox(height: 14),
              const Text('Unable to play this source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              Text(_errorDetail ?? 'Try reloading or switching player sources.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.4)),
              const SizedBox(height: 20),
              Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8, children: [
                FilledButton.icon(onPressed: _loadSource, icon: const Icon(Icons.refresh_rounded), label: const Text('Reload')),
                if (_sources.length > 1) OutlinedButton.icon(onPressed: _switchSource, icon: const Icon(Icons.swap_horiz_rounded), label: const Text('Switch player')),
              ]),
            ])),
          )),
          if (_fullscreen) Positioned(right: 12, top: 12, child: SafeArea(child: IconButton.filledTonal(tooltip: 'Exit fullscreen', onPressed: () => _setFullscreen(false), icon: const Icon(Icons.fullscreen_exit_rounded)))),
        ],
      ),
    );

    return PopScope(
      canPop: !_isImmersive,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onBack(); },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isImmersive ? null : AppBar(
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.movie.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            Text('${_sourceIndex + 1}/${_sources.length} · ${_stream.label}${widget.movie.rating.isNotEmpty ? ' · ★ ${widget.movie.rating}' : ''}', style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ]),
          actions: [
            IconButton(tooltip: 'Reload', onPressed: _loadSource, icon: const Icon(Icons.refresh_rounded)),
            if (_sources.length > 1) IconButton(tooltip: 'Switch player', onPressed: _switchSource, icon: const Icon(Icons.swap_horiz_rounded)),
            IconButton(tooltip: 'Rotate / landscape', onPressed: _toggleLandscape, icon: const Icon(Icons.screen_rotation_alt_rounded)),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'copy': _copyLink(); break;
                  case 'share': _share(); break;
                  case 'cast': _cast(); break;
                  case 'pip': _enterPip(); break;
                  case 'fullscreen': _setFullscreen(true); break;
                  case 'download': _downloadPage(); break;
                  case 'browser': _openBrowser(); break;
                  case 'quality': _toggleQuality(); break;
                  case 'save': _saveWatchLater(); break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'save', child: Text('Add / remove Watch Later')),
                const PopupMenuItem(value: 'download', child: Text('Open download page')),
                const PopupMenuItem(value: 'browser', child: Text('Open source in browser')),
                const PopupMenuItem(value: 'copy', child: Text('Copy player link')),
                const PopupMenuItem(value: 'share', child: Text('Share movie')),
                const PopupMenuItem(value: 'cast', child: Text('Cast / display settings')),
                PopupMenuItem(value: 'quality', child: Text(AppPreferences.instance.lowQuality ? 'Use automatic quality' : 'Prefer low quality')),
                if (_pipAvailable) const PopupMenuItem(value: 'pip', child: Text('Picture-in-picture')),
                const PopupMenuItem(value: 'fullscreen', child: Text('Fullscreen')),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(children: [
              if (!_isImmersive) Container(height: 3, alignment: Alignment.centerLeft, child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: MediaQuery.sizeOf(context).width * (_progress.clamp(0, 100) / 100), color: appRed)),
              Expanded(child: video),
              if (!_isImmersive) Container(
                color: appSurface,
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                  _Control(icon: Icons.refresh_rounded, label: 'Reload', onTap: _loadSource),
                  _Control(icon: Icons.swap_horiz_rounded, label: 'Switch', onTap: _switchSource, disabled: _sources.length < 2 || _switching),
                  _Control(icon: Icons.screen_rotation_alt_rounded, label: _landscape ? 'Portrait' : 'Rotate', onTap: _toggleLandscape),
                  _Control(icon: Icons.fullscreen_rounded, label: 'Fullscreen', onTap: () => _setFullscreen(true)),
                  _Control(icon: Icons.cast_rounded, label: 'Cast', onTap: _cast),
                  if (_pipAvailable) _Control(icon: Icons.picture_in_picture_alt_rounded, label: 'PiP', onTap: _enterPip),
                  _Control(icon: Icons.bookmark_add_outlined, label: 'Watch Later', onTap: _saveWatchLater),
                  _Control(icon: Icons.download_rounded, label: 'Download', onTap: _downloadPage),
                  _Control(icon: Icons.copy_rounded, label: 'Copy link', onTap: _copyLink),
                  _Control(icon: Icons.share_rounded, label: 'Share', onTap: _share),
                ])),
              ),
            ]),
            if (_fullscreenWidget != null) Positioned.fill(child: ColoredBox(color: Colors.black, child: _fullscreenWidget)),
            if (_landscape && !_fullscreen && _fullscreenWidget == null) ...[
              Positioned(left: 12, top: 12, child: SafeArea(child: IconButton.filledTonal(onPressed: _onBack, icon: const Icon(Icons.arrow_back_rounded)))),
              Positioned(right: 12, top: 12, child: SafeArea(child: IconButton.filledTonal(onPressed: _toggleLandscape, icon: const Icon(Icons.screen_rotation_rounded)))),
            ],
          ],
        ),
      ),
    );
  }
}

class _Control extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;
  const _Control({required this.icon, required this.label, required this.onTap, this.disabled = false});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: disabled ? null : onTap,
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(width: 66, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: disabled ? Colors.white24 : Colors.white),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: disabled ? Colors.white24 : Colors.white70)),
      ]),
    )),
  );
}
