import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:video_player/video_player.dart';
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
  VideoPlayerController? _nativeController;
  Timer? _nativeProgressTimer;
  Timer? _controlsHideTimer;
  bool _nativeControlsVisible = true;
  DateTime _lastNativeProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  late final List<({String url, String referer, String agent})> _sources;
  int _sourceIndex = 0;
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
    final nativeSourceIndex = _sources.indexWhere(
      (source) => StreamResolver.resolve(source.url).usesNativePlayer,
    );
    if (nativeSourceIndex >= 0) _sourceIndex = nativeSourceIndex;
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
            _error = false;
            _errorDetail = null;
          });
          _armTimeout();
          _keepVisible();
          _applyShield();
        },
        onProgress: (_) {
          _applyShield();
        },
        onPageFinished: (url) {
          _loadTimeout?.cancel();
          if (mounted) setState(() {
            _loading = false;
          });
          _keepVisible();
          _applyShield();
          _installVideoHooks();
          if (!_stream.usesNativePlayer) unawaited(_offerResume());
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
    final native = _nativeController;
    if (native != null && native.value.isInitialized) {
      try { await native.pause(); } catch (_) {}
    } else {
      try { await _controller.runJavaScript(_videosJs('v.pause()')); } catch (_) {}
    }
    if (mounted) await Navigator.of(context).maybePop();
  }

  String _videosJs(String action) =>
      "document.querySelectorAll('video').forEach(function(v){try{$action}catch(e){}});";

  void _runVideoAction(String action, {int seconds = 0}) {
    final native = _nativeController;
    if (native != null && native.value.isInitialized) {
      if (action == 'seekBy') {
        final current = native.value.position;
        final duration = native.value.duration;
        final next = current + Duration(seconds: seconds);
        final clamped = next < Duration.zero
            ? Duration.zero
            : (duration > Duration.zero && next > duration ? duration : next);
        unawaited(native.seekTo(clamped).catchError((_) {}));
      } else if (action == 'play') {
        unawaited(native.play().catchError((_) {}));
      } else {
        unawaited(native.pause().catchError((_) {}));
      }
      return;
    }
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
    final native = _nativeController;
    if (native != null && native.value.isInitialized && native.value.duration > Duration.zero) {
      try {
        await native.seekTo(Duration(milliseconds: (native.value.duration.inMilliseconds * progress).round()));
        return;
      } catch (_) {}
    }
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
    if (_nativeController != null) return;
    _controller.runJavaScript(BackgroundPlayback.rememberPlayingJs).catchError((_) {});
  }

  void _resumePlaying() {
    if (_nativeController != null) return;
    _controller.runJavaScript(BackgroundPlayback.resumePlayingJs).catchError((_) {});
  }

  void _armTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 28), () {
      if (!mounted || !_loading) return;
      setState(() {
        _loading = false;
        _error = true;
        _errorDetail = 'This source is taking too long to respond. Try switching to another player.';
      });
    });
  }

  bool _isTrustedPlayerHost(String host) {
    String normalize(String value) => value.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final target = normalize(host);
    final allowed = <String>{};
    void addHostFromUrl(String value) {
      final parsed = Uri.tryParse(value);
      final parsedHost = parsed?.host;
      if (parsedHost != null && parsedHost.isNotEmpty) allowed.add(normalize(parsedHost));
    }
    addHostFromUrl(_currentUrl);
    addHostFromUrl(_currentReferer);
    addHostFromUrl(AppConfig.playerOrigin);
    addHostFromUrl(AppConfig.embedBase);
    addHostFromUrl(AppConfig.altEmbedBase);
    return allowed.any((base) => target == base || target.endsWith('.$base'));
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
    // Embedded providers sometimes wire the Play button to a redirect/ad page.
    // Keep the movie inside DamiMovies: allow same-provider navigation, but
    // block main-frame jumps to unrelated domains. The explicit Browser action
    // remains available for users who intentionally want to leave the player.
    if (request.isMainFrame && _stream.kind == StreamKind.embed && !_isTrustedPlayerHost(uri.host)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('External redirect blocked. Use Switch player to try another source.'),
          duration: Duration(seconds: 3),
        ));
      }
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

  Future<void> _disposeNativePlayer() async {
    _nativeProgressTimer?.cancel();
    _controlsHideTimer?.cancel();
    _videoPlaying = false;
    final wasPlaying = _videoPlaying;
    final old = _nativeController;
    _nativeController = null;
    if (wasPlaying && _playbackServiceActive) unawaited(BackgroundPlayback.setPlaying(false));
    if (old != null) {
      try { old.removeListener(_onNativePlayerChanged); } catch (_) {}
      try { await old.dispose(); } catch (_) {}
    }
  }

  void _onNativePlayerChanged() {
    final native = _nativeController;
    if (native == null || !native.value.isInitialized) return;
    final value = native.value;
    final now = DateTime.now();
    if (value.duration > Duration.zero &&
        value.position >= Duration.zero &&
        now.difference(_lastNativeProgressSave).inSeconds >= 12) {
      _lastNativeProgressSave = now;
      unawaited(MovieLibrary.instance.setProgress(
        widget.movie,
        value.position.inMilliseconds / 1000.0,
        value.duration.inMilliseconds / 1000.0,
      ));
    }
    if (value.isPlaying != _videoPlaying) {
      _videoPlaying = value.isPlaying;
      if (_playbackServiceActive) unawaited(BackgroundPlayback.setPlaying(value.isPlaying));
      if (value.isPlaying && _nativeControlsVisible) _scheduleHideNativeControls();
    }
  }

  void _scheduleHideNativeControls() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      final native = _nativeController;
      if (!mounted || native == null || !native.value.isPlaying) return;
      setState(() => _nativeControlsVisible = false);
    });
  }

  void _showNativeControls() {
    if (!mounted) return;
    setState(() => _nativeControlsVisible = true);
    if (_nativeController?.value.isPlaying == true) _scheduleHideNativeControls();
  }

  Future<void> _loadNativeSource(ResolvedStream stream) async {
    await _disposeNativePlayer();
    if (!mounted) return;
    final headers = <String, String>{
      'User-Agent': _currentAgent.isNotEmpty ? _currentAgent : AppConfig.userAgent,
      if (_currentReferer.isNotEmpty) 'Referer': _currentReferer,
    };
    VideoPlayerController? next;
    try {
      next = VideoPlayerController.networkUrl(Uri.parse(stream.url), httpHeaders: headers);
      _nativeController = next;
      _nativeControlsVisible = true;
      next.addListener(_onNativePlayerChanged);
      setState(() {
        _loading = true;
        _error = false;
        _errorDetail = null;
      });
      await next.initialize().timeout(const Duration(seconds: 27));
      if (!mounted || !identical(_nativeController, next)) {
        // A newer source may have replaced and already disposed this one.
        return;
      }
      await next.setLooping(false);
      _loadTimeout?.cancel();
      setState(() {
        _loading = false;
        _error = false;
      });
      _nativeProgressTimer?.cancel();
      _nativeProgressTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        _onNativePlayerChanged();
      });
      try { await next.play(); } catch (_) { /* Show native play control if autoplay is denied. */ }
      unawaited(_offerResume());
      if (next.value.isPlaying) _scheduleHideNativeControls();
    } catch (error) {
      final isCurrentRequest = next == null || identical(_nativeController, next);
      if (isCurrentRequest) _loadTimeout?.cancel();
      if (next != null && identical(_nativeController, next)) {
        try { next.removeListener(_onNativePlayerChanged); } catch (_) {}
        _nativeController = null;
        try { await next.dispose(); } catch (_) {}
      }
      if (mounted && isCurrentRequest) setState(() {
        _loading = false;
        _error = true;
        _errorDetail = 'Native playback could not start for this source. Try Reload or Switch player. ${error.toString().split('\n').first}';
      });
    }
  }

  Future<void> _loadSource() async {
    _loadTimeout?.cancel();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
      _errorDetail = null;
    });
    _armTimeout();
    final stream = _stream;
    if (stream.kind == StreamKind.invalid) {
      _loadTimeout?.cancel();
      await _disposeNativePlayer();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _errorDetail = 'This title does not have a valid playback URL.';
      });
      return;
    }
    if (stream.usesNativePlayer) {
      await _loadNativeSource(stream);
      return;
    }
    await _disposeNativePlayer();
    if (!mounted) return;
    setState(() {});
    try {
      await _controller.setUserAgent(_currentAgent.isNotEmpty ? _currentAgent : AppConfig.userAgent);
      final headers = <String, String>{
        if (_currentReferer.isNotEmpty) 'Referer': _currentReferer,
      };
      await _controller.loadRequest(Uri.parse(stream.url), headers: headers);
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
    if (!_stream.usesNativePlayer) await _loadSource();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      _stream.usesNativePlayer
          ? 'Quality is selected by the native stream player when supported.'
          : (prefs.lowQuality ? 'Low quality preference enabled where supported.' : 'Automatic quality preference enabled.'),
    )));
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
    _nativeProgressTimer?.cancel();
    _controlsHideTimer?.cancel();
    final native = _nativeController;
    _nativeController = null;
    if (native != null) {
      try { native.removeListener(_onNativePlayerChanged); } catch (_) {}
      unawaited(native.dispose());
    }
    if (_playbackServiceActive) unawaited(BackgroundPlayback.stop(_onStopTapped));
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]));
    super.dispose();
  }

  void _toggleNativeControls() {
    if (!mounted) return;
    if (_nativeControlsVisible && _nativeController?.value.isPlaying == true) {
      _controlsHideTimer?.cancel();
      setState(() => _nativeControlsVisible = false);
    } else {
      _showNativeControls();
    }
  }

  String _formatPlayerTime(Duration value) {
    final total = value.inSeconds < 0 ? 0 : value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '$minutes:${two(seconds)}';
  }

  Widget _buildNativeVideo(VideoPlayerController controller) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        final aspect = value.aspectRatio.isFinite && value.aspectRatio > 0
            ? value.aspectRatio
            : 16 / 9;
        final showControls = _nativeControlsVisible || !value.isPlaying;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleNativeControls,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: VideoPlayer(controller),
                  ),
                ),
                if (value.isBuffering)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: Center(child: CircularProgressIndicator(color: Colors.white70)),
                    ),
                  ),
                if (showControls)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x68000000), Colors.transparent, Color(0x99000000)],
                            stops: [0, .45, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showControls)
                  SafeArea(
                    child: Column(
                      children: [
                        if (_isImmersive)
                          Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12, top: 8),
                              child: Text(
                                widget.movie.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, shadows: [Shadow(color: Colors.black, blurRadius: 8)]),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  tooltip: 'Back 10 seconds',
                                  onPressed: () => _runVideoAction('seekBy', seconds: -10),
                                  iconSize: 25,
                                  icon: const Icon(Icons.replay_10_rounded),
                                ),
                                const SizedBox(width: 18),
                                IconButton.filled(
                                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                                  onPressed: () => _runVideoAction(value.isPlaying ? 'pause' : 'play'),
                                  iconSize: 36,
                                  style: IconButton.styleFrom(backgroundColor: appRed, foregroundColor: Colors.white),
                                  icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                ),
                                const SizedBox(width: 18),
                                IconButton.filledTonal(
                                  tooltip: 'Forward 10 seconds',
                                  onPressed: () => _runVideoAction('seekBy', seconds: 10),
                                  iconSize: 25,
                                  icon: const Icon(Icons.forward_10_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              VideoProgressIndicator(
                                controller,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                colors: VideoProgressColors(
                                  playedColor: appRed,
                                  bufferedColor: Colors.white54,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(_formatPlayerTime(value.position), style: const TextStyle(fontSize: 12)),
                                  const Spacer(),
                                  Text(_formatPlayerTime(value.duration), style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Fullscreen',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _setFullscreen(!_fullscreen),
                                    icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final native = _nativeController;
    final video = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (native != null) _buildNativeVideo(native) else WebViewWidget(controller: _controller),
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
        appBar: null,
        body: Stack(
          children: [
            Column(children: [
              Expanded(child: video),
              if (!_isImmersive) Container(
                color: appSurface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
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
                ),
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
