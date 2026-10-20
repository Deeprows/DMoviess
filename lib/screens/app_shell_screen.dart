import 'package:flutter/material.dart';
import '../main.dart';
import 'community_screen.dart';
import 'movie_home_screen.dart';
import 'library_screen.dart';
import 'community_profile_screen.dart';
import '../services/auth_service.dart';
import '../services/app_preferences.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});
  @override State<AppShellScreen> createState() => _AppShellScreenState();
}
class _AppShellScreenState extends State<AppShellScreen> {
  int _index = 0;

  @override Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: [
      const MovieHomeScreen(),
      CommunityScreen(active: _index == 1),
      const LibraryScreen(),
      CommunityProfileScreen(
        asTab: true,
        active: _index == 3,
        email: AuthService.instance.user?.email ?? '',
        name: AuthService.instance.user?.name,
        photoUrl: AuthService.instance.user?.photoUrl,
      ),
    ]),
    bottomNavigationBar: NavigationBar(
      height: 66,
      backgroundColor: appSurface,
      indicatorColor: appRed.withValues(alpha: .18),
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.movie_outlined), selectedIcon: const Icon(Icons.movie_filter_rounded), label: 'Movies'.tr),
        NavigationDestination(icon: const Icon(Icons.forum_outlined), selectedIcon: const Icon(Icons.forum_rounded), label: 'Community'.tr),
        NavigationDestination(icon: const Icon(Icons.video_library_outlined), selectedIcon: const Icon(Icons.video_library_rounded), label: 'Library'.tr),
        NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: 'Profile'.tr),
      ],
    ),
  );
}
