import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signUp = true;
  bool _busy = false;
  AuthFailure? _failure;
  List<String> _posters = const [];

  @override
  void initState() {
    super.initState();
    _loadPosters();
  }

  Future<void> _loadPosters() async {
    try {
      final raw = await rootBundle.loadString('assets/data/movies.json');
      final data = jsonDecode(raw);
      final urls = <String>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            final image = (item['image'] ?? '').toString();
            if (image.startsWith('http')) urls.add(image);
          }
        }
      }
      if (mounted) setState(() => _posters = urls.take(24).toList());
    } catch (_) {}
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await AuthService.instance.signIn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _collage(size),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  appBg.withValues(alpha: .35),
                  appBg.withValues(alpha: .78),
                  appBg,
                ],
                stops: const [0, .55, 1],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _logo(),
                      _card(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _collage(Size size) {
    if (_posters.isEmpty) return const SizedBox.shrink();
    return Transform.rotate(
      angle: -.12,
      child: OverflowBox(
        minWidth: size.width * 1.5,
        maxWidth: size.width * 1.5,
        minHeight: size.height * 1.4,
        maxHeight: size.height * 1.4,
        child: GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .68,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            for (final url in _posters)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => ColoredBox(color: appSurface),
                  placeholder: (_, __) => ColoredBox(color: appSurface),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _logo() => Padding(
        padding: const EdgeInsets.only(top: 44, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/icon/icon.png', width: 84, height: 84, fit: BoxFit.cover),
            ),
            const SizedBox(height: 12),
            const Text('DamiMovies',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.8)),
            const SizedBox(height: 3),
            const Text('YOUR WORLD OF ENTERTAINMENT',
                style: TextStyle(color: Colors.white60, fontSize: 9, letterSpacing: 1.6)),
          ],
        ),
      );

  Widget _card() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tabs(),
                  const SizedBox(height: 26),
                  Text(
                    _signUp ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _signUp
                        ? 'Join with your Gmail to stream, download and save movies.'
                        : 'Log in with your Gmail to pick up where you left off.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  _gmailButton(),
                  if (_failure != null) ...[
                    const SizedBox(height: 14),
                    _error(_failure!),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.lock_outline_rounded, color: Colors.white54, size: 16),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text('Gmail accounts only. No password needed.',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'By continuing you agree that DamiMovies does not host any movies. All content belongs to its owners.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          _tab('Log in', !_signUp, () => setState(() { _signUp = false; _failure = null; })),
          _tab('Sign up', _signUp, () => setState(() { _signUp = true; _failure = null; })),
        ]),
      );

  Widget _tab(String label, bool selected, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? appRed : Colors.transparent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : Colors.white70,
                )),
          ),
        ),
      );

  Widget _gmailButton() => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        elevation: 6,
        shadowColor: appRed.withValues(alpha: .5),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: _busy ? null : _continue,
          child: SizedBox(
            height: 56,
            child: Center(
              child: _busy
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.6, color: appRed),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        _GoogleG(),
                        SizedBox(width: 12),
                        Text('Continue with Gmail',
                            style: TextStyle(color: Color(0xFF1B1B1F), fontSize: 18, fontWeight: FontWeight.w800)),
                      ],
                    ),
            ),
          ),
        ),
      );

  Widget _error(AuthFailure failure) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: appAccentSoft, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(failure.message,
                    style: TextStyle(color: appAccentSoft, fontSize: 14, height: 1.35)),
              ),
            ],
          ),
          if (failure.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(failure.detail, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ],
      );
}

/// A small multicolour "G" so no image asset is needed.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => const SweepGradient(
          colors: [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
            Color(0xFF4285F4),
          ],
          stops: [0, .25, .5, .75, 1],
        ).createShader(rect),
        child: const Text('G',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1)),
      );
}
