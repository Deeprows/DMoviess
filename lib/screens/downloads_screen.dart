import 'package:flutter/material.dart';
import '../main.dart';
import '../models/download_task.dart';
import '../services/download_manager.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads', style: TextStyle(fontWeight: FontWeight.w900)), actions: [
        IconButton(tooltip: 'Clear finished downloads', icon: const Icon(Icons.cleaning_services_rounded), onPressed: () => manager.clearFinished()),
      ]),
      body: ListenableBuilder(listenable: manager, builder: (context, _) {
        final tasks = manager.tasks;
        if (!manager.available && tasks.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.download_for_offline_outlined, size: 52, color: Colors.white54), const SizedBox(height: 12), const Text('Background downloads are not ready on this device.', textAlign: TextAlign.center), const SizedBox(height: 8), Text('Open a movie and tap Download to start one.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))])));
        if (tasks.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.download_done_rounded, size: 58, color: Colors.white24), const SizedBox(height: 14), const Text('No downloads yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('Tap Download on a movie and its files will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))])));
        return ListView.separated(padding: const EdgeInsets.all(14), itemCount: tasks.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) {
          final task = tasks[i];
          final status = switch (task.status) {
            DownloadStatus.downloading => 'Downloading · ${task.percent}%',
            DownloadStatus.paused => 'Paused',
            DownloadStatus.completed => 'Completed',
            DownloadStatus.failed => task.error ?? 'Failed',
          };
          return Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(width: 40, height: 45, decoration: BoxDecoration(color: appRed.withValues(alpha: .14), borderRadius: BorderRadius.circular(9)), child: Icon(_icon(task.extension), color: appRed)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(task.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white60))]))]),
            if (task.status == DownloadStatus.downloading) ...[const SizedBox(height: 11), LinearProgressIndicator(value: task.progress, color: appRed, backgroundColor: Colors.white12, minHeight: 4)],
            const SizedBox(height: 7), Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (task.status == DownloadStatus.completed) IconButton(tooltip: 'Open file', onPressed: () => manager.open(task.id), icon: const Icon(Icons.open_in_new_rounded)),
              if (task.status == DownloadStatus.downloading) IconButton(tooltip: 'Pause', onPressed: () => manager.pause(task.id), icon: const Icon(Icons.pause_circle_outline_rounded)),
              if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed) IconButton(tooltip: 'Resume / retry', onPressed: () => manager.resume(task.id), icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.greenAccent)),
              IconButton(tooltip: 'Remove', onPressed: () => manager.remove(task.id, deleteFile: task.status == DownloadStatus.completed), icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54)),
            ]),
          ]));
        });
      }),
    );
  }

  IconData _icon(String ext) => switch (ext) {
    'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'm4v' => Icons.movie_rounded,
    'mp3' || 'aac' || 'm4a' => Icons.music_note_rounded,
    'apk' => Icons.android_rounded,
    'zip' || 'rar' || '7z' => Icons.folder_zip_rounded,
    'pdf' => Icons.picture_as_pdf_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}
