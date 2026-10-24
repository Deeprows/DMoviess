import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/auth_gate.dart';
import 'services/ad_service.dart';
import 'services/app_preferences.dart';
import 'utils/l10n.dart';
import 'services/download_manager.dart';
import 'services/push_service.dart';

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
      [DeviceOrientation.portraitUp],
    ).timeout(const Duration(seconds: 4));
  } catch (error) {
    debugPrint('DamiMovies: orientation setup skipped: $error');
  }

  try {
    await AppPreferences.instance.load().timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint(
        'DamiMovies: preferences could not be loaded at startup: $error');
  }

  try {
    unawaited(PushService.instance.init());
  } catch (error) {
    debugPrint('DamiMovies: push unavailable at startup: $error');
  }

  try {
    unawaited(AdService.instance.start());
  } catch (error) {
    debugPrint('DamiMovies: ads unavailable at startup: $error');
  }

  try {
    await DownloadManager.instance.init().timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('DamiMovies: download service unavailable at startup: $error');
  }
}

/// App-wide look: softer surfaces, rounded shapes, floating snackbars,
/// smooth page transitions and a refined type scale.
ThemeData _buildTheme(DamiPalette palette) {
  final onAccent =
      palette.accent.computeLuminance() > .5 ? Colors.black : Colors.white;
  const hairline = Color(0x1FFFFFFF);
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    splashFactory: InkRipple.splashFactory,
    highlightColor: Colors.transparent,
    colorScheme: ColorScheme.dark(
      primary: palette.accent,
      onPrimary: onAccent,
      secondary: palette.accentSoft,
      surface: palette.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -.3,
        color: Colors.white,
      ),
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
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: hairline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: hairline),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -.3,
        color: Colors.white,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: palette.surface,
      showDragHandle: true,
      dragHandleColor: Colors.white24,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.surface,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: hairline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withValues(alpha: .06),
      selectedColor: palette.accent.withValues(alpha: .22),
      showCheckmark: false,
      side: const BorderSide(color: hairline),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: onAccent,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Color(0x33FFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accentSoft,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: const TextStyle(color: Colors.white54),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0x14FFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
            color: palette.accent.withValues(alpha: .8), width: 1.4),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onAccent : null),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? palette.accent : null),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accent,
      linearTrackColor: Colors.white12,
    ),
    dividerTheme: const DividerThemeData(color: Color(0x14FFFFFF), space: 1),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: palette.deepSurface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
    ),
  );
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
            locale: Locale(AppPreferences.instance.languageCode),
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(palette),
            navigatorKey: AdService.instance.navigatorKey,
            scaffoldMessengerKey: PushService.messengerKey,
            home: const _DamiSplash(),
          );
        },
      );
}

class _DamiSplash extends StatefulWidget {
  const _DamiSplash();

  @override
  State<_DamiSplash> createState() => _DamiSplashState();
}

class _DamiSplashState extends State<_DamiSplash> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      );
      // Cold-start notifications may have been received during the splash.
      // Open their movie only after the app navigator is on the auth/home route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PushService.instance.onNavigationReady();
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF080B10),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Image.asset('assets/splash/splash.png',
                width: 300, height: 300, fit: BoxFit.contain),
          ),
        ),
      );
}
