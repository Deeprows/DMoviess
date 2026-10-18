import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/app_shell_screen.dart';
import 'services/app_preferences.dart';
import 'services/download_manager.dart';

Color get appBg => AppPreferences.instance.palette.background;
Color get appSurface => AppPreferences.instance.palette.surface;
Color get appRed => AppPreferences.instance.palette.accent;
Color get appAccentSoft => AppPreferences.instance.palette.accentSoft;

/// Start Flutter's first frame before waiting for plugins or persistent storage.
/// Android keeps its native splash visible until Flutter renders that frame, so
/// no non-essential plugin initialization belongs before runApp().
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DamiMoviesApp());
  unawaited(_initializeServices());
}

Future<void> _initializeServices() async {
  // These are best-effort startup tasks. A plugin that is slow or unavailable
  // must never hold the user on the native launch screen.
  try {
    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    ).timeout(const Duration(seconds: 4));
  } catch (error) {
    debugPrint('DamiMovies: orientation setup skipped: $error');
  }

  try {
    await AppPreferences.instance
        .load()
        .timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('DamiMovies: preferences could not be loaded at startup: $error');
  }

  try {
    await DownloadManager.instance
        .init()
        .timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('DamiMovies: download service unavailable at startup: $error');
  }
}

class DamiMoviesApp extends StatelessWidget {
  const DamiMoviesApp({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppPreferences.instance,
        builder: (context, _) {
          final palette = AppPreferences.instance.palette;
          return MaterialApp(
            title: 'DamiMovies',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: palette.background,
              colorScheme: ColorScheme.dark(
                primary: palette.accent,
                surface: palette.surface,
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: palette.background,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: palette.deepSurface,
                indicatorColor: palette.accent.withValues(alpha: .18),
                labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                  color: states.contains(WidgetState.selected)
                      ? Colors.white
                      : Colors.white60,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w800
                      : FontWeight.w500,
                  fontSize: 11,
                )),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: palette.surface,
                hintStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              switchTheme: SwitchThemeData(
                thumbColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? palette.accent
                        : null),
                trackColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? palette.accent.withValues(alpha: .35)
                        : null),
              ),
              useMaterial3: true,
            ),
            home: const AppShellScreen(),
          );
        },
      );
}
