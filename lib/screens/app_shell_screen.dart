import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/app_remote_config.dart';
import '../services/app_analytics.dart';
import 'community_screen.dart';
import 'movie_home_screen.dart';
import 'library_screen.dart';
import '../services/app_preferences.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});
  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _index = 0;
  static const _kSeenNotice = 'damimovies_seen_notice';
  bool _noticeOpen = false;

  @override
  void initState() {
    super.initState();
    AppAnalytics.instance.screenViewed('movies');
    RemoteConfig.instance.addListener(_checkNotice);
    // The bundled/cached config is already applied; the online copy arrives
    // a moment later and triggers _checkNotice again.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotice());
  }

  @override
  void dispose() {
    RemoteConfig.instance.removeListener(_checkNotice);
    super.dispose();
  }

  /// Shows the "notice" from app_config.json once per notice id.
  Future<void> _checkNotice() async {
    if (_noticeOpen || !mounted) return;
    final notice = RemoteConfig.instance.notice;
    if (!notice.active) return;
    _noticeOpen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kSeenNotice) == notice.id) return;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: notice.dismissible,
        builder: (dialogContext) => PopScope(
          canPop: notice.dismissible,
          child: AlertDialog(
            backgroundColor: appSurface,
            title: Text(notice.title.isEmpty ? 'DamiMovies' : notice.title),
            content: SingleChildScrollView(
                child: Text(notice.message, style: const TextStyle(height: 1.5))),
            actions: [
              if (notice.dismissible || !notice.hasButton)
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('Close'.tr)),
              if (notice.hasButton)
                FilledButton(
                  onPressed: () {
                    unawaited(launchUrl(Uri.parse(notice.buttonUrl),
                        mode: LaunchMode.externalApplication));
                    if (notice.dismissible) Navigator.pop(dialogContext);
                  },
                  child: Text(notice.buttonText),
                ),
            ],
          ),
        ),
      );
      await prefs.setString(_kSeenNotice, notice.id);
    } catch (_) {
    } finally {
      _noticeOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _index, children: [
          const MovieHomeScreen(),
          CommunityScreen(active: _index == 1),
          const LibraryScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          height: 66,
          backgroundColor: appSurface,
          indicatorColor: appRed.withValues(alpha: .18),
          selectedIndex: _index,
          onDestinationSelected: (value) {
            if (value == _index) return;
            setState(() => _index = value);
            const screens = ['movies', 'community', 'library'];
            AppAnalytics.instance.screenViewed(screens[value]);
          },
          destinations: [
            NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie_filter_rounded),
                label: 'Movies'.tr),
            NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum_rounded),
                label: 'Community'.tr),
            NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library_rounded),
                label: 'Library'.tr),
          ],
        ),
      );
}
