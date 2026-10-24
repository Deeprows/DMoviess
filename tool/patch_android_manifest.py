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
if 'WorkManagerInitializer' not in s:
    provider = '''<provider android:name="androidx.startup.InitializationProvider" android:authorities="${applicationId}.androidx-startup" android:exported="false" tools:node="merge">
            <meta-data android:name="androidx.work.WorkManagerInitializer" android:value="androidx.startup" tools:node="remove"/>
        </provider>
        '''
    s = s.replace('<activity', provider + '<activity', 1)
path.write_text(s, encoding='utf-8')
print('Patched Android manifest for internet, downloads and PiP.')
