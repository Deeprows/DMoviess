import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'app_shell_screen.dart';
import 'auth_screen.dart';

/// Shows the Gmail sign-in screen until the user is signed in, then the app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    unawaited(AuthService.instance.restore());
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
