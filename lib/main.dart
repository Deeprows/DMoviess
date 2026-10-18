import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/app_shell_screen.dart';
import 'services/app_preferences.dart';
import 'services/download_manager.dart';

Color get appBg => AppPreferences.instance.palette.background;
Color get appSurface => AppPreferences.instance.palette.surface;
Color get appRed => AppPreferences.instance.palette.accent;
Color get appAccentSoft => AppPreferences.instance.palette.accentSoft;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  await DownloadManager.instance.init();
  runApp(const DamiMoviesApp());
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
              colorScheme: ColorScheme.dark(primary: palette.accent, surface: palette.surface),
              appBarTheme: AppBarTheme(backgroundColor: palette.background, foregroundColor: Colors.white, elevation: 0),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: palette.deepSurface,
                indicatorColor: palette.accent.withValues(alpha: .18),
                labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                  color: states.contains(WidgetState.selected) ? Colors.white : Colors.white60,
                  fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 11,
                )),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: palette.surface,
                hintStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              switchTheme: SwitchThemeData(
                thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? palette.accent : null),
                trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? palette.accent.withValues(alpha: .35) : null),
              ),
              useMaterial3: true,
            ),
            home: const AppShellScreen(),
          );
        },
      );
}
