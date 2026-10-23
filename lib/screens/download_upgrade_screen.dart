import 'package:flutter/material.dart';

import 'remove_ads_screen.dart';

/// An optional one-time offer shown before handing off the fifth download tap.
/// Closing the offer (including Android Back) resumes the original download.
class DownloadUpgradeScreen extends StatelessWidget {
  const DownloadUpgradeScreen({super.key});

  static const Color _background = Color(0xFF0A0B12);
  static const Color _red = Color(0xFFFF315B);
  static const Color _gold = Color(0xFFFFCB72);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          const Positioned(
            top: -145,
            right: -120,
            child: _Glow(size: 350, color: Color(0x42F32B59)),
          ),
          const Positioned(
            bottom: -210,
            left: -170,
            child: _Glow(size: 420, color: Color(0x222B51D4)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Continue download',
                          onPressed: () => Navigator.of(context).pop(),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: .08),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFD994), Color(0xFFFF6F52), _red],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x55F62650),
                                blurRadius: 36,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.workspace_premium_rounded,
                            size: 66,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _gold.withValues(alpha: .12),
                            border: Border.all(color: _gold.withValues(alpha: .35)),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text(
                            'YOU LOVE MOVIES. WE LOVE THAT!',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your next movie deserves fewer interruptions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'You have tapped Download five times! '
                        'Enjoying DamiMovies? Explore Remove Ads '
                        'and make your app experience smoother.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFBABBC9),
                          fontSize: 14.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171821),
                          border: Border.all(color: const Color(0xFF30313E)),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Column(
                          children: [
                            _Benefit(
                              icon: Icons.block_rounded,
                              title: 'Remove app ads',
                              subtitle: 'Enjoy DamiMovies without in-app ad interruptions.',
                            ),
                            Divider(color: Color(0xFF30313E), height: 26),
                            _Benefit(
                              icon: Icons.favorite_rounded,
                              title: 'Support DamiMovies',
                              subtitle: 'Help us keep improving your movie experience.',
                            ),
                            Divider(color: Color(0xFF30313E), height: 26),
                            _Benefit(
                              icon: Icons.lock_open_rounded,
                              title: 'Your choice, always',
                              subtitle: 'You can still download without upgrading.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const RemoveAdsScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.workspace_premium_rounded),
                          label: const Text(
                            'Explore Remove Ads',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Not now · Continue Download',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;
  const _Glow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0x22FF315B),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: DownloadUpgradeScreen._red, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFB1B2C1),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
