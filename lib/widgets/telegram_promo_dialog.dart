import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/telegram_popup_service.dart';

/// Image-led vertical promotion. When imageUrl is blank or fails to load, the
/// built-in red/black poster still looks intentional.
class TelegramPromoDialog extends StatelessWidget {
  const TelegramPromoDialog({super.key, required this.config});

  final TelegramPopupConfig config;

  Future<void> _openChannel(BuildContext context) async {
    final uri = Uri.tryParse(config.telegramUrl);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        await TelegramPopupService.markJoined(config);
      }
      if (opened && context.mounted) {
        Navigator.of(context).pop();
      } else if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not open Telegram. Please try again.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not open Telegram. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final height = (screen.height * 0.66).clamp(340.0, 570.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF2A0B17),
                              Color(0xFF83152C),
                              Color(0xFF100A12),
                            ],
                          ),
                        ),
                      ),
                      if (config.imageUrl.startsWith('https://'))
                        Image.network(
                          config.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x3A000000),
                              Color(0x19000000),
                              Color(0xE9000000),
                            ],
                            stops: [0, .32, 1],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                        child: Column(
                          children: [
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF229ED9).withValues(alpha: .88),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x6633AAFF), blurRadius: 28),
                                ],
                              ),
                              child: const Icon(Icons.send_rounded,
                                  size: 29, color: Colors.white),
                            ),
                            const Spacer(),
                            Text(
                              config.title.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                config.highlight.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFFC85A),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                            if (config.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 13),
                              Text(
                                config.subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              height: 49,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF3158),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () => _openChannel(context),
                                icon: const Icon(Icons.send_rounded, size: 18),
                                label: Text(config.buttonText,
                                    style: const TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: const Color(0xED090A0E),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
