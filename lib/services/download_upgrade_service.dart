import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/download_upgrade_screen.dart';
import 'auth_service.dart';
import 'premium_service.dart';

/// Shows a one-time, optional Remove Ads offer on the fifth valid Download tap.
///
/// A tap only means the user requested the external download flow. The app
/// cannot verify that a third-party browser actually completed a download.
/// Counts are stored locally per signed-in Gmail account on this device.
class DownloadUpgradeService {
  DownloadUpgradeService._();

  static const int _offerAtTap = 5;
  static const String _keyPrefix = 'damimovies_download_upgrade_taps_v1_';
  static bool _handlingTap = false;

  /// Always continues the requested download when the optional offer closes,
  /// including when the user uses Android Back instead of the Continue button.
  static Future<void> onDownloadTap(
    BuildContext context, {
    required Future<void> Function() continueDownload,
  }) async {
    // Prevent double taps racing to show the offer or opening two browsers.
    if (_handlingTap) return;
    _handlingTap = true;
    try {
      try {
        await PremiumService.instance.ensureLoaded();
        if (!PremiumService.instance.active) {
          final preferences = await SharedPreferences.getInstance();
          final email =
              AuthService.instance.user?.email.trim().toLowerCase() ?? '';
          final accountKey = email.isEmpty ? 'guest' : email;
          final key = '$_keyPrefix$accountKey';
          final previous = preferences.getInt(key) ?? 0;

          // Saturate the counter: after the first offer it never repeats.
          if (previous < _offerAtTap) {
            final next = previous + 1;
            final saved = await preferences.setInt(key, next);
            if (saved && next == _offerAtTap && context.mounted) {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const DownloadUpgradeScreen(),
                ),
              );
            }
          }
        }
      } catch (error) {
        // Storage, navigation, or premium-state failures must not block the
        // download flow.
        debugPrint('DamiMovies: download offer skipped: $error');
      }

      if (context.mounted) await continueDownload();
    } finally {
      _handlingTap = false;
    }
  }
}
