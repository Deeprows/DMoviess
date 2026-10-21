#!/usr/bin/env python3
"""Android setup for Firebase push notifications.

Run after `flutter create . --platforms=android` and after the other
tool/patch_*.py scripts (the GitHub workflow does it):

    python3 tool/patch_android_push.py

  * AndroidManifest: default FCM channel / status-bar icon / colour
  * res/drawable/ic_stat_notify.xml and res/values/push_colors.xml
  * MainActivity.kt: creates the "trending" and "news" notification channels
  * android/app minSdk -> 24 (Firebase needs at least 23)

Firebase itself is configured in Dart (lib/services/push_service.dart), so no
google-services.json or Gradle plugin is needed. Safe to run more than once.
"""
import glob
import os
import re
import sys

manifest = "android/app/src/main/AndroidManifest.xml"
res_dir = os.path.join(os.path.dirname(manifest), "res")

# ---- manifest meta-data -------------------------------------------------
s = open(manifest, encoding="utf8").read()
if "default_notification_channel_id" not in s:
    meta = (
        '    <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id"'
        ' android:value="trending"/>\n'
        '        <meta-data android:name="com.google.firebase.messaging.default_notification_icon"'
        ' android:resource="@drawable/ic_stat_notify"/>\n'
        '        <meta-data android:name="com.google.firebase.messaging.default_notification_color"'
        ' android:resource="@color/push_accent"/>\n    '
    )
    s = s.replace("</application>", meta + "</application>", 1)
    open(manifest, "w", encoding="utf8").write(s)
    print("patched", manifest)

# ---- resources ----------------------------------------------------------
os.makedirs(os.path.join(res_dir, "drawable"), exist_ok=True)
os.makedirs(os.path.join(res_dir, "values"), exist_ok=True)
open(os.path.join(res_dir, "drawable", "ic_stat_notify.xml"), "w", encoding="utf8").write(
    '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.63,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z" />
</vector>
''')
open(os.path.join(res_dir, "values", "push_colors.xml"), "w", encoding="utf8").write(
    '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="push_accent">#FFE50914</color>
</resources>
''')
print("wrote push resources in", res_dir)

# ---- notification channels (MainActivity.kt) ----------------------------
matches = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not matches:
    sys.exit("MainActivity.kt not found - run `flutter create . --platforms=android` first")
path = matches[0]
src = open(path, encoding="utf8").read()
if "createPushChannels" not in src:
    for imp in ("android.app.NotificationChannel", "android.app.NotificationManager",
                "android.os.Build", "android.os.Bundle"):
        if f"import {imp}" not in src:
            src = re.sub(r"^(package\s+[\w.]+\s*\n)", rf"\1\nimport {imp}\n", src, count=1, flags=re.M)
    funcs = '''    private fun createPushChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel("trending", "Trending movies", NotificationManager.IMPORTANCE_HIGH)
        )
        nm.createNotificationChannel(
            NotificationChannel("news", "Announcements", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

'''
    if "override fun onCreate" in src:
        src = re.sub(r"(override fun onCreate\([^)]*\)\s*\{\s*\n\s*super\.onCreate\([^)]*\)\s*\n)",
                     r"\1        createPushChannels()\n", src, count=1)
        src = src.replace("    override fun onCreate", funcs + "    override fun onCreate", 1)
    else:
        oncreate = funcs + '''    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createPushChannels()
    }

'''
        if "    override fun configureFlutterEngine" in src:
            src = src.replace("    override fun configureFlutterEngine", oncreate + "    override fun configureFlutterEngine", 1)
        else:  # bare `class MainActivity : FlutterActivity()` with no body
            src = re.sub(r"class MainActivity\s*:\s*FlutterActivity\(\)\s*(\{\s*\})?",
                         "class MainActivity : FlutterActivity() {\n" + oncreate.rstrip() + "\n}", src, count=1)
    if "createPushChannels" not in src:
        sys.exit("Could not add push channels to MainActivity.kt")
    open(path, "w", encoding="utf8").write(src)
    print("patched", path)

# ---- minSdk -------------------------------------------------------------
gradles = glob.glob("android/app/build.gradle*")
if not gradles:
    sys.exit("android/app/build.gradle(.kts) not found")
g = gradles[0]
t = open(g, encoding="utf8").read()
t2 = re.sub(r"(minSdk(?:Version)?\s*=?\s*)flutter\.minSdkVersion", r"\g<1>24", t)
if t2 != t:
    open(g, "w", encoding="utf8").write(t2)
    print("minSdk set to 24 in", g)
else:
    print("minSdk left unchanged in", g)
