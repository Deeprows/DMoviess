#!/usr/bin/env python3
"""Sign the release APK with your own keystore when RELEASE_KEYSTORE_PATH is set.

Falls back to Flutter's default (debug) signing when the variable is empty, so
builds still work before the keystore secrets are added.
"""
from pathlib import Path
import re

kts = Path('android/app/build.gradle.kts')
groovy = Path('android/app/build.gradle')

if kts.exists():
    path, s = kts, kts.read_text(encoding='utf-8')
    if 'RELEASE_KEYSTORE_PATH' not in s:
        block = '''    signingConfigs {
        create("release") {
            val ksPath = System.getenv("RELEASE_KEYSTORE_PATH")
            if (!ksPath.isNullOrEmpty()) {
                storeFile = file(ksPath)
                storePassword = System.getenv("RELEASE_STORE_PASSWORD")
                keyAlias = System.getenv("RELEASE_KEY_ALIAS")
                keyPassword = System.getenv("RELEASE_KEY_PASSWORD")
            }
        }
    }

'''
        s = s.replace('    buildTypes {', block + '    buildTypes {', 1)
        s, n = re.subn(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = if (System.getenv("RELEASE_KEYSTORE_PATH").isNullOrEmpty()) '
            'signingConfigs.getByName("debug") else signingConfigs.getByName("release")',
            s, count=1)
        if n == 0 or 'create("release")' not in s:
            raise SystemExit('Could not patch build.gradle.kts for release signing')
elif groovy.exists():
    path, s = groovy, groovy.read_text(encoding='utf-8')
    if 'RELEASE_KEYSTORE_PATH' not in s:
        block = '''    signingConfigs {
        release {
            def ksPath = System.getenv("RELEASE_KEYSTORE_PATH")
            if (ksPath) {
                storeFile file(ksPath)
                storePassword System.getenv("RELEASE_STORE_PASSWORD")
                keyAlias System.getenv("RELEASE_KEY_ALIAS")
                keyPassword System.getenv("RELEASE_KEY_PASSWORD")
            }
        }
    }

'''
        s = s.replace('    buildTypes {', block + '    buildTypes {', 1)
        s, n = re.subn(
            r'signingConfig\s+signingConfigs\.debug',
            'signingConfig System.getenv("RELEASE_KEYSTORE_PATH") ? signingConfigs.release : signingConfigs.debug',
            s, count=1)
        if n == 0 or 'signingConfigs {' not in s:
            raise SystemExit('Could not patch build.gradle for release signing')
else:
    raise SystemExit('No android/app/build.gradle(.kts) found; run flutter create first')

path.write_text(s, encoding='utf-8')
print(f'Patched {path} for release signing.')
