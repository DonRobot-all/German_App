import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Репозиторий, в Releases которого CI выкладывает свежий APK.
const String kRepo = 'DonRobot-all/German_App';

/// Номер сборки этого приложения. CI подставляет его при сборке
/// (`--dart-define=BUILD_NUMBER=...`); при локальном запуске равен 0.
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

class UpdateInfo {
  const UpdateInfo(this.build, this.url);

  /// Номер новой сборки.
  final int build;

  /// Прямая ссылка на APK.
  final String url;
}

enum UpdateStatus { available, upToDate, unknown }

class UpdateResult {
  const UpdateResult(this.status, {this.info, this.message});

  final UpdateStatus status;
  final UpdateInfo? info;
  final String? message;
}

/// Спрашивает у GitHub последний релиз и сравнивает его номер с текущим.
/// Никогда не бросает исключений: при любой проблеме вернёт `unknown`.
Future<UpdateResult> checkForUpdate() async {
  if (kBuildNumber <= 0) {
    return const UpdateResult(
      UpdateStatus.unknown,
      message: 'Версия без номера сборки (не из GitHub Actions).',
    );
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client
        .getUrl(Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'))
        .timeout(const Duration(seconds: 10));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'german-words-app');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return UpdateResult(
        UpdateStatus.unknown,
        message: res.statusCode == 404
            ? 'Релизы не найдены (репозиторий должен быть публичным).'
            : 'GitHub ответил кодом ${res.statusCode}.',
      );
    }
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    final m = RegExp(r'(\d+)$').firstMatch(tag);
    if (m == null) {
      return const UpdateResult(
        UpdateStatus.unknown,
        message: 'Не удалось определить номер версии.',
      );
    }
    final latest = int.parse(m.group(1)!);
    if (latest <= kBuildNumber) {
      return const UpdateResult(UpdateStatus.upToDate);
    }
    String? url;
    for (final a in (json['assets'] as List<dynamic>? ?? const [])) {
      final map = a as Map<String, dynamic>;
      final name = (map['name'] as String?) ?? '';
      if (name.endsWith('.apk')) {
        url = map['browser_download_url'] as String?;
        break;
      }
    }
    if (url == null) {
      return const UpdateResult(
        UpdateStatus.unknown,
        message: 'В релизе нет файла APK.',
      );
    }
    return UpdateResult(UpdateStatus.available, info: UpdateInfo(latest, url));
  } on TimeoutException {
    return const UpdateResult(UpdateStatus.unknown, message: 'Нет связи с GitHub.');
  } catch (_) {
    return const UpdateResult(
      UpdateStatus.unknown,
      message: 'Не удалось проверить обновления.',
    );
  } finally {
    client.close(force: true);
  }
}

/// Открывает загрузку APK. Дальше Android сам предложит установить файл.
Future<bool> openDownload(UpdateInfo info) async {
  try {
    return await launchUrl(
      Uri.parse(info.url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
