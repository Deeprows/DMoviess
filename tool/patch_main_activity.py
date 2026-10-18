#!/usr/bin/env python3
"""Expose Android Picture-in-Picture to Flutter's damimovies/pip channel."""
from pathlib import Path
import re
import sys

matches = list(Path('android/app/src/main/kotlin').rglob('MainActivity.kt'))
if not matches:
    sys.exit('MainActivity.kt not found; run flutter create first.')
path = matches[0]
current = path.read_text(encoding='utf-8')
match = re.search(r'^package\s+([\w.]+)', current, re.M)
if not match:
    sys.exit('Could not determine MainActivity Kotlin package.')
pkg = match.group(1)
code = f'''package {pkg}

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "damimovies/pip")
            .setMethodCallHandler {{ call, result ->
                when (call.method) {{
                    "isAvailable" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    )
                    "enter" -> {{
                        var ok = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {{
                            try {{
                                ok = enterPictureInPictureMode(
                                    PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
                                )
                            }} catch (_: Exception) {{ ok = false }}
                        }}
                        result.success(ok)
                    }}
                    else -> result.notImplemented()
                }}
            }}
    }}
}}
'''
path.write_text(code, encoding='utf-8')
print('Patched MainActivity with DamiMovies PiP channel.')
