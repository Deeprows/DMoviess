import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../main.dart';
import '../services/in_app_download_service.dart';
import '../services/download_manager.dart';
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
  Key _browserKey = UniqueKey();
  String _lastPageUrl = '';
  late final String _pageUrl;
  bool _loading = true;
  bool _canGoBack = false;
  bool _queuing = false;
  bool _scanning = false;
  final List<_VerifiedDirectLink> _verifiedLinks = [];
  String _scanStatus = '';
  String? _loadError;
  String? _lastDownloadUrl;
  DateTime? _lastDownloadAt;
  int _progress = 0;

  // Keep the last known-good download page instead of allowing ad popups to
  // replace the in-app browser. Extra hosts can be approved by the user.
  final Set<String> _approvedHosts = <String>{};
  String _lastSafePage = '';
  Uri? _blockedLink;
  bool _restoringPage = false;
  int _consecutiveRestores = 0;
  DateTime? _lastRestore;

  static final RegExp _directFile = RegExp(
    r'\.(mp4|mkv|webm|avi|mov|m4v|zip|rar|7z|pdf|mp3|m4a|apk)(?:$|[?#])',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _pageUrl = widget.downloadUrl;
    _lastPageUrl = _pageUrl;
    _lastSafePage = _pageUrl;
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
    } else {
      _approvedHosts.add(valid.host.toLowerCase());
    }
  }

  Future<void> _refreshBackState(InAppWebViewController controller) async {
    final value = await controller.canGoBack();
    if (mounted) setState(() => _canGoBack = value);
  }

  static Uri? _httpUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) return null;
    return uri;
  }

  bool _isApproved(Uri uri) => _approvedHosts.contains(uri.host.toLowerCase());

  void _recordSafePage(Uri uri) {
    if (!_isApproved(uri) || _directFile.hasMatch(uri.path)) return;
    _lastSafePage = uri.toString();
    _lastPageUrl = _lastSafePage;
  }

  void _blockLink(Uri uri) {
    if (!mounted || _blockedLink == uri) return;
    // Defer because WebView navigation callbacks can run during a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _blockedLink == uri) return;
      setState(() => _blockedLink = uri);
    });
  }

  /// Cross-site links (including onclick ad destinations) are never silently
  /// loaded. A genuine file host can be approved explicitly by the user.
  Future<void> _reviewBlockedLink() async {
    final destination = _blockedLink;
    if (!mounted || destination == null) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Open another website?'),
        content: Text(
          'This link goes to ${destination.host}.\n\n'
          'Only continue if this is the download server you selected. '
          'Unexpected advertisement redirects should be declined.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Stay on download page'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Open in DamiMovies'),
          ),
        ],
      ),
    );
    if (!mounted || _blockedLink != destination) return;
    setState(() => _blockedLink = null);
    if (allow != true) return;
    _approvedHosts.add(destination.host.toLowerCase());
    await _webView?.loadUrl(urlRequest: URLRequest(url: WebUri(destination.toString())));
  }

  /// Last-resort recovery for redirects WebView cannot intercept (notably
  /// some HTTP redirect chains). Never restore more than twice in a burst.
  Future<void> _recoverUnexpectedPage(InAppWebViewController controller) async {
    if (_restoringPage || _lastSafePage.isEmpty) return;
    final now = DateTime.now();
    if (_lastRestore == null || now.difference(_lastRestore!) > const Duration(seconds: 8)) {
      _consecutiveRestores = 0;
    }
    _lastRestore = now;
    if (_consecutiveRestores >= 2) return;
    _consecutiveRestores++;
    _restoringPage = true;
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(_lastSafePage)));
    } finally {
      _restoringPage = false;
    }
  }

  Future<void> _returnToDownloadPage() async {
    final controller = _webView;
    if (controller == null || _lastSafePage.isEmpty) return;
    setState(() { _blockedLink = null; _loadError = null; });
    final current = (await controller.getUrl())?.toString();
    // Never reload the server list merely because a popup was blocked:
    // refreshing it can restart the provider's security check.
    if (current != _lastSafePage) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(_lastSafePage)));
    }
    await _refreshBackState(controller);
  }

  Future<bool> _handleBack() async {
    final controller = _webView;
    if (controller == null) return true;
    final current = _httpUri((await controller.getUrl())?.toString() ?? '');
    if (current != null && !_isApproved(current)) {
      await _returnToDownloadPage();
      return false;
    }
    if (await controller.canGoBack()) {
      await controller.goBack();
      final after = _httpUri((await controller.getUrl())?.toString() ?? '');
      if (after != null && !_isApproved(after)) await _returnToDownloadPage();
      await _refreshBackState(controller);
      return false;
    }
    if (_blockedLink != null) {
      await _returnToDownloadPage();
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
              'The server buttons may lead to another webpage or generate '
              'a link after you select a server.';
        });
        _showVerifiedLinks();
        return;
      }
      final currentPage = (await _webView!.getUrl())?.toString() ?? _lastSafePage;
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
          ? 'No verified direct files found. The buttons on this page '
              'appear to lead to other pages, require a server step, '
              'or block file verification.'
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
            const Text('Only links confirmed to return a downloadable file are listed. '
                'Other webpages and unverified links are excluded.',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 16),
            if (_verifiedLinks.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 15),
                child: Text('No verified direct downloads on this page yet. '
                    'Continue on the original server page if needed.')),
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

  /// The URL extension alone does not prove this is a file. Ask for only
  /// response headers before handing it to the native downloader.
  Future<void> _verifyAndAsk(String url) async {
    if (!mounted || _queuing) return;
    final referer = (await _webView?.getUrl())?.toString() ?? _lastSafePage;
    String cookies = '';
    try {
      final scoped = await CookieManager.instance().getCookies(url: WebUri(url));
      cookies = scoped.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {}
    final info = await DownloadManager.instance.checkLink(
      url, referer: referer, cookie: cookies,
    );
    if (!mounted) return;
    if (!info.isFile) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This link did not return a direct file. '
            'Use In-App Servers to find verified download links.'),
      ));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That button returned a webpage, not a file. '
            'Try In-App Servers for direct download links.'),
      ));
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
    // Don't break captcha widgets, external images or third-party content
    // rendered inside frames. Only protect the top-level download page.
    if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
    final url = action.request.url?.toString() ?? '';
    if (url == 'about:blank') return NavigationActionPolicy.ALLOW;
    final uri = _httpUri(url);
    if (uri == null) return NavigationActionPolicy.CANCEL;
    if (_directFile.hasMatch(uri.path) || action.shouldPerformDownload == true) {
      unawaited(_verifyAndAsk(url));
      return NavigationActionPolicy.CANCEL;
    }
    if (_isApproved(uri)) return NavigationActionPolicy.ALLOW;
    // An ad's cross-site redirect must not replace the download page, even
    // if the redirect originated from tapping an actual Download button.
    _blockLink(uri);
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
                        final uri = _httpUri(url?.toString() ?? '');
                        if (uri != null && !_isApproved(uri)) {
                          _blockLink(uri);
                          unawaited(_recoverUnexpectedPage(controller));
                          return;
                        }
                        setState(() { _loading = true; _progress = 5; });
                        unawaited(_refreshBackState(controller));
                      },
                      onProgressChanged: (controller, value) {
                        if (mounted) setState(() => _progress = value);
                      },
                      onLoadStop: (controller, url) {
                        final uri = _httpUri(url?.toString() ?? '');
                        if (uri != null && !_isApproved(uri)) {
                          _blockLink(uri);
                          unawaited(_recoverUnexpectedPage(controller));
                          return;
                        }
                        if (uri != null) _recordSafePage(uri);
                        if (mounted) setState(() { _loading = false; _progress = 100; });
                        unawaited(_refreshBackState(controller));
                      },
                      onUpdateVisitedHistory: (controller, url, isReload) {
                        final uri = _httpUri(url?.toString() ?? '');
                        if (uri != null && !_isApproved(uri)) {
                          _blockLink(uri);
                          unawaited(_recoverUnexpectedPage(controller));
                        } else {
                          unawaited(_refreshBackState(controller));
                        }
                      },
                      onReceivedError: (controller, request, error) {
                        if (request.isForMainFrame != true || !mounted) return;
                        final failed = _httpUri(request.url.toString());
                        // Canceled popups / unapproved redirects are deliberate,
                        // and must never replace the real page with an error.
                        if (failed != null && !_isApproved(failed)) return;
                        setState(() { _loading = false; _loadError =
                          'The download page could not be loaded. Check your connection and retry.'; });
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
                        // Do not load target="_blank" / window.open links into
                        // the CURRENT WebView. They are the main source of
                        // onclick ads taking users away from download servers.
                        final uri = _httpUri(action.request.url?.toString() ?? '');
                        if (uri == null) return false;
                        if (_directFile.hasMatch(uri.path) || action.shouldPerformDownload == true) {
                          unawaited(_verifyAndAsk(uri.toString()));
                        } else {
                          // Legitimate new-tab server links remain available
                          // through an explicit user-controlled review action.
                          _blockLink(uri);
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
                  const Expanded(child: Text('Redirect blocked — download page protected',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.white70))),
                  TextButton(onPressed: _reviewBlockedLink, child: const Text('Review')),
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
                  tooltip: 'Back on download page',
                  onPressed: !_canGoBack && _blockedLink == null ? null : () async {
                    await _handleBack();
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: 'Refresh download page',
                  onPressed: () => _webView?.reload(),
                  icon: const Icon(Icons.refresh_rounded),
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
                TextButton.icon(
                  onPressed: _returnToDownloadPage,
                  icon: const Icon(Icons.history_rounded, size: 17),
                  label: const Text('Page'),
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
