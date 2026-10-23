import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/app_remote_config.dart';
import '../services/app_analytics.dart';
import '../services/auth_service.dart';
import '../services/telegram_popup_service.dart';
import '../widgets/telegram_promo_dialog.dart';
import 'community_screen.dart';
import 'movie_home_screen.dart';
import 'tv_shows_screen.dart';
import 'library_screen.dart';
import '../services/app_preferences.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});
  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _index = 0;
  bool _tvVisited = false;
  static const _kSeenNotice = 'damimovies_seen_notice';
  bool _noticeOpen = false;
  bool _welcomeOpen = false;
  bool _telegramChecking = false;
  bool _telegramShownThisSession = false;
  bool _telegramDialogOpen = false;
  bool _noticeCheckPending = false;

  @override
  void initState() {
    super.initState();
    AppAnalytics.instance.screenViewed('movies');
    RemoteConfig.instance.addListener(_checkNotice);
    // Show the guide only to accounts newly registered on this device.
    // Check other app announcements only after the welcome card closes,
    // so two dialogs never compete for the user's attention.
    _welcomeOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showWelcomeGuideIfNeeded());
    });
  }

  @override
  void dispose() {
    RemoteConfig.instance.removeListener(_checkNotice);
    super.dispose();
  }

  /// Show only after confirmed signup, until this Gmail account taps Got it.
  Future<void> _showWelcomeGuideIfNeeded() async {
    try {
      if (!await AuthService.instance.shouldShowWelcomeGuide() || !mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: appSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: appRed, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Welcome to DamiMovies',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  _welcomeTip(
                    Icons.movie_creation_outlined,
                    'Watch & download',
                    'Explore the latest movies and download your favorites.',
                  ),
                  const SizedBox(height: 13),
                  _welcomeTip(
                    Icons.groups_2_outlined,
                    'Community',
                    'Join discussions respectfully. Posts are moderated.',
                  ),
                  const SizedBox(height: 13),
                  _welcomeTip(
                    Icons.switch_video_outlined,
                    'Player not working?',
                    'Try another player or server if one fails to load.',
                  ),
                  const SizedBox(height: 19),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: appRed,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final saved = await AuthService.instance.dismissWelcomeGuide();
                        if (!dialogContext.mounted) return;
                        if (saved) {
                          Navigator.of(dialogContext).pop();
                        } else {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text(
                              'Could not save your preference. Please try again.',
                            )),
                          );
                        }
                      },
                      child: const Text('Got it',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      debugPrint('DamiMovies: welcome guide skipped: $error');
    } finally {
      _welcomeOpen = false;
      if (mounted) unawaited(_checkNotice());
    }
  }

  Widget _welcomeTip(IconData icon, String title, String message) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: appRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(message,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      );

  /// Shows the "notice" from app_config.json once per notice id.
  Future<void> _checkNotice() async {
    if (_telegramDialogOpen) {
      _noticeCheckPending = true;
      return;
    }
    if (_noticeOpen || _welcomeOpen || !mounted) return;
    final notice = RemoteConfig.instance.notice;
    if (!notice.active) {
      unawaited(_maybeShowTelegramPromo());
      return;
    }
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
      if (mounted) unawaited(_maybeShowTelegramPromo());
    }
  }

  /// Show the Telegram campaign after the signup guide and app notice.
  /// No popup races, and users see each campaign only at the JSON frequency.
  Future<void> _maybeShowTelegramPromo() async {
    if (!mounted || _welcomeOpen || _noticeOpen ||
        _telegramChecking || _telegramShownThisSession) return;
    _telegramChecking = true;
    try {
      final config = await TelegramPopupService.load();
      if (config == null || !await TelegramPopupService.shouldShow(config)) {
        return;
      }
      if (config.delaySeconds > 0) {
        await Future<void>.delayed(Duration(seconds: config.delaySeconds));
      }
      if (!mounted || _welcomeOpen || _noticeOpen) return;
      _telegramShownThisSession = true;
      _telegramDialogOpen = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (_) => TelegramPromoDialog(config: config),
      );
      await TelegramPopupService.markSeen(config);
    } catch (error) {
      debugPrint('DamiMovies: Telegram promo skipped: $error');
    } finally {
      _telegramDialogOpen = false;
      _telegramChecking = false;
      if (mounted && _noticeCheckPending) {
        _noticeCheckPending = false;
        unawaited(_checkNotice());
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _index, children: [
          const MovieHomeScreen(),
          _tvVisited ? const TvShowsScreen() : const SizedBox.shrink(),
          CommunityScreen(active: _index == 2),
          const LibraryScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          height: 66,
          backgroundColor: appSurface,
          indicatorColor: appRed.withValues(alpha: .18),
          selectedIndex: _index,
          onDestinationSelected: (value) {
            if (value == _index) return;
            setState(() {
              _index = value;
              if (value == 1) _tvVisited = true;
            });
            const screens = ['movies', 'tv_shows', 'community', 'library'];
            AppAnalytics.instance.screenViewed(screens[value]);
          },
          destinations: [
            NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie_filter_rounded),
                label: 'Movies'.tr),
            NavigationDestination(
                icon: Icon(Icons.live_tv_outlined),
                selectedIcon: Icon(Icons.live_tv_rounded),
                label: 'TV Shows'.tr),
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
