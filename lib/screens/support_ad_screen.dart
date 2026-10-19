import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../main.dart';
import 'remove_ads_screen.dart';

/// "We Need Your Support" page: loads the support / smart link and shows
/// Skip Ad once `skipAfterSeconds` have passed since the ad loaded.
class SupportAdScreen extends StatefulWidget {
  final String url;
  final int skipAfterSeconds;
  const SupportAdScreen({super.key, required this.url, required this.skipAfterSeconds});

  @override
  State<SupportAdScreen> createState() => _SupportAdScreenState();
}

class _SupportAdScreenState extends State<SupportAdScreen> {
  late final WebViewController _controller;
  Timer? _countdown;
  Timer? _fallback;
  late int _left;
  bool _counting = false;
  bool _canSkip = false;

  @override
  void initState() {
    super.initState();
    _left = widget.skipAfterSeconds;
    if (_left <= 0) _canSkip = true;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _startCountdown(),
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) setState(() => _canSkip = true);
        },
        onNavigationRequest: (request) {
          final scheme = Uri.tryParse(request.url)?.scheme.toLowerCase() ?? '';
          // Keep the ad inside the app: no hand-off to other apps.
          return scheme == 'http' || scheme == 'https' || scheme == 'about'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
    // If the page never finishes loading, still start the countdown so the
    // user is never stuck.
    _fallback = Timer(const Duration(seconds: 12), _startCountdown);
  }

  void _startCountdown() {
    if (_counting || _canSkip || !mounted) return;
    _counting = true;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _left--;
        if (_left <= 0) {
          _canSkip = true;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _fallback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _canSkip,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(children: [
              Container(
                color: appSurface,
                padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                child: Row(children: [
                  Icon(Icons.favorite_rounded, color: appRed, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('We Need Your Support',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  _canSkip
                      ? FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: appRed),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Skip Ad'),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(_counting ? 'Skip in $_left' : 'Loading…',
                              style: const TextStyle(color: Colors.white60, fontSize: 13)),
                        ),
                ]),
              ),
              Expanded(child: WebViewWidget(controller: _controller)),
              Container(
                width: double.infinity,
                color: appSurface,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(children: [
                  const Expanded(
                    child: Text('Ads keep DamiMovies free. Thank you!',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const RemoveAdsScreen())),
                    icon: const Icon(Icons.block_rounded, size: 16),
                    label: const Text('Remove ads'),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}
