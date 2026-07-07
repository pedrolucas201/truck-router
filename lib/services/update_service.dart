import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Checagem de atualização in-app. A "fonte da verdade" é um version.json público
/// no mesmo bucket GCS das APKs, escrito pelo release.ps1 a cada release. Sem
/// Play Store, então o update é sideload: baixa a APK e dispara o instalador
/// (ver UpdateDialog + ota_update).
class UpdateInfo {
  final int build;
  final String version;
  final String url;
  final bool force;
  final String notes;
  const UpdateInfo({
    required this.build,
    required this.version,
    required this.url,
    required this.force,
    required this.notes,
  });
}

class UpdateService {
  static const _versionUrl =
      'https://storage.googleapis.com/truck-router-apks/version.json';

  /// Retorna UpdateInfo se há build MAIOR que o instalado; null caso contrário
  /// (inclusive offline / erro de rede / json malformado — nunca lança, nunca
  /// vaza erro pro usuário; sem update é indistinguível de sem internet).
  static Future<UpdateInfo?> check() async {
    try {
      final res = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final latest = (j['build'] as num?)?.toInt();
      if (latest == null) return null;
      final minBuild = (j['minBuild'] as num?)?.toInt() ?? 0;

      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      if (latest <= current) return null;

      return UpdateInfo(
        build: latest,
        version: (j['version'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
        force: current < minBuild,
        notes: (j['notes'] as String?) ?? '',
      );
    } catch (_) {
      return null; // ponytail: falha silenciosa é o comportamento correto aqui
    }
  }
}
