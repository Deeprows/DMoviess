#!/usr/bin/env python3
"""Safely patch the generated DamiMovies Android manifest.

Keep WorkManager's *default* AndroidX Startup initializer intact. DamiMovies
uses flutter_downloader, and its enqueue() returns null when WorkManager is
not initialized. Do not install a second custom WorkManager/FileProvider here;
that previously introduced a startup regression in this application.

Called by .github/workflows/build.yml after flutter create.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

path = Path('android/app/src/main/AndroidManifest.xml')
s = path.read_text(encoding='utf-8')

if 'xmlns:tools=' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

permissions = [
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
    'android.permission.WRITE_EXTERNAL_STORAGE',
]
for permission in permissions:
    if f'android:name="{permission}"' not in s:
        max_sdk = ' android:maxSdkVersion="28"' if permission.endswith('WRITE_EXTERNAL_STORAGE') else ''
        entry = f'    <uses-permission android:name="{permission}"{max_sdk}/>'
        s = s.replace('<application', entry + '\n    <application', 1)

if 'android:usesCleartextTraffic' not in s:
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="DamiMovies"', s, count=1)
if 'android:supportsPictureInPicture' not in s:
    s = s.replace('<activity', '<activity android:supportsPictureInPicture="true"', 1)

# The PREVIOUS manifest patch disabled the WorkManagerInitializer and never
# declared FlutterDownloaderInitializer. Because AndroidX Startup could no
# longer create WorkManager, the download plugin returned no task id. Remove
# only this legacy block: preserve other providers from other plugins.
legacy_block = re.compile(
    r'<provider\b(?=[^>]*android:name=["\']androidx\.startup\.InitializationProvider["\'])'
    r'[^>]*>\s*'
    r'<meta-data\b(?=[^>]*android:name=["\']androidx\.work\.WorkManagerInitializer["\'])'
    r'[^>]*/>\s*</provider>\s*',
    flags=re.DOTALL,
)
s = legacy_block.sub('', s)

# Defensive: reject a still-broken local manifest instead of silently
# generating an APK with broken downloads. Do not touch plugin library manifests.
if re.search(
    r'<meta-data\b(?=[^>]*android:name=["\']androidx\.work\.WorkManagerInitializer["\'])'
    r'(?=[^>]*tools:node=["\']remove["\'])',
    s,
):
    raise SystemExit('ERROR: App manifest still disables WorkManagerInitializer without a replacement.')

try:
    ET.fromstring(s)
except ET.ParseError as exc:
    raise SystemExit(f'ERROR: Android manifest is invalid XML: {exc}') from exc

path.write_text(s, encoding='utf-8')
print('DamiMovies Android manifest patched. WorkManager default startup is enabled; no extra providers added.')
