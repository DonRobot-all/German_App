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
    # В релизной сборке Flutter интернет по умолчанию не разрешает; без него
    # не работает проверка обновлений.
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    # Точное время уведомлений (пользователь разрешает в настройках Android).
    'android.permission.SCHEDULE_EXACT_ALARM',
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
        # В шаблоне нет блока compileOptions: создаём его внутри android { ... }.
        block = ('compileOptions {\n        %s\n    }' % flag)
        t, n = re.subn(
            r'android\s*\{',
            lambda m: m.group(0) + '\n    ' + block,
            t,
            count=1,
        )
    if n == 0:
        sys.exit('%s: не найден блок android { ... }' % path)

    if is_kts:
        dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:%s")' % DESUGAR_VERSION
    else:
        dep = "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:%s'" % DESUGAR_VERSION
    t = t.rstrip('\n') + '\n\ndependencies {\n    %s\n}\n' % dep

    with open(path, 'w', encoding='utf-8') as f:
        f.write(t)
    print('%s: desugaring включён' % path)


KEYSTORE = 'signing/release.jks'
KEY_ALIAS = 'germanwords'
# Пароль в репозитории не хранится: CI передаёт его из GitHub Secrets.
PASSWORD_ENV = 'KEYSTORE_PASSWORD'


def patch_signing(candidates=GRADLE_FILES, keystore=KEYSTORE):
    """Подписывает релиз постоянным ключом из репозитория.

    Без этого каждая сборка в CI получает новый случайный debug-ключ, и Android
    не позволяет установить новую версию поверх старой.
    """
    if not os.path.exists(keystore) or not os.environ.get(PASSWORD_ENV):
        print('ВНИМАНИЕ: нет ключа подписи (файл %s и переменная %s, их задают '
              'секреты GitHub). Сборка будет подписана случайным debug-ключом, '
              'обновление поверх старой версии не сработает.'
              % (keystore, PASSWORD_ENV))
        return
    path = next((p for p in candidates if os.path.exists(p)), None)
    if path is None:
        sys.exit('build.gradle(.kts) приложения не найден')
    with open(path, encoding='utf-8') as f:
        t = f.read()
    if 'signing/release.jks' in t:
        print('%s: подпись уже настроена' % path)
        return

    is_kts = path.endswith('.kts')
    store = '../../' + keystore  # путь от папки android/app
    if is_kts:
        block = (
            '    signingConfigs {\n'
            '        create("release") {\n'
            '            storeFile = file("%s")\n'
            '            storePassword = System.getenv("%s")\n'
            '            keyAlias = "%s"\n'
            '            keyPassword = System.getenv("%s")\n'
            '        }\n'
            '    }\n\n' % (store, PASSWORD_ENV, KEY_ALIAS, PASSWORD_ENV))
    else:
        block = (
            '    signingConfigs {\n'
            '        release {\n'
            "            storeFile file('%s')\n"
            "            storePassword System.getenv('%s')\n"
            "            keyAlias '%s'\n"
            "            keyPassword System.getenv('%s')\n"
            '        }\n'
            '    }\n\n' % (store, PASSWORD_ENV, KEY_ALIAS, PASSWORD_ENV))

    t, n = re.subn(
        r'([ \t]*)buildTypes\s*\{',
        lambda m: block + m.group(0),
        t,
        count=1,
    )
    if n == 0:
        sys.exit('%s: не найден блок buildTypes { ... }' % path)

    if is_kts:
        t, n = re.subn(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = signingConfigs.getByName("release")',
            t,
        )
        line = 'signingConfig = signingConfigs.getByName("release")'
    else:
        t, n = re.subn(
            r'signingConfig\s+signingConfigs\.debug',
            'signingConfig signingConfigs.release',
            t,
        )
        line = 'signingConfig signingConfigs.release'
    if n == 0:
        # В шаблоне нет строки с debug-подписью: добавляем в release { ... }.
        t, n = re.subn(
            r'(buildTypes\s*\{\s*(?:getByName\("release"\)|release)\s*\{)',
            lambda m: m.group(1) + '\n            ' + line,
            t,
            count=1,
        )
    if n == 0:
        sys.exit('%s: не найден блок release { ... } в buildTypes' % path)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(t)
    print('%s: релиз подписывается ключом %s' % (path, keystore))


ROOT_GRADLE_FILES = ('android/build.gradle.kts', 'android/build.gradle')
COMPILE_SDK = 36
COMPILE_SDK_MARK = 'german_words: compileSdk'

KTS_COMPILE_SDK = """// german_words: compileSdk. Некоторые плагины собраны с более старым Android API,
// чем требуют их зависимости. Поднимаем версию для компиляции у всех модулей.
subprojects {
    val bumpCompileSdk = { p: Project ->
        val ext = p.extensions.findByName("android")
        if (ext != null) {
            try {
                ext.withGroovyBuilder { "compileSdkVersion"(%(sdk)d) }
            } catch (e: Exception) {
            }
        }
    }
    if (state.executed) bumpCompileSdk(this) else afterEvaluate { bumpCompileSdk(this) }
}

"""

GROOVY_COMPILE_SDK = """// german_words: compileSdk. Некоторые плагины собраны с более старым Android API,
// чем требуют их зависимости. Поднимаем версию для компиляции у всех модулей.
subprojects { sp ->
    def bump = { Project p ->
        if (p.hasProperty('android')) {
            try {
                p.android { compileSdkVersion %(sdk)d }
            } catch (Exception e) {
            }
        }
    }
    if (sp.state.executed) {
        bump(sp)
    } else {
        sp.afterEvaluate { bump(sp) }
    }
}

"""


def patch_compile_sdk(candidates=ROOT_GRADLE_FILES, sdk=COMPILE_SDK):
    """Поднимает compileSdk у плагинов (иначе, например, file_picker не собирается)."""
    path = next((p for p in candidates if os.path.exists(p)), None)
    if path is None:
        print('Корневой build.gradle не найден, compileSdk не меняю')
        return
    with open(path, encoding='utf-8') as f:
        t = f.read()
    if COMPILE_SDK_MARK in t:
        print('%s: compileSdk уже поднят' % path)
        return
    block = (KTS_COMPILE_SDK if path.endswith('.kts') else GROOVY_COMPILE_SDK) % {'sdk': sdk}
    # Блок должен стоять до evaluationDependsOn(":app"), иначе :app вычислится раньше.
    m = re.search(r'^[ \t]*subprojects\s*\{', t, re.M)
    if m:
        t = t[:m.start()] + block + t[m.start():]
    else:
        t = t.rstrip('\n') + '\n\n' + block
    with open(path, 'w', encoding='utf-8') as f:
        f.write(t)
    print('%s: compileSdk поднят до %d' % (path, sdk))


if __name__ == '__main__':
    patch_manifest()
    patch_gradle()
    patch_signing()
    patch_compile_sdk()
