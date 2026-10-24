import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../main.dart';
import '../services/download_manager.dart';
import '../services/in_app_download_service.dart';
import 'library_screen.dart';

/// Download destinations open INSIDE DamiMovies. WebView's actual native
/// download events are handed to Android's background download engine.
/// A download page (HTML) itself is never treated as a movie file.
class InAppDownloadScreen extends StatefulWidget {
  const InAppDownloadScreen({
    super.key,
    required this.movieTitle,
    required this.downloadUrl,
  });

  final String movieTitle;
  final String downloadUrl;

  @override
  State<InAppDownloadScreen> createState() => _InAppDownloadScreenState();
}

class _InAppDownloadScreenState extends State<InAppDownloadScreen> {
  InAppWebViewController? _webView;
  Key _browserKey = UniqueKey();
  String _lastPageUrl = '';
  late final String _pageUrl;
  bool _loading = true;
  bool _canGoBack = false;
  bool _queuing = false;
  String? _loadError;
  String? _lastDownloadUrl;
  DateTime? _lastDownloadAt;
  int _progress = 0;

  static final RegExp _directFile = RegExp(
    r'\.(mp4|mkv|webm|avi|mov|m4v|zip|rar|7z|pdf|mp3|m4a|apk)(?:$|[?#])',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _pageUrl = widget.downloadUrl;
    _lastPageUrl = _pageUrl;
    final valid = Uri.tryParse(_pageUrl);
    if (valid == null ||
        (valid.scheme != 'https' && valid.scheme != 'http') ||
        valid.host.isEmpty) {
      _loadError = 'This download page has an invalid address.';
      _loading = false;
    } else if (_directFile.hasMatch(valid.path)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_askToDownload(_pageUrl));
      });
    }
  }

  Future<void> _refreshBackState(InAppWebViewController controller) async {
    final value = await controller.canGoBack();
    if (mounted) setState(() => _canGoBack = value);
  }

  Future<bool> _handleBack() async {
    final controller = _webView;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      await _refreshBackState(controller);
      return false;
    }
    return true;
  }

  Future<void> _askToDownload(String link, {String? suggestedFile, String? mimeType}) async {
    if (!mounted || _queuing) return;
    final uri = Uri.tryParse(link);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This provider did not supply a downloadable file URL.'),
      ));
      return;
    }
    final now = DateTime.now();
    if (_lastDownloadUrl == link &&
        _lastDownloadAt != null &&
        now.difference(_lastDownloadAt!) < const Duration(seconds: 3)) return;
    _lastDownloadAt = now;
    _lastDownloadUrl = link;

    final choice = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Download this file?'),
        content: Text(suggestedFile?.isNotEmpty == true
            ? suggestedFile!
            : 'Save this file to your device? You can view its progress in Library → Downloads.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialog, true),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download'),
          ),
        ],
      ),
    );
    if (choice != true || !mounted) return;

    setState(() => _queuing = true);
    String? error;
    try {
      error = await InAppDownloadService.saveFile(
        url: link,
        pageUrl: _lastPageUrl,
        suggestedName: suggestedFile ?? widget.movieTitle,
        mimeType: mimeType,
      );
    } catch (exception) {
      error = 'Could not start the download. Check the link and try again.';
      debugPrint('DamiMovies: in-app download failed: $exception');
    } finally {
      if (mounted) setState(() => _queuing = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(error == null
          ? 'Download added! Track progress in Library → Downloads.'
          : error),
      action: error == null
          ? SnackBarAction(label: 'VIEW', onPressed: _openDownloads)
          : null,
    ));
  }

  void _openDownloads() {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const LibraryScreen(initialTab: 2),
    ));
  }

  Future<NavigationActionPolicy> _navigate(
      InAppWebViewController controller, NavigationAction action) async {
    final url = action.request.url?.toString() ?? '';
    if (url.isEmpty) return NavigationActionPolicy.ALLOW;
    if (_directFile.hasMatch(Uri.tryParse(url)?.path ?? '')) {
      unawaited(_askToDownload(url));
      return NavigationActionPolicy.CANCEL;
    }
    if (url.startsWith('http://') || url.startsWith('https://') ||
        url == 'about:blank') {
      return NavigationActionPolicy.ALLOW;
    }
    // A normal web browser may offer intent:// or external app links; this
    // dedicated download screen deliberately stays within DamiMovies.
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: appBg,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Download in DamiMovies',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              Text(widget.movieTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'My downloads',
              onPressed: _openDownloads,
              icon: const Icon(Icons.download_for_offline_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            if (_loading || (_progress > 0 && _progress < 100))
              LinearProgressIndicator(
                value: _progress > 0 && _progress < 100
                    ? _progress / 100
                    : null,
                minHeight: 3,
                color: appRed,
              ),
            Expanded(
              child: _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.wifi_off_rounded,
                              size: 45, color: Colors.white54),
                          const SizedBox(height: 16),
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 15),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _loadError = null;
                                _loading = true;
                                _browserKey = UniqueKey();
                              });
                            },
                            child: const Text('Try again'),
                          ),
                        ]),
                      ),
                    )
                  : InAppWebView(
                      key: _browserKey,
                      initialUrlRequest: URLRequest(url: WebUri(_pageUrl)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        useOnDownloadStart: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        javaScriptCanOpenWindowsAutomatically: false,
                        thirdPartyCookiesEnabled: true,
                      ),
                      onWebViewCreated: (controller) => _webView = controller,
                      onLoadStart: (controller, url) {
                        if (!mounted) return;
                        if (url != null && (url.scheme == 'https' || url.scheme == 'http') &&
                          !_directFile.hasMatch(Uri.tryParse(url.toString())?.path ?? '')) {
                          _lastPageUrl = url.toString();
                        }
                        setState(() { _loading = true; _progress = 5; });
                        unawaited(_refreshBackState(controller));
                      },
                      onProgressChanged: (controller, value) {
                        if (mounted) setState(() => _progress = value);
                      },
                      onLoadStop: (controller, url) {
                        if (mounted) setState(() { _loading = false; _progress = 100; });
                        unawaited(_refreshBackState(controller));
                      },
                      onReceivedError: (controller, request, error) {
                        if (request.isForMainFrame == true && mounted) {
                          setState(() { _loading = false; _loadError =
                            'The download page could not be loaded. Check your connection and retry.'; });
                        }
                      },
                      onDownloadStartRequest: (controller, request) {
                        unawaited(_askToDownload(
                          request.url.toString(),
                          suggestedFile: request.suggestedFilename,
                          mimeType: request.mimeType,
                        ));
                      },
                      shouldOverrideUrlLoading: _navigate,
                      onCreateWindow: (controller, action) async {
                        // target="_blank" download links stay in our in-app
                        // browser instead of opening Chrome or another app.
                        final target = action.request.url;
                        if (target == null) return false;
                        final url = target.toString();
                        final uri = Uri.tryParse(url);
                        if (uri == null ||
                            (uri.scheme != 'https' && uri.scheme != 'http')) return false;
                        if (_directFile.hasMatch(uri.path)) {
                          unawaited(_askToDownload(url));
                        } else {
                          await controller.loadUrl(urlRequest: URLRequest(url: target));
                        }
                        return true;
                      },
                    ),
            ),
            if (_queuing)
              const Padding(
                padding: EdgeInsets.all(6),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 9),
                  Text('Preparing download…'),
                ]),
              ),
            Container(
              decoration: BoxDecoration(
                color: appSurface,
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .08))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                IconButton(
                  tooltip: 'Back on download page',
                  onPressed: !_canGoBack ? null : () async {
                    await _webView?.goBack();
                    final c = _webView;
                    if (c != null) await _refreshBackState(c);
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: 'Refresh download page',
                  onPressed: () => _webView?.reload(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const Spacer(),
                Text('Downloads in app',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: _openDownloads,
                  icon: const Icon(Icons.folder_rounded, size: 17),
                  label: const Text('My Files'),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
