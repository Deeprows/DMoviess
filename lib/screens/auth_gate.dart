import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/app_analytics.dart';
import 'app_shell_screen.dart';
import 'auth_screen.dart';

/// Shows the Gmail sign-in screen until the user is signed in, then the app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _wasBackgrounded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Count an app launch even if the visitor has not signed in.
    AppAnalytics.instance.appOpened();
    unawaited(AuthService.instance.restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Count a new visit when the app returns from the background.
    // A normal foreground transition should not count twice.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        AppAnalytics.instance.appOpened();
      }
      // Coming back from the background must never log the user out.
      unawaited(AuthService.instance.recheck());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AuthService.instance,
        builder: (context, _) {
          final auth = AuthService.instance;
          if (!auth.ready) {
            return Scaffold(
              backgroundColor: appBg,
              body: Center(child: CircularProgressIndicator(color: appRed)),
            );
          }
          return auth.signedIn ? const AppShellScreen() : const AuthScreen();
        },
      );
}
