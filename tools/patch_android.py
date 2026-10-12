#!/usr/bin/env python3
"""Дописывает в сгенерированный `flutter create` Android-проект то, что нужно
плагинам приложения (озвучка и напоминания). Безопасно запускать повторно.

Запуск из корня проекта:  python3 tools/patch_android.py
"""
import os
import re
import sys

MANIFEST = 'android/app/src/main/AndroidManifest.xml'
GRADLE_FILES = ('android/app/build.gradle.kts', 'android/app/build.gradle')
DESUGAR_VERSION = '2.1.4'

TTS_QUERIES = (
    '<queries><intent>'
    '<action android:name="android.intent.action.TTS_SERVICE"/>'
    '</intent></queries>'
)

PERMISSIONS = (
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
)

RECEIVERS = (
    '<receiver android:exported="false" '
    'android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />'
    '<receiver android:exported="false" '
    'android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">'
    '<intent-filter>'
    '<action android:name="android.intent.action.BOOT_COMPLETED"/>'
    '<action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>'
    '<action android:name="android.intent.action.QUICKBOOT_POWERON" />'
    '<action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>'
    '</intent-filter>'
    '</receiver>'
)


def patch_manifest(path=MANIFEST):
    with open(path, encoding='utf-8') as f:
        s = f.read()
    original = s

    before_app = ''
    if 'android.intent.action.TTS_SERVICE' not in s:
        before_app += TTS_QUERIES + '\n    '
    for perm in PERMISSIONS:
        if perm not in s:
            before_app += '<uses-permission android:name="%s"/>\n    ' % perm
    if before_app:
        if '<application' not in s:
            sys.exit('AndroidManifest: тег <application> не найден')
        s = s.replace('<application', before_app + '<application', 1)

    if 'ScheduledNotificationReceiver' not in s:
        if '</application>' not in s:
            sys.exit('AndroidManifest: тег </application> не найден')
        s = s.replace('</application>', RECEIVERS + '\n    </application>', 1)

    if s != original:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(s)
        print('AndroidManifest: обновлён')
    else:
        print('AndroidManifest: уже в порядке')


def patch_gradle(candidates=GRADLE_FILES):
    path = next((p for p in candidates if os.path.exists(p)), None)
    if path is None:
        sys.exit('build.gradle(.kts) приложения не найден')
    with open(path, encoding='utf-8') as f:
        t = f.read()
    if 'desugar_jdk_libs' in t:
        print('%s: desugaring уже включён' % path)
        return

    is_kts = path.endswith('.kts')
    flag = ('isCoreLibraryDesugaringEnabled = true' if is_kts
            else 'coreLibraryDesugaringEnabled true')
    t, n = re.subn(
        r'compileOptions\s*\{',
        lambda m: m.group(0) + '\n        ' + flag,
        t,
        count=1,
    )
    if n == 0:
        sys.exit('%s: блок compileOptions не найден' % path)

    if is_kts:
        dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:%s")' % DESUGAR_VERSION
    else:
        dep = "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:%s'" % DESUGAR_VERSION
    t = t.rstrip('\n') + '\n\ndependencies {\n    %s\n}\n' % dep

    with open(path, 'w', encoding='utf-8') as f:
        f.write(t)
    print('%s: desugaring включён' % path)


if __name__ == '__main__':
    patch_manifest()
    patch_gradle()
