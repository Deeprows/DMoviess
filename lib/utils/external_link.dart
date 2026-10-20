import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _directFile = RegExp(
    r'\.(apk|zip|rar|7z|tar|gz|iso|exe|msi|dmg|torrent|mkv|mp4|avi|mov|m4v|webm|mp3|m4a|pdf|jpg|png|epub)(?:$|[?#])',
    caseSensitive: false);

/// True when [url] points straight at a downloadable file.
bool isDirectMovieDownload(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (_directFile.hasMatch(uri.path)) return true;
  return uri.queryParameters.values.any((v) => _directFile.hasMatch(v));
}

/// Opens [url] in the user's own browser (never inside the app).
/// Returns true when a browser accepted the link.
Future<bool> openInExternalBrowser(BuildContext? context, String url) async {
  final uri = Uri.tryParse(url.trim());
  var ok = false;
  if (uri != null && uri.hasScheme) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your browser for this link.')));
  }
  return ok;
}
