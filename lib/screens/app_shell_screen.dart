import 'package:flutter/material.dart';
import '../main.dart';
import 'movie_home_screen.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import '../services/app_preferences.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});
  @override State<AppShellScreen> createState() => _AppShellScreenState();
}
class _AppShellScreenState extends State<AppShellScreen> {
  int _index = 0;

  @override Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: const [
      MovieHomeScreen(),
      BrowserScreen(),
      DownloadsScreen(),
      LibraryScreen(),
    ]),
    bottomNavigationBar: NavigationBar(
      height: 66,
      backgroundColor: appSurface,
      indicatorColor: appRed.withValues(alpha: .18),
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.movie_outlined), selectedIcon: const Icon(Icons.movie_filter_rounded), label: 'Movies'.tr),
        NavigationDestination(icon: const Icon(Icons.language_rounded), selectedIcon: const Icon(Icons.travel_explore_rounded), label: 'Browser'.tr),
        NavigationDestination(icon: const Icon(Icons.download_outlined), selectedIcon: const Icon(Icons.download_rounded), label: 'Downloads'.tr),
        NavigationDestination(icon: const Icon(Icons.video_library_outlined), selectedIcon: const Icon(Icons.video_library_rounded), label: 'Library'.tr),
      ],
    ),
  );
}
