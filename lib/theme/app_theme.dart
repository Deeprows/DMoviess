import 'package:flutter/material.dart';

import '../services/app_preferences.dart';

/// Colours for the community and Watch Together screens. They follow the
/// theme the person picked in Settings, so they change with it.
class UiPalette {
  final DamiPalette _p;
  const UiPalette(this._p);

  /// Readable text/icon colour on top of the accent colour.
  Color get onAccent =>
      _p.accent.computeLuminance() > .5 ? Colors.black : Colors.white;
}

class Ui {
  Ui._();

  static DamiPalette get _p => AppPreferences.instance.palette;

  static UiPalette get palette => UiPalette(_p);

  static Color get bg => _p.background;
  static Color get card => _p.surface;
  static Color get cardDeep => _p.deepSurface;
  static Color get panel => _p.deepSurface;
  static Color get red => _p.accent;
  static Color get redSoft => _p.accentSoft;
  static Color get glassLine => Colors.white.withValues(alpha: .10);
  static Color get muted => Colors.white60;
  static Color get dim => Colors.white38;

  static Gradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_p.accent, _p.accentSoft],
      );
}
