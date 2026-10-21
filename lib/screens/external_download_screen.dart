import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Download handoff: no embedded browser, scanner, or in-app downloader.
class ExternalDownloadScreen extends StatefulWidget {
  final String movieTitle;
  final String downloadUrl;

  const ExternalDownloadScreen({
    super.key,
    required this.movieTitle,
    required this.downloadUrl,
  });

  @override
  State<ExternalDownloadScreen> createState() => _ExternalDownloadScreenState();
}

class _ExternalDownloadScreenState extends State<ExternalDownloadScreen> {
  bool _opening = false;

  Future<void> _openExternalBrowser() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final uri = Uri.tryParse(widget.downloadUrl);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        throw const FormatException('Invalid download link');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Unable to open external browser');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open your browser. Please check your browser settings.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D13),
        foregroundColor: Colors.white,
        title: const Text('Download in Browser'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B202C),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.open_in_browser_rounded,
                      size: 64, color: Color(0xFFE53955)),
                ),
                const SizedBox(height: 28),
                Text(widget.movieTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 23, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                const Text('Continue your download in an external browser',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 19,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text(
                  'DamiMovies does not download files inside the app. Tap below to open the download page in your phone’s browser and follow the instructions there.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _opening ? null : _openExternalBrowser,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE53955),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(_opening ? 'Opening browser…' : 'Open External Browser'),
                  ),
                ),
                const SizedBox(height: 22),
                const Text('Come back to DamiMovies for more great movies!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to DamiMovies'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
