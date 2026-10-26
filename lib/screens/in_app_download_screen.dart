import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../main.dart';
import '../utils/external_link.dart';
import '../services/in_app_download_service.dart';
import '../services/download_manager.dart';
import 'library_screen.dart';

/// Download pages open INSIDE DamiMovies and behave like a normal browser:
/// every server / download button the user taps may lead to another page
/// (HubCDN -> HBLinks -> HubCloud ...), and the browser simply follows it.
/// Real file downloads are caught at any step and handed to Android's
/// background download engine. Only automatic pop-ups (no user tap) are held
/// back, and the user can open them with one tap.
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

class _VerifiedDirectLink {
  const _VerifiedDirectLink(this.url, this.label, this.fileName, this.total, this.mimeType);
  final String url;
  final String label;
  final String? fileName;
  final int? total;
  final String? mimeType;
}

class _InAppDownloadScreenState extends State<InAppDownloadScreen> {
  InAppWebViewController? _webView;
  PullToRefreshController? _pull;
  Key _browserKey = UniqueKey();
  String _lastPageUrl = '';
  String _pageTitle = '';
  late final String _pageUrl;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _queuing = false;
  bool _scanning = false;
  final List<_VerifiedDirectLink> _verifiedLinks = [];
  String _scanStatus = '';
  String? _loadError;
  String? _lastDownloadUrl;
  DateTime? _lastDownloadAt;
  int _progress = 0;

  // Pop-ups opened WITHOUT a user tap (advertisement scripts) are held back
  // here. Anything the user taps opens normally.
  Uri? _blockedLink;
  // URLs that were probed, turned out to be web pages, and must now load
  // normally instead of being treated as a file.
  final Set<String> _allowOnce = <String>{};

  static final RegExp _directFile = RegExp(
    r'\.(mp4|mkv|webm|avi|mov|m4v|zip|rar|7z|pdf|mp3|m4a|apk)(?:$|[?#])',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _pageUrl = widget.downloadUrl;
    _lastPageUrl = _pageUrl;
    _pull = PullToRefreshController(
      settings: PullToRefreshSettings(color: appRed),
      onRefresh: () async {
        final c = _webView;
        if (c == null) return;
        final u = await c.getUrl();
        if (u != null) {
          await c.loadUrl(urlRequest: URLRequest(url: u));
        } else {
          await c.reload();
        }
      },
    );
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

  @override
  void dispose() {
    _pull = null;
    super.dispose();
  }

  Future<void> _refreshBackState(InAppWebViewController controller) async {
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (mounted) setState(() { _canGoBack = back; _canGoForward = forward; });
  }

  static Uri? _httpUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) return null;
    return uri;
  }

  Future<void> _open(String url) async {
    final c = _webView;
    if (c == null) return;
    await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _holdPopup(Uri uri) {
    if (!mounted || _blockedLink == uri) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _blockedLink = uri);
    });
  }

  /// The user decides: an automatic pop-up can still be opened in-app.
  Future<void> _openHeldPopup() async {
    final target = _blockedLink;
    if (target == null) return;
    setState(() => _blockedLink = null);
    await _open(target.toString());
  }

  Future<void> _goToDownloadPage() async {
    if (_webView == null) return;
    setState(() { _blockedLink = null; _loadError = null; });
    await _open(_pageUrl);
  }

  /// Back follows the browser history like any browser, and leaves the
  /// screen only when there is nothing left to go back to.
  Future<bool> _handleBack() async {
    final controller = _webView;
    if (controller == null) return true;
    if (_blockedLink != null) setState(() => _blockedLink = null);
    if (_loadError != null) {
      setState(() { _loadError = null; _loading = true; _browserKey = UniqueKey(); });
      return false;
    }
    if (await controller.canGoBack()) {
      await controller.goBack();
      await _refreshBackState(controller);
      return false;
    }
    return true;
  }

  /// Read only URLs that are already present in the current page DOM.
  /// Never simulate clicks or run the provider's onclick scripts: those may
  /// trigger advertisements, navigation, or an authentication flow.
  Future<void> _scanDirectLinks() async {
    if (_scanning || _webView == null || _loading) return;
    setState(() {
      _scanning = true;
      _verifiedLinks.clear();
      _scanStatus = 'Checking visible download links…';
    });
    try {
      const js = r'''(() => {
        const output = [];
        const seen = new Set();
        const elements = document.querySelectorAll(
          'a[href], a[download], [data-href], [data-url], [data-download], [data-file], [onclick]'
        );
        for (const element of elements) {
          const label = (element.innerText || element.textContent ||
            element.getAttribute('title') || 'Download').trim().slice(0, 100);
          const attributes = ['data-download', 'data-file', 'data-url', 'data-href', 'href'];
          let raw = attributes.map(name => element.getAttribute(name))
            .find(value => value && !/^(javascript:|blob:|data:|#)/i.test(value.trim()));
          // Read a literal direct URL in onclick text without executing it.
          // Dynamic or encoded links cannot be safely inferred here.
          if (!raw && element.hasAttribute('onclick')) {
            const match = element.getAttribute('onclick').match(
              /https?:\/\/[^\s'\"<>\)]+\.(?:mp4|mkv|webm|avi|mov|m4v|zip|rar|7z)(?:\?[^\s'\"<>\)]*)?/i
            );
            if (match) raw = match[0];
          }
          if (!raw) continue;
          let url;
          try { url = new URL(raw, document.baseURI); } catch (_) { continue; }
          if (!/^https?:$/.test(url.protocol)) continue;
          const directExt = /\.(mp4|mkv|webm|avi|mov|m4v|zip|rar|7z|mp3|m4a)(?:$|[?#])/i.test(url.pathname + url.search);
          const downloadHint = element.hasAttribute('download') ||
            /download|direct|1080p|720p|480p|server|mirror|hubcloud|pixeldrain/i.test(label);
          if (!directExt && !downloadHint) continue;
          if (url.href === document.location.href || seen.has(url.href)) continue;
          seen.add(url.href);
          output.push({url: url.href, label});
          if (output.length >= 20) break;
        }
        return JSON.stringify(output);
      })()''';
      final raw = await _webView!.evaluateJavascript(source: js);
      dynamic parsed = raw;
      // Android may return the JSON string or a JSON-encoded string.
      if (parsed is String) {
        parsed = jsonDecode(parsed);
        if (parsed is String) parsed = jsonDecode(parsed);
      }
      if (parsed is! List) throw const FormatException('No readable page links');
      final candidates = <(String, String)>[];
      for (final candidate in parsed) {
        if (candidate is! Map) continue;
        final url = candidate['url']?.toString() ?? '';
        final uri = _httpUri(url);
        if (uri == null) continue;
        candidates.add((url, candidate['label']?.toString() ?? 'Download'));
      }
      if (candidates.isEmpty) {
        if (mounted) setState(() {
          _scanStatus = 'No direct file links are exposed on this page. '
              'Just tap a server\'s Download button on the page: it opens '
              'like a normal browser and the file downloads automatically '
              'once the server provides it.';
        });
        _showVerifiedLinks();
        return;
      }
      final currentPage = (await _webView!.getUrl())?.toString() ?? _lastPageUrl;
      final manager = DownloadManager.instance;
      final found = <_VerifiedDirectLink>[];
      // Limit requests: a page can include many advertising and server URLs.
      // Probe response headers, never download the file during scanning.
      for (var start = 0; start < candidates.length; start += 4) {
        final batch = candidates.skip(start).take(4).toList();
        final matches = await Future.wait(batch.map((entry) async {
          final (url, label) = entry;
          var cookies = '';
          try {
            final values = await CookieManager.instance().getCookies(url: WebUri(url));
            cookies = values.map((c) => '${c.name}=${c.value}').join('; ');
          } catch (_) {}
          final info = await manager.checkLink(url,
              referer: currentPage, cookie: cookies);
          if (!info.isFile) return null;
          return _VerifiedDirectLink(url, label, info.fileName, info.total, info.mimeType);
        }));
        found.addAll(matches.whereType<_VerifiedDirectLink>());
        if (!mounted) return;
        setState(() {
          _verifiedLinks
            ..clear()
            ..addAll(found);
          _scanStatus = 'Checked ${start + batch.length} of ${candidates.length} links…';
        });
      }
      if (mounted) setState(() {
        _scanStatus = found.isEmpty
          ? 'No direct files could be verified here. Tap a Download button '
              'on the page and continue: it opens like a normal browser.'
          : '${found.length} direct file link${found.length == 1 ? '' : 's'} verified.';
      });
    } catch (error) {
      debugPrint('DamiMovies direct-link scan: $error');
      if (mounted) setState(() => _scanStatus =
          'Could not inspect this page. Try again after it finishes loading.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
    if (mounted) _showVerifiedLinks();
  }

  void _showVerifiedLinks() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('DamiMovies In-App Servers',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_scanStatus, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            const Text('Direct file links found on this page are listed here. '
                'Any other button still works normally on the page.',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 16),
            if (_verifiedLinks.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.open_in_browser_rounded),
                    label: const Text('Continue on the page')))),
            Flexible(child: ListView.separated(
              shrinkWrap: true,
              itemCount: _verifiedLinks.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (_, index) {
                final link = _verifiedLinks[index];
                final description = link.fileName ?? link.label;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(description, maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                  subtitle: Text(link.total == null
                      ? link.url
                      : '${(link.total! / (1024 * 1024)).toStringAsFixed(1)} MB · ${link.url}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white60)),
                  trailing: FilledButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_askToDownload(link.url,
                        suggestedFile: link.fileName ?? widget.movieTitle,
                        mimeType: link.mimeType));
                    },
                    child: const Text('Download'),
                  ),
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  /// A link that looks like a file is probed (headers only). Real files go
  /// to the downloader; web pages load normally in the browser; if the
  /// provider refuses the probe we still offer the download, like a browser.
  Future<void> _verifyAndAsk(String url) async {
    if (!mounted || _queuing) return;
    final referer = (await _webView?.getUrl())?.toString() ?? _lastPageUrl;
    String cookies = '';
    try {
      final scoped = await CookieManager.instance().getCookies(url: WebUri(url));
      cookies = scoped.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {}
    final info = await DownloadManager.instance.checkLink(
      url, referer: referer, cookie: cookies,
    );
    if (!mounted) return;
    if (info.isPage) {
      _allowOnce.add(url);
      await _open(url);
      return;
    }
    await _askToDownload(url,
      suggestedFile: info.fileName, mimeType: info.mimeType);
  }

  Future<void> _askToDownload(String link, {String? suggestedFile, String? mimeType}) async {
    if (!mounted || _queuing) return;
    final type = (mimeType ?? '').toLowerCase();
    if (type.contains('html') || type.contains('json') ||
        type.startsWith('text/')) {
      // It is a web page, not a file: just open it like a browser would.
      _allowOnce.add(link);
      await _open(link);
      return;
    }
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
      error = 'Could not start the transfer. Try a verified direct file under In-App Servers.';
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
    // Frames (captcha, embeds) always load.
    if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
    final url = action.request.url?.toString() ?? '';
    if (url == 'about:blank') return NavigationActionPolicy.ALLOW;
    final uri = _httpUri(url);
    // intent:, market:, app deep links etc. cannot render in the page.
    if (uri == null) return NavigationActionPolicy.CANCEL;
    if (_allowOnce.remove(url)) return NavigationActionPolicy.ALLOW;
    if (_directFile.hasMatch(uri.path) || action.shouldPerformDownload == true) {
      unawaited(_verifyAndAsk(url));
      return NavigationActionPolicy.CANCEL;
    }
    // Everything else — including buttons that lead to another website —
    // opens normally, exactly like a real browser.
    return NavigationActionPolicy.ALLOW;
  }

  Future<void> _openExternal() async {
    final url = (await _webView?.getUrl())?.toString() ?? _lastPageUrl;
    if (!mounted) return;
    await openInExternalBrowser(context, url);
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
                                _webView = null;
                              });
                            },
                            child: const Text('Try again'),
                          ),
                          TextButton(
                            onPressed: _openExternal,
                            child: const Text('Open in my browser'),
                          ),
                        ]),
                      ),
                    )
                  : InAppWebView(
                      key: _browserKey,
                      initialUrlRequest: URLRequest(url: WebUri(_pageUrl)),
                      pullToRefreshController: _pull,
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        useOnDownloadStart: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        javaScriptCanOpenWindowsAutomatically: false,
                        thirdPartyCookiesEnabled: true,
                        useWideViewPort: true,
                        loadWithOverviewMode: true,
                        supportZoom: true,
                        builtInZoomControls: true,
                        displayZoomControls: false,
                        mixedContentMode:
                            MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
                      ),
                      onWebViewCreated: (controller) => _webView = controller,
                      onLoadStart: (controller, url) {
                        if (!mounted) return;
                        final u = url?.toString() ?? '';
                        setState(() {
                          _loading = true;
                          _progress = 5;
                          _loadError = null;
                          if (_httpUri(u) != null) _lastPageUrl = u;
                        });
                        unawaited(_refreshBackState(controller));
                      },
                      onProgressChanged: (controller, value) {
                        if (mounted) setState(() => _progress = value);
                      },
                      onLoadStop: (controller, url) async {
                        _pull?.endRefreshing();
                        final u = url?.toString() ?? '';
                        final title = await controller.getTitle();
                        if (!mounted) return;
                        setState(() {
                          _loading = false;
                          _progress = 100;
                          if (_httpUri(u) != null) _lastPageUrl = u;
                          _pageTitle = title ?? '';
                        });
                        unawaited(_refreshBackState(controller));
                      },
                      onTitleChanged: (controller, title) {
                        if (mounted) setState(() => _pageTitle = title ?? '');
                      },
                      onUpdateVisitedHistory: (controller, url, isReload) {
                        final u = url?.toString() ?? '';
                        if (mounted && _httpUri(u) != null) {
                          setState(() => _lastPageUrl = u);
                        }
                        unawaited(_refreshBackState(controller));
                      },
                      onReceivedError: (controller, request, error) {
                        _pull?.endRefreshing();
                        if (request.isForMainFrame != true || !mounted) return;
                        // Cancelled loads (our own download hand-off) are not errors.
                        if (error.type == WebResourceErrorType.CANCELLED) return;
                        setState(() { _loading = false; _loadError =
                          'This page could not be loaded. Check your connection and retry.'; });
                      },
                      onDownloadStartRequest: (controller, request) {
                        unawaited(_askToDownload(
                          request.url.toString(),
                          suggestedFile: request.suggestedFilename,
                          mimeType: request.mimeType,
                        ));
                      },
                      shouldOverrideUrlLoading: _navigate,
                      onJsAlert: (controller, request) async {
                        if (!mounted) return null;
                        await showDialog<void>(
                          context: context,
                          builder: (d) => AlertDialog(
                            content: Text(request.message ?? ''),
                            actions: [TextButton(
                              onPressed: () => Navigator.pop(d),
                              child: const Text('OK'))],
                          ),
                        );
                        return JsAlertResponse(
                          handledByClient: true,
                          action: JsAlertResponseAction.CONFIRM,
                        );
                      },
                      onJsConfirm: (controller, request) async {
                        if (!mounted) return null;
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            content: Text(request.message ?? ''),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('OK')),
                            ],
                          ),
                        );
                        return JsConfirmResponse(
                          handledByClient: true,
                          action: ok == true
                              ? JsConfirmResponseAction.CONFIRM
                              : JsConfirmResponseAction.CANCEL,
                        );
                      },
                      onCreateWindow: (controller, action) async {
                        // target="_blank" / window.open. A tap by the user
                        // opens the page right here (like a browser tab);
                        // a script-opened pop-up with no tap is held back.
                        final uri = _httpUri(action.request.url?.toString() ?? '');
                        if (uri == null) return false;
                        if (_directFile.hasMatch(uri.path) ||
                            action.shouldPerformDownload == true) {
                          unawaited(_verifyAndAsk(uri.toString()));
                        } else if (action.hasGesture == false) {
                          _holdPopup(uri);
                        } else {
                          unawaited(_open(uri.toString()));
                        }
                        return false;
                      },
                    ),
            ),
            if (_blockedLink != null)
              Container(
                color: appSurface,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  const Icon(Icons.gpp_good_outlined, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Pop-up held back · ${_blockedLink!.host}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white70))),
                  TextButton(onPressed: _openHeldPopup, child: const Text('Open')),
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _blockedLink = null),
                    icon: const Icon(Icons.close_rounded, size: 18)),
                ]),
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
                  tooltip: 'Back',
                  onPressed: () async {
                    final exit = await _handleBack();
                    if (exit && mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: _canGoForward ? () => _webView?.goForward() : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                IconButton(
                  tooltip: _loading ? 'Stop' : 'Refresh',
                  onPressed: () => _loading ? _webView?.stopLoading() : _webView?.reload(),
                  icon: Icon(_loading ? Icons.close_rounded : Icons.refresh_rounded),
                ),
                Expanded(child: TextButton.icon(
                  onPressed: _scanning || _loading ? null : _scanDirectLinks,
                  icon: _scanning
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search_rounded, size: 17),
                  label: const Text('In-App Servers',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
                IconButton(
                  tooltip: 'Back to download page',
                  onPressed: _goToDownloadPage,
                  icon: const Icon(Icons.home_rounded, size: 21),
                ),
                IconButton(
                  tooltip: 'Library downloads',
                  onPressed: _openDownloads,
                  icon: const Icon(Icons.folder_rounded, size: 19),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
