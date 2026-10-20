import 'package:flutter/material.dart';
import '../main.dart';
import '../services/download_manager.dart';
import '../services/download_scanner.dart';
import 'downloads_screen.dart';

class DownloadScannerScreen extends StatefulWidget {
  final String pageUrl;
  const DownloadScannerScreen({super.key, required this.pageUrl});
  @override State<DownloadScannerScreen> createState() => _DownloadScannerScreenState();
}

class _DownloadScannerScreenState extends State<DownloadScannerScreen> {
  late final DownloadScanner _scanner;
  @override void initState() {
    super.initState();
    _scanner = DownloadScanner()..init();
    _scanner.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanner.start(widget.pageUrl));
  }
  void _changed() { if (mounted) setState(() {}); }
  @override void dispose() { _scanner.removeListener(_changed); _scanner.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find downloads'), actions: [
      IconButton(tooltip: 'Scan again', onPressed: _scanner.scanning ? null : () => _scanner.rescan(widget.pageUrl), icon: const Icon(Icons.refresh_rounded)),
      IconButton(tooltip: 'My downloads', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())), icon: const Icon(Icons.download_done_rounded)),
    ]),
    body: Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(14), color: appSurface, child: Row(children: [
        if (_scanner.scanning) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else const Icon(Icons.search_rounded),
        const SizedBox(width: 10), Expanded(child: Text(_scanner.status, style: const TextStyle(fontWeight: FontWeight.w600))),
      ])),
      Expanded(child: _scanner.files.isEmpty
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_scanner.scanning ? 'Checking the page for direct video and file links…' : 'No direct download links found on this page.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))))
        : ListView.separated(padding: const EdgeInsets.all(12), itemCount: _scanner.files.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) {
          final file = _scanner.files[index];
          final label = file.label.isEmpty ? (file.fileName ?? file.host) : file.label;
          return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(14)), child: Row(children: [
            Icon(file.extension == 'mp4' || file.extension == 'mkv' || file.extension == 'webm' ? Icons.movie_rounded : Icons.insert_drive_file_rounded, color: appRed, size: 30),
            const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('${file.host}${file.quality == null ? '' : ' • ${file.quality}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white54))])),
            IconButton(tooltip: 'Download in app', onPressed: () async {
              final error = await DownloadManager.instance.enqueue(file.url, referer: file.referer, name: file.fileName ?? label);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Download started')));
            }, icon: const Icon(Icons.download_rounded)),
          ]));
        })),
    ]),
  );
}
