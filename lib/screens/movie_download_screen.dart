// IN-APP DOWNLOADS DISABLED: downloads now open in the user's external browser.
// This file is commented out on purpose; remove the leading '// ' to restore it.
// import 'dart:async';
//
// import 'package:flutter/material.dart';
// import 'package:webview_flutter/webview_flutter.dart';
//
// import '../main.dart';
// import '../models/movie.dart';
// import '../services/download_manager.dart';
// import '../services/download_scanner.dart';
// import 'browser_screen.dart';
// import 'downloads_screen.dart';
//
// /// "Download" page of a movie. The third-party download page is scanned in
// /// the background; direct files it offers show up here with their own
// /// Download button, so the person never has to use the other site.
// class MovieDownloadScreen extends StatefulWidget {
//   final Movie movie;
//
//   /// Direct file links already known (for example the stream being played).
//   final List<String> directUrls;
//   const MovieDownloadScreen({super.key, required this.movie, this.directUrls = const []});
//
//   @override
//   State<MovieDownloadScreen> createState() => _MovieDownloadScreenState();
// }
//
// class _MovieDownloadScreenState extends State<MovieDownloadScreen> {
//   final DownloadScanner _scanner = DownloadScanner();
//   final Map<String, String> _state = {}; // url -> starting | started | error text
//   bool _showPage = false;
//
//   String get _pageUrl => widget.movie.downloadUrl.trim();
//
//   @override
//   void initState() {
//     super.initState();
//     _scanner.init();
//     unawaited(_scanner.start(_pageUrl, directUrls: widget.directUrls));
//   }
//
//   @override
//   void dispose() {
//     _scanner.dispose();
//     super.dispose();
//   }
//
//   String _suggestedName(FoundFile f) {
//     final m = widget.movie;
//     final parts = [
//       m.title,
//       if (m.year.isNotEmpty) '(${m.year})',
//       if (f.quality != null) f.quality!,
//       if (f.server != null) '- ${f.server}',
//     ];
//     final base = parts.join(' ').trim();
//     if (m.title.trim().isEmpty) return f.fileName ?? fileNameFromUrl(f.url);
//     return sanitizeFileName('$base.${f.extension}');
//   }
//
//   String _size(int? bytes) {
//     if (bytes == null || bytes <= 0) return '';
//     const kb = 1024, mb = 1024 * 1024, gb = 1024 * 1024 * 1024;
//     if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
//     if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
//     return '${(bytes / kb).toStringAsFixed(0)} KB';
//   }
//
//   Future<void> _download(FoundFile f) async {
//     if (_state[f.url] == 'starting') return;
//     setState(() => _state[f.url] = 'starting');
//     final error = await DownloadManager.instance.enqueue(
//       f.url,
//       referer: f.referer,
//       cookie: _scanner.cookie,
//       name: _suggestedName(f),
//     );
//     if (!mounted) return;
//     setState(() => _state[f.url] = error ?? 'started');
//   }
//
//   void _openDownloads() => Navigator.push(
//       context, MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()));
//
//   void _openPage() => Navigator.push(context,
//       MaterialPageRoute<void>(builder: (_) => BrowserScreen(initialUrl: _pageUrl)));
//
//   @override
//   Widget build(BuildContext context) => ListenableBuilder(
//         listenable: _scanner,
//         builder: (context, _) => Scaffold(
//           appBar: AppBar(
//             title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//               const Text('Download', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
//               Text(widget.movie.title,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: const TextStyle(fontSize: 12, color: Colors.white60)),
//             ]),
//             actions: [
//               IconButton(
//                 tooltip: _showPage ? 'Hide page' : 'Show page (if it asks for a check)',
//                 onPressed: () => setState(() => _showPage = !_showPage),
//                 icon: Icon(_showPage ? Icons.visibility_off_rounded : Icons.visibility_rounded),
//               ),
//               IconButton(
//                 tooltip: 'Scan again',
//                 onPressed: _scanner.scanning ? null : () => _scanner.rescan(_pageUrl),
//                 icon: const Icon(Icons.refresh_rounded),
//               ),
//               IconButton(
//                 tooltip: 'Downloads',
//                 onPressed: _openDownloads,
//                 icon: const Icon(Icons.download_done_rounded),
//               ),
//             ],
//           ),
//           body: Stack(children: [
//             Column(children: [
//               _statusBar(),
//               Expanded(child: _body()),
//             ]),
//             // The scanning browser. Hidden (1 px) unless the person wants to
//             // see it, for example to pass a "are you human" check.
//             if (_showPage)
//               Positioned.fill(
//                 child: Column(children: [
//                   Container(
//                     color: appSurface,
//                     padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//                     child: Row(children: [
//                       const Expanded(
//                           child: Text('Finish any check on the page, links appear in the list.',
//                               style: TextStyle(fontSize: 12, color: Colors.white70))),
//                       TextButton(onPressed: () => setState(() => _showPage = false), child: const Text('Done')),
//                     ]),
//                   ),
//                   Expanded(child: WebViewWidget(controller: _scanner.controller)),
//                 ]),
//               )
//             else
//               // 1 px on screen, but laid out as a phone-sized page so the site
//               // builds its normal mobile layout (buttons, servers ...).
//               Positioned(
//                 left: 0,
//                 top: 0,
//                 width: 1,
//                 height: 1,
//                 child: ClipRect(
//                   child: OverflowBox(
//                     alignment: Alignment.topLeft,
//                     minWidth: 390,
//                     maxWidth: 390,
//                     minHeight: 780,
//                     maxHeight: 780,
//                     child: WebViewWidget(controller: _scanner.controller),
//                   ),
//                 ),
//               ),
//           ]),
//         ),
//       );
//
//   Widget _statusBar() => Container(
//         width: double.infinity,
//         color: appSurface,
//         padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
//         child: Row(children: [
//           if (_scanner.scanning)
//             SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.4, color: appRed))
//           else
//             Icon(_scanner.files.isEmpty ? Icons.search_off_rounded : Icons.check_circle_rounded,
//                 size: 18, color: _scanner.files.isEmpty ? Colors.white54 : Colors.greenAccent),
//           const SizedBox(width: 12),
//           Expanded(
//               child: Text(_scanner.status,
//                   style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
//         ]),
//       );
//
//   Widget _body() {
//     final files = _scanner.files;
//     if (files.isEmpty) {
//       if (_scanner.scanning) {
//         return const Center(
//             child: Padding(
//                 padding: EdgeInsets.all(28),
//                 child: Text('Reading the download page for you.\nNo need to open it.',
//                     textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))));
//       }
//       return Center(
//         child: Padding(
//           padding: const EdgeInsets.all(28),
//           child: Column(mainAxisSize: MainAxisSize.min, children: [
//             const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.white24),
//             const SizedBox(height: 14),
//             const Text('Nothing to download here yet',
//                 style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
//             const SizedBox(height: 6),
//             const Text('The page may need a check first, or has no file for this title.',
//                 textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
//             const SizedBox(height: 18),
//             Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
//               FilledButton.icon(
//                   style: FilledButton.styleFrom(backgroundColor: appRed),
//                   onPressed: () => setState(() => _showPage = true),
//                   icon: const Icon(Icons.visibility_rounded),
//                   label: const Text('Show page')),
//               OutlinedButton.icon(
//                   onPressed: () => _scanner.rescan(_pageUrl),
//                   icon: const Icon(Icons.refresh_rounded),
//                   label: const Text('Scan again')),
//               if (_pageUrl.startsWith('http'))
//                 TextButton(onPressed: _openPage, child: const Text('Open in browser')),
//             ]),
//           ]),
//         ),
//       );
//     }
//     return ListView.separated(
//       padding: const EdgeInsets.all(14),
//       itemCount: files.length,
//       separatorBuilder: (_, __) => const SizedBox(height: 10),
//       itemBuilder: (_, i) => _card(files[i]),
//     );
//   }
//
//   Widget _card(FoundFile f) {
//     final st = _state[f.url];
//     final started = st == 'started';
//     final starting = st == 'starting';
//     final failed = st != null && !started && !starting;
//     final size = _size(f.total);
//     return Container(
//       padding: const EdgeInsets.all(13),
//       decoration: BoxDecoration(
//         color: appSurface,
//         borderRadius: BorderRadius.circular(15),
//         border: Border.all(color: Colors.white10),
//       ),
//       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         Row(children: [
//           Container(
//             width: 44,
//             height: 48,
//             decoration: BoxDecoration(color: appRed.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
//             child: Icon(Icons.movie_rounded, color: appRed),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//               Text(_suggestedName(f),
//                   maxLines: 2, overflow: TextOverflow.ellipsis,
//                   style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
//               const SizedBox(height: 5),
//               if (f.label.isNotEmpty)
//                 Padding(
//                   padding: const EdgeInsets.only(bottom: 5),
//                   child: Text(f.label,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: const TextStyle(fontSize: 11, color: Colors.white54)),
//                 ),
//               Wrap(spacing: 8, runSpacing: 4, children: [
//                 if (f.quality != null) _chip(f.quality!, appRed),
//                 _chip(f.extension.toUpperCase(), Colors.white24),
//                 if (size.isNotEmpty) _chip(size, Colors.white24),
//                 Text(f.host, style: const TextStyle(fontSize: 11, color: Colors.white38)),
//               ]),
//             ]),
//           ),
//         ]),
//         const SizedBox(height: 11),
//         if (failed)
//           Padding(
//             padding: const EdgeInsets.only(bottom: 8),
//             child: Text(st, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
//           ),
//         SizedBox(
//           width: double.infinity,
//           height: 44,
//           child: started
//               ? OutlinedButton.icon(
//                   onPressed: _openDownloads,
//                   icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
//                   label: const Text('Download started · View'))
//               : FilledButton.icon(
//                   style: FilledButton.styleFrom(backgroundColor: appRed),
//                   onPressed: starting ? null : () => _download(f),
//                   icon: starting
//                       ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
//                       : const Icon(Icons.download_rounded),
//                   label: Text(starting ? 'Starting…' : (failed ? 'Try again' : 'Download')),
//                 ),
//         ),
//       ]),
//     );
//   }
//
//   Widget _chip(String text, Color color) => Container(
//         padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
//         decoration: BoxDecoration(
//           color: color.withValues(alpha: color == Colors.white24 ? 1 : .18),
//           borderRadius: BorderRadius.circular(6),
//         ),
//         child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
//       );
// }
//
