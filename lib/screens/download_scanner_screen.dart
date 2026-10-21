import '../utils/l10n.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../main.dart';
import '../services/download_manager.dart';
import '../services/download_scanner.dart';
import '../utils/external_link.dart' show openInExternalBrowser;
import 'downloads_screen.dart';

/// Two ways to use this screen:
///  * full scan (default): lists every direct file found on the page;
///  * single download ([autoDownload]): follows the one Download button the
///    person tapped, skips the ad pages in between and starts the download.
class DownloadScannerScreen extends StatefulWidget {
  final String pageUrl;
  final String? entryUrl;
  final String entryLabel;
  final bool autoDownload;
  const DownloadScannerScreen({
    super.key,
    required this.pageUrl,
    this.entryUrl,
    this.entryLabel = '',
    this.autoDownload = false,
  });
  @override
  State<DownloadScannerScreen> createState() => _DownloadScannerScreenState();
}

class _DownloadScannerScreenState extends State<DownloadScannerScreen> {
  late final DownloadScanner _scanner;
  bool _autoBusy = false;
  bool _autoDone = false;
  final Set<String> _tried = {};
  String? _autoError;
  String? _autoName;
  String _autoUrl = '';

  bool get _single => widget.autoDownload;

  @override
  void initState() {
    super.initState();
    _scanner = DownloadScanner()..init();
    _scanner.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  void _begin() {
    if (!mounted) return;
    _tried.clear();
    setState(() {
      _autoBusy = false;
      _autoDone = false;
      _autoError = null;
      _autoName = null;
    });
    if (_single) {
      _scanner.startSingle(widget.pageUrl,
          url: widget.entryUrl, label: widget.entryLabel);
    } else {
      _scanner.rescan(widget.pageUrl);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_single && !_autoDone && !_autoBusy) {
      final next = _nextFile();
      if (next != null) _startAuto(next);
    }
  }

  /// First file we have not tried yet, video files first.
  FoundFile? _nextFile() {
    const video = ['mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v'];
    FoundFile? any;
    for (final f in List<FoundFile>.of(_scanner.files)) {
      if (_tried.contains(f.url)) continue;
      if (video.contains(f.extension)) return f;
      any ??= f;
    }
    return any;
  }

  Future<void> _startAuto(FoundFile file) async {
    _autoBusy = true;
    _tried.add(file.url);
    _autoUrl = file.url;
    final error = await DownloadManager.instance.enqueue(file.url,
        referer: file.referer,
        cookie: _scanner.cookie,
        name: file.fileName);
    if (!mounted) return;
    setState(() {
      _autoBusy = false;
      _autoError = error;
      _autoDone = error == null;
      _autoName = file.fileName ??
          (file.label.isEmpty ? file.host : file.label);
    });
    // The first file failed (for example it turned out to be a web page):
    // try the next one the scan found, if any.
    if (error != null) _changed();
  }

  Future<void> _downloadFile(FoundFile file, String label) async {
    final error = await DownloadManager.instance.enqueue(file.url,
        referer: file.referer, cookie: _scanner.cookie, name: file.fileName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Download started'),
      duration: const Duration(seconds: 5),
      action: error == null
          ? SnackBarAction(label: 'VIEW', onPressed: _openDownloads)
          : SnackBarAction(
              label: 'OPEN IN BROWSER',
              onPressed: () => openInExternalBrowser(context, file.url)),
    ));
  }

  void _openDownloads() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const DownloadsScreen()));

  @override
  void dispose() {
    _scanner.removeListener(_changed);
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(_single ? 'Download'.tr : 'Find downloads'.tr),
            actions: [
              if (!_single)
                IconButton(
                    tooltip: 'Scan again',
                    onPressed: _scanner.scanning
                        ? null
                        : () => _scanner.rescan(widget.pageUrl),
                    icon: const Icon(Icons.refresh_rounded)),
              IconButton(
                  tooltip: 'My downloads',
                  onPressed: _openDownloads,
                  icon: const Icon(Icons.download_done_rounded)),
            ]),
        // The helper browser sits UNDER the screen's own content. It needs a
        // real size so pages lay out and render their buttons normally.
        body: Stack(children: [
          Positioned.fill(
              child: ExcludeSemantics(
                  child: WebViewWidget(controller: _scanner.controller))),
          Positioned.fill(
              child: Container(
                  color: appBg,
                  child: _single ? _singleBody() : _listBody())),
        ]),
      );

  // ------------------------------------------------------- single download

  Widget _singleBody() {
    final scanning = (_scanner.scanning || _autoBusy) && !_autoDone;
    final failed = !scanning && !_autoDone && _autoError != null;
    final nothing = !scanning && !_autoDone && _autoError == null;
    final fallbackUrl = _autoUrl.isNotEmpty
        ? _autoUrl
        : (widget.entryUrl ?? widget.pageUrl);

    IconData icon;
    Color color;
    String title;
    String body;
    if (_autoDone) {
      icon = Icons.check_circle_rounded;
      color = Colors.greenAccent;
      title = 'Download started';
      body = (_autoName ?? '').isEmpty
          ? 'You can leave this screen. Progress shows in My downloads.'
          : '$_autoName\n\nYou can leave this screen. Progress shows in My downloads.';
    } else if (failed) {
      icon = Icons.error_outline_rounded;
      color = Colors.orangeAccent;
      title = 'Couldn\'t start the download';
      body = _autoError!;
    } else if (nothing) {
      icon = Icons.link_off_rounded;
      color = Colors.orangeAccent;
      title = 'No direct link found';
      body = 'This server did not give a direct file. Try again, pick another '
          'server, or open the link in your phone\'s browser.';
    } else {
      icon = Icons.hourglass_top_rounded;
      color = Colors.white70;
      title = 'Preparing your download';
      body = '${widget.entryLabel.isEmpty ? '' : '${widget.entryLabel}\n\n'}'
          'Skipping the ad pages for you. This can take up to a minute.';
    }

    return Center(
        child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (scanning)
                const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 3))
              else
                Icon(icon, size: 54, color: color),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, height: 1.35)),
              if (scanning) ...[
                const SizedBox(height: 10),
                Text(_scanner.status,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
              const SizedBox(height: 22),
              if (_autoDone) ...[
                FilledButton.icon(
                    onPressed: _openDownloads,
                    style: FilledButton.styleFrom(backgroundColor: appRed),
                    icon: const Icon(Icons.download_done_rounded),
                    label: const Text('View downloads')),
                const SizedBox(height: 8),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to the page')),
              ] else if (failed || nothing) ...[
                FilledButton.icon(
                    onPressed: _begin,
                    style: FilledButton.styleFrom(backgroundColor: appRed),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: () =>
                        openInExternalBrowser(context, fallbackUrl),
                    icon: const Icon(Icons.open_in_browser_rounded),
                    label: const Text('Open in my browser')),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to the page')),
              ] else
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel')),
            ])));
  }

  // ------------------------------------------------------------- full scan

  Widget _listBody() => Column(children: [
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: appSurface,
            child: Row(children: [
              if (_scanner.scanning)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                const Icon(Icons.search_rounded),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(_scanner.status,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ])),
        Expanded(
            child: _scanner.files.isEmpty
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                            _scanner.scanning
                                ? 'Checking the page for direct video and file links…'
                                : 'No direct download links found on this page.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60))))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _scanner.files.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final file = _scanner.files[index];
                      final label = file.label.isEmpty
                          ? (file.fileName ?? file.host)
                          : file.label;
                      final isVideo = file.extension == 'mp4' ||
                          file.extension == 'mkv' ||
                          file.extension == 'webm';
                      return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: appSurface,
                              borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            Icon(
                                isVideo
                                    ? Icons.movie_rounded
                                    : Icons.insert_drive_file_rounded,
                                color: appRed,
                                size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${file.host}${file.quality == null ? '' : ' • ${file.quality}'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white54))
                                ])),
                            IconButton(
                                tooltip: 'Download in app',
                                onPressed: () => _downloadFile(file, label),
                                icon: const Icon(Icons.download_rounded)),
                          ]));
                    })),
      ]);
}
