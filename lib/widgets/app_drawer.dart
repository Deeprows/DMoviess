import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../main.dart';
import '../screens/community_profile_screen.dart';
import '../screens/community_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/library_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/watch_together_screen.dart';
import '../services/app_preferences.dart';
import '../services/app_remote_config.dart';
import '../services/auth_service.dart';
import '../services/premium_service.dart';

/// Side menu: a branded header, then one big icon + label row per item.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _go(BuildContext context, Widget page) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _run(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumService.instance;
    final until = premium.until;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
    final items = <_Item>[
      if (RemoteConfig.instance.removeAds.enabled)
        _Item(
          Icons.block_rounded,
          premium.active
              ? 'Premium · ${premium.daysLeft} ${premium.daysLeft == 1 ? 'day' : 'days'}'
              : 'Remove Ads',
          () => _go(context, const RemoveAdsScreen()),
          subtitle: until == null
              ? null
              : 'Ads off until ${until.day} ${months[until.month - 1]} ${until.year}',
        ),
      _Item(Icons.forum_rounded, 'Movie Community'.tr,
          () => _go(context, const CommunityScreen(standalone: true))),
      if (AuthService.instance.user != null)
        _Item(Icons.edit_note_rounded, 'My community posts'.tr,
            () => _go(context,
                CommunityProfileScreen(email: AuthService.instance.user!.email))),
      _Item(Icons.theaters_rounded, 'Watch Together'.tr,
          () => _go(context, const WatchTogetherScreen())),
      _Item(Icons.video_library_rounded, 'My Library',
          () => _go(context, const LibraryScreen())),
      _Item(Icons.download_rounded, 'Downloads',
          () => _go(context, const DownloadsScreen())),
      _Item(Icons.settings_rounded, 'Settings & Themes',
          () => _go(context, const SettingsScreen())),
      _Item(Icons.notifications_rounded, 'Notice',
          () => _go(context, const SettingsScreen())),
      _Item(Icons.share_rounded, 'Share App', () {
        _run(context, () => Share.share(
            'Discover movies with DamiMovies.\n${AppConfig.appUrl}'));
      }),
    ];

    return Drawer(
      width: MediaQuery.sizeOf(context).width * .78,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(),
      child: Column(children: [
        ListenableBuilder(
          listenable: AuthService.instance,
          builder: (context, _) => _header(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [for (final item in items) _tile(item)],
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context) {
    final user = AuthService.instance.user;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.paddingOf(context).top + 28, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [appSurface, appBg],
        ),
      ),
      child: Column(children: [
        user == null ? _brandLogo() : _avatar(user),
        const SizedBox(height: 14),
        if (user == null)
          const Text(AppConfig.appName,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))
        else
          Text(user.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Version: ${AppConfig.appVersion}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  /// The app logo, shown only when nobody is signed in.
  Widget _brandLogo() => Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [appAccentSoft, appRed]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: appRed.withValues(alpha: .35),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
        ),
        child: const Icon(Icons.movie_filter_rounded,
            color: Colors.white, size: 60),
      );

  /// The signed-in Gmail photo, or the first letter of the email when the
  /// account has no photo (or it cannot load).
  Widget _avatar(AuthUser user) {
    const size = 96.0;
    final initial =
        user.email.isEmpty ? '?' : user.email.characters.first.toUpperCase();
    Widget letter() => Container(
          color: appRed,
          alignment: Alignment.center,
          child: Text(initial,
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [appAccentSoft, appRed]),
        boxShadow: [
          BoxShadow(
              color: appRed.withValues(alpha: .35),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: ClipOval(
        child: user.photo.isEmpty
            ? letter()
            : CachedNetworkImage(
                imageUrl: user.photo,
                fit: BoxFit.cover,
                placeholder: (_, __) => letter(),
                errorWidget: (_, __, ___) => letter(),
              ),
      ),
    );
  }

  Widget _tile(_Item item) => InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          child: Row(children: [
            Icon(item.icon, size: 30, color: Colors.white),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    if (item.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.subtitle!,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54)),
                      ),
                  ]),
            ),
          ]),
        ),
      );
}

class _Item {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  const _Item(this.icon, this.label, this.onTap, {this.subtitle});
}
