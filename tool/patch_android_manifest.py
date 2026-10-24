#!/usr/bin/env python3
"""Patch Flutter's generated Android manifest for DamiMovies downloads and PiP."""
from pathlib import Path
import re

path = Path('android/app/src/main/AndroidManifest.xml')
s = path.read_text(encoding='utf-8')
if 'xmlns:tools' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
permissions = [
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
    'android.permission.WRITE_EXTERNAL_STORAGE',
]
for permission in permissions:
    if permission not in s:
        max_sdk = ' android:maxSdkVersion="28"' if permission.endswith('WRITE_EXTERNAL_STORAGE') else ''
        insert = f'    <uses-permission android:name="{permission}"{max_sdk}/>'
        s = s.replace('<application', insert + '\n    <application', 1)
if 'android:usesCleartextTraffic' not in s:
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="DamiMovies"', s, count=1)
if 'android:supportsPictureInPicture' not in s:
    s = s.replace('<activity', '<activity android:supportsPictureInPicture="true"', 1)
# flutter_downloader schedules transfers through Android WorkManager.
# Do NOT disable WorkManagerInitializer unless a custom WorkManager
# initializer is also installed. A previous DamiMovies patch removed the
# initializer without replacing it, causing enqueue() to fail on Android.
# `flutter create` regenerates AndroidManifest.xml for every GitHub build.
legacy_provider = re.compile(
    r'<provider\s+android:name="androidx\.startup\.InitializationProvider"'
    r'\s+android:authorities="\$\{applicationId\}\.androidx-startup"'
    r'\s+android:exported="false"\s+tools:node="merge">'
    r'\s*<meta-data\s+android:name="androidx\.work\.WorkManagerInitializer"'
    r'\s+android:value="androidx.startup"\s+tools:node="remove"\s*/>'
    r'\s*</provider>\s*',
    flags=re.MULTILINE,
)
s = legacy_provider.sub('', s)

# Allow flutter_downloader to open completed files from Library or an Android
# download notification. The app-private external download folder is allowed.
if 'vn.hunghd.flutterdownloader.DownloadedFileProvider' not in s:
    download_provider = '''        <provider
            android:name="vn.hunghd.flutterdownloader.DownloadedFileProvider"
            android:authorities="${applicationId}.flutter_downloader.provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/provider_paths" />
        </provider>
'''
    s = s.replace('<activity', download_provider + '        <activity', 1)

# This resource is regenerated because this repo generates its Android
# project during GitHub Actions rather than storing it in Git.
xml_dir = Path('android/app/src/main/res/xml')
xml_dir.mkdir(parents=True, exist_ok=True)
(xml_dir / 'provider_paths.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-files-path name="external_files" path="." />
    <external-path name="external_storage" path="." />
    <files-path name="files" path="." />
    <cache-path name="cache" path="." />
</paths>
''', encoding='utf-8')

path.write_text(s, encoding='utf-8')
print('Patched Android manifest; WorkManager auto-initialization retained, download FileProvider configured.')
