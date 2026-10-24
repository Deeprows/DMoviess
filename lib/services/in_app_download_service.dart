import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'download_manager.dart';

/// Bridges a real file-download event from the in-app browser to the existing
/// Android native background transfer engine. This NEVER opens a web browser.
/// No HTML page is queued as a video file.
class InAppDownloadService {
  const InAppDownloadService._();

  static Future<String?> saveFile({
    required String url,
    required String pageUrl,
    String? suggestedName,
    String? mimeType,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null ||
        (target.scheme != 'https' && target.scheme != 'http') ||
        target.host.isEmpty) {
      return 'This page did not provide a downloadable HTTP file.';
    }

    // Only use cookies scoped to the target file's host; never collect all
    // website cookies and forward them to an unrelated download domain.
    String cookies = '';
    try {
      final scoped = await CookieManager.instance().getCookies(
        url: WebUri(url),
      );
      cookies = scoped.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (error) {
      debugPrint('DamiMovies: download cookies unavailable: $error');
    }

    final manager = DownloadManager.instance;
    await manager.init();
    if (!manager.available) {
      return 'The Android download service is unavailable. Please restart the app.';
    }

    // Native downloader keeps tasks running when the embedded page is closed.
    // Referer and the target-host cookies help supported providers validate
    // a download that was initiated on their page.
    return manager.enqueueFromWebView(
      url,
      referer: pageUrl,
      cookie: cookies,
      name: suggestedName,
      mimeType: mimeType,
    );
  }
}
