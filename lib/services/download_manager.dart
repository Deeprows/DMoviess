import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart' as fd;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/download_task.dart';

// ------------------------------------------------------------- name helpers

String sanitizeFileName(String name) {
  var n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  n = n.replaceAll(RegExp(r'^\.+'), '');
  if (n.length > 120) {
    final dot = n.lastIndexOf('.');
    final ext = (dot > 0 && n.length - dot <= 8) ? n.substring(dot) : '';
    n = n.substring(0, 120 - ext.length) + ext;
  }
  return n.isEmpty ? 'download' : n;
}

String fileNameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'download';
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return 'download';
  var last = segs.last;
  try {
    last = Uri.decodeComponent(last);
  } catch (_) {}
  return sanitizeFileName(last);
}

String? fileNameFromDisposition(String? header) {
  if (header == null || header.isEmpty) return null;
  final star =
      RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false)
          .firstMatch(header);
  if (star != null) {
    try {
      return sanitizeFileName(Uri.decodeComponent(star.group(1)!.trim()));
    } catch (_) {}
  }
  final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false)
      .firstMatch(header);
  if (plain != null) return sanitizeFileName(plain.group(1)!.trim());
  return null;
}

// ---------------------------------------------------- native callback bridge

const _portName = 'damimovies_downloader_port';

/// Runs in a background isolate: forwards progress to the UI isolate.
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final send = IsolateNameServer.lookupPortByName(_portName);
  send?.send([id, status, progress]);
}

// Native status codes (flutter_downloader): 1 enqueued, 2 running,
// 3 complete, 4 failed, 5 canceled, 6 paused.
DownloadStatus? _mapStatus(int s) {
  switch (s) {
    case 1:
    case 2:
      return DownloadStatus.downloading;
    case 3:
      return DownloadStatus.completed;
    case 4:
      return DownloadStatus.failed;
    case 6:
      return DownloadStatus.paused;
  }
  return null;
}

class _Probe {
  final String? error;
  final String? fileName;
  final int? total;

  /// The link answered with a web page (not a file).
  final bool isPage;
  final String contentType;
  const _Probe(
      {this.error,
      this.fileName,
      this.total,
      this.isPage = false,
      this.contentType = ''});
}

class _Attempt {
  final Map<String, String> headers;
  final String fileName;
  final bool publicStorage;
  const _Attempt(this.headers, this.fileName, this.publicStorage);
}

/// What a link really is, for the in-app download scanner.
class LinkInfo {
  /// True when the link is a file we can download.
  final bool isFile;

  /// True when the link is a web page (HTML).
  final bool isPage;
  final String? fileName;
  final int? total;
  const LinkInfo(
      {this.isFile = false, this.isPage = false, this.fileName, this.total});
}

// ------------------------------------------------------------------ manager

/// Background downloader built on the native Android download service
/// (WorkManager + foreground notification via `flutter_downloader`).
///
/// Downloads keep running when the app is minimised or swiped away, show a
/// notification with progress, and are saved to the phone's Downloads folder.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const _prefsKey = 'downloads_v2';

  final List<DownloadTask> _tasks = [];
  final Set<String> _starting = {};
  bool _ready = false;
  bool _available = false;
  Timer? _notifyTimer;
  String? _lastError;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _tasks.where((t) => t.active).length;
  bool get available => _available;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    try {
      await fd.FlutterDownloader.initialize(debug: false, ignoreSsl: false)
          .timeout(const Duration(seconds: 8));
      fd.FlutterDownloader.registerCallback(downloadCallback);
      _available = true;
    } on TimeoutException {
      // The native side is often just slow on first start. Try to use it
      // anyway; enqueue() reports a real error if it truly is not ready.
      try {
        fd.FlutterDownloader.registerCallback(downloadCallback);
      } catch (_) {}
      _available = true;
    } catch (e) {
      debugPrint('FlutterDownloader init failed: $e');
    }

    // Progress updates from the background isolate.
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    port.listen(_onPort);

    // Our list (names, sizes) ...
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) {
          _tasks
            ..clear()
            ..addAll(list.map(DownloadTask.tryParse).whereType<DownloadTask>());
        }
      }
    } catch (_) {}

    // ... reconciled with what the native side says happened meanwhile.
    if (_available) {
      try {
        final native = await fd.FlutterDownloader.loadTasks()
                .timeout(const Duration(seconds: 6)) ??
            [];
        for (final t in List.of(_tasks)) {
          fd.DownloadTask? n;
          for (final x in native) {
            if (x.taskId == t.id) {
              n = x;
              break;
            }
          }
          if (n == null) {
            if (t.status != DownloadStatus.completed) {
              t.status = DownloadStatus.failed;
              t.error = 'This download was interrupted. Start it again.';
            }
            continue;
          }
          t.percent = n.progress;
          final s = n.status;
          if (s == fd.DownloadTaskStatus.complete) {
            t.status = DownloadStatus.completed;
            t.percent = 100;
          } else if (s == fd.DownloadTaskStatus.failed) {
            t.status = DownloadStatus.failed;
            t.error ??= 'Download failed. Tap retry.';
          } else if (s == fd.DownloadTaskStatus.paused) {
            t.status = DownloadStatus.paused;
          } else if (s == fd.DownloadTaskStatus.running ||
              s == fd.DownloadTaskStatus.enqueued) {
            t.status = DownloadStatus.downloading;
          } else if (s == fd.DownloadTaskStatus.canceled) {
            _tasks.remove(t);
          }
        }
      } catch (_) {}
    }
    _changed();
  }

  // ------------------------------------------------------------ bookkeeping

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_tasks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  void _tick() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 300), notifyListeners);
  }

  void _changed() {
    _notifyTimer?.cancel();
    notifyListeners();
    _save();
  }

  DownloadTask? _find(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _onPort(dynamic data) {
    if (data is! List || data.length < 3) return;
    final id = data[0] as String;
    final status = data[1] as int;
    final progress = data[2] as int;
    final t = _find(id);
    if (t == null) return;

    final mapped = _mapStatus(status);
    if (progress >= 0) t.percent = progress;
    if (mapped == null) {
      // canceled / undefined
      if (status == 5) {
        _tasks.remove(t);
        _changed();
      }
      return;
    }
    final changed = mapped != t.status;
    t.status = mapped;
    if (mapped == DownloadStatus.completed) t.percent = 100;
    if (mapped == DownloadStatus.failed) {
      t.error = 'Download failed. Check your connection and tap retry.';
    } else {
      t.error = null;
    }
    changed ? _changed() : _tick();
  }

  // -------------------------------------------------------------------- API

  /// Starts a background download. Returns null on success, otherwise a
  /// message that can be shown to the user.
  Future<String?> enqueue(
    String url, {
    String referer = '',
    String cookie = '',
    String? name,
  }) async {
    if (!_available) {
      return 'Background downloads aren\'t available on this device.';
    }

    // Same link already in the list -> resume it instead of duplicating.
    for (final t in _tasks) {
      if (t.url == url && t.status != DownloadStatus.completed) {
        if (t.status == DownloadStatus.paused ||
            t.status == DownloadStatus.failed) {
          await resume(t.id);
        }
        return null;
      }
    }

    // A second tap while the first is still being checked does nothing.
    if (!_starting.add(url)) return null;
    try {
      return await _enqueue(url, referer, cookie, name);
    } finally {
      _starting.remove(url);
    }
  }

  Future<String?> _enqueue(
      String url, String referer, String cookie, String? name) async {
    final probe = await _probe(url, referer, cookie);
    if (probe.error != null) return probe.error;

    unawaited(_askNotificationPermission());
    await _askStoragePermission();

    final dir = await _saveDir();
    final fileName = _pickName(name, probe, url);
    final full = <String, String>{
      'User-Agent': AppConfig.userAgent,
      if (referer.isNotEmpty) 'Referer': referer,
      if (cookie.isNotEmpty && !cookie.contains('\n')) 'Cookie': cookie,
    };
    final slim = <String, String>{
      'User-Agent': AppConfig.userAgent,
      if (referer.isNotEmpty) 'Referer': referer,
    };
    final asciiName = fileName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');

    // Try the nicest option first (shows in the phone's Downloads folder),
    // then simpler ones, so one picky Android version does not block everything.
    final attempts = <_Attempt>[
      _Attempt(full, fileName, true),
      _Attempt(full, fileName, false),
      _Attempt(slim, asciiName, false),
    ];
    String? id;
    _lastError = null;
    for (final a in attempts) {
      try {
        id = await fd.FlutterDownloader.enqueue(
          url: url,
          savedDir: dir,
          fileName: a.fileName,
          headers: a.headers,
          showNotification: true,
          openFileFromNotification: true,
          saveInPublicStorage: a.publicStorage,
        );
        if (id != null) break;
      } catch (e) {
        _lastError = e.toString();
        debugPrint('Download enqueue failed: $e');
      }
    }
    if (id == null) return 'Couldn\'t start the download${_shortError()}.';

    _tasks.insert(
      0,
      DownloadTask(
        id: id,
        url: url,
        referer: referer,
        name: fileName,
        total: probe.total,
      ),
    );
    _changed();
    return null;
  }

  String _shortError() {
    var e = _lastError;
    if (e == null || e.isEmpty) return '';
    e = e.replaceFirst('PlatformException(', '').replaceAll('\n', ' ').trim();
    if (e.length > 90) e = '${e.substring(0, 90)}…';
    return ' ($e)';
  }

  /// Real file name: the server's own name wins, then the link's, then the
  /// label from the page. Always ends with an extension so the file opens.
  String _pickName(String? given, _Probe probe, String url) {
    final hasExt = RegExp(r'\.[A-Za-z0-9]{2,5}$');
    var base = probe.fileName ?? '';
    if (base.isEmpty) {
      final fromUrl = fileNameFromUrl(url);
      if (hasExt.hasMatch(fromUrl)) base = fromUrl;
    }
    if (base.isEmpty && given != null && given.trim().isNotEmpty) base = given;
    if (base.isEmpty) base = fileNameFromUrl(url);
    base = sanitizeFileName(base);
    if (!hasExt.hasMatch(base)) {
      final t = probe.contentType;
      if (t.contains('matroska')) {
        base = '$base.mkv';
      } else if (t.contains('webm')) {
        base = '$base.webm';
      } else if (t.contains('mp4') || t.startsWith('video/')) {
        base = '$base.mp4';
      } else if (t.contains('zip')) {
        base = '$base.zip';
      }
    }
    return base;
  }

  /// Checks what a link is (file or web page) without downloading it.
  Future<LinkInfo> checkLink(String url,
      {String referer = '', String cookie = ''}) async {
    final p = await _probe(url, referer, cookie);
    if (p.isPage) return const LinkInfo(isPage: true);
    if (p.error != null) return const LinkInfo();
    return LinkInfo(isFile: true, fileName: p.fileName, total: p.total);
  }

  Future<void> pause(String id) async {
    final t = _find(id);
    if (t == null || !t.active) return;
    try {
      await fd.FlutterDownloader.pause(taskId: id);
      t.status = DownloadStatus.paused;
      _changed();
    } catch (_) {}
  }

  Future<void> resume(String id) async {
    final t = _find(id);
    if (t == null || t.status == DownloadStatus.completed || t.active) return;
    try {
      final newId = t.status == DownloadStatus.failed
          ? await fd.FlutterDownloader.retry(taskId: id)
          : await fd.FlutterDownloader.resume(taskId: id);
      if (newId != null) {
        t.id = newId;
        t.status = DownloadStatus.downloading;
        t.error = null;
        _changed();
      } else {
        t.status = DownloadStatus.failed;
        t.error = 'Couldn\'t resume. The server may not allow it.';
        _changed();
      }
    } catch (_) {
      t.status = DownloadStatus.failed;
      t.error = 'Couldn\'t resume. Open the link again.';
      _changed();
    }
  }

  /// Stops the task and removes it, deleting the file.
  Future<void> cancel(String id) async {
    final t = _find(id);
    if (t == null) return;
    if (t.active) {
      try {
        await fd.FlutterDownloader.cancel(taskId: id);
      } catch (_) {}
    }
    await remove(id, deleteFile: true);
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    final t = _find(id);
    if (t == null) return;
    _tasks.remove(t);
    _changed();
    try {
      await fd.FlutterDownloader.remove(
          taskId: id, shouldDeleteContent: deleteFile);
    } catch (_) {}
  }

  Future<void> clearFinished() async {
    final done =
        _tasks.where((t) => t.status == DownloadStatus.completed).toList();
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    _changed();
    for (final t in done) {
      try {
        await fd.FlutterDownloader.remove(
            taskId: t.id, shouldDeleteContent: false);
      } catch (_) {}
    }
  }

  /// Opens a finished download with an installed app. False if it couldn't.
  Future<bool> open(String id) async {
    try {
      return await fd.FlutterDownloader.open(taskId: id);
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<String> _saveDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/Downloads');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  Future<void> _askStoragePermission() async {
    try {
      final s = await Permission.storage.status;
      if (!s.isGranted) await Permission.storage.request();
    } catch (_) {}
  }

  Future<void> _askNotificationPermission() async {
    try {
      final s = await Permission.notification.status;
      if (!s.isGranted) await Permission.notification.request();
    } catch (_) {}
  }

  /// Asks the server for the first byte only: tells us the real file name and
  /// size, and catches links that return a web page instead of a file.
  Future<_Probe> _probe(String url, String referer, String cookie) async {
    final client = http.Client();
    Future<http.StreamedResponse> send(bool range) {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..maxRedirects = 8;
      req.headers['User-Agent'] = AppConfig.userAgent;
      req.headers['Accept'] = '*/*';
      if (referer.isNotEmpty) req.headers['Referer'] = referer;
      if (cookie.isNotEmpty) req.headers['Cookie'] = cookie;
      if (range) req.headers['Range'] = 'bytes=0-0';
      return client.send(req).timeout(const Duration(seconds: 12));
    }

    try {
      var res = await send(true);
      if (res.statusCode >= 400) res = await send(false);
      if (res.statusCode >= 400) {
        return _Probe(error: 'The server replied ${res.statusCode}.');
      }

      final type = (res.headers['content-type'] ?? '').toLowerCase();
      final disp = fileNameFromDisposition(res.headers['content-disposition']);
      if (type.startsWith('text/html') && disp == null) {
        return const _Probe(
            isPage: true,
            error: 'This link opens a web page, not a file. Use the page\'s '
                'own download button.');
      }

      int? total;
      final range = res.headers['content-range'];
      if (res.statusCode == 206 && range != null) {
        final m = RegExp(r'/(\d+)\s*$').firstMatch(range);
        if (m != null) total = int.tryParse(m.group(1)!);
      } else if (res.statusCode == 200 &&
          res.contentLength != null &&
          res.contentLength! > 0) {
        total = res.contentLength;
      }
      return _Probe(fileName: disp, total: total, contentType: type);
    } on TimeoutException {
      return const _Probe(error: 'The server took too long to respond.');
    } catch (_) {
      return const _Probe(error: 'Couldn\'t reach the server.');
    } finally {
      client.close();
    }
  }
}
