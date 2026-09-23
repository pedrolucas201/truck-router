import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'field_log.dart';

/// Atualização in-app (voltou em 15/09/2026 a pedido do Beto: "os caras não vão
/// ficar parando pra atualizar"). Fora da Play Store nada se instala sozinho —
/// o Android sempre exige o toque em "Instalar" — então o que dá pra fazer é
/// encurtar o resto: placa na abertura, o que mudou, um toque baixa, o
/// instalador abre. Fonte da verdade = `version.json` público no bucket das
/// APKs, escrito pelo release.ps1 a cada release (com sha256 da APK).
///
/// Saiu em 08/07 (`0eaecce`) enquanto se decidia App Distribution vs Play; a
/// Play ficou inviável e o App Distribution não instala nada — só avisa.
class UpdateInfo {
  final int build;
  final String version;
  final String url;
  final String sha256; // vazio = sem conferência (json antigo)
  final bool force;
  final String notes;
  const UpdateInfo({
    required this.build,
    required this.version,
    required this.url,
    required this.sha256,
    required this.force,
    required this.notes,
  });
}

/// Build instalado, lido do APP_VERSION ("2.4.68+155" → 155). `flutter run`
/// carimba 'dev' → null → nunca oferece update num build de desenvolvimento.
int? currentBuild([String appVersion = FieldLog.appVersion]) {
  final i = appVersion.indexOf('+');
  return i < 0 ? null : int.tryParse(appVersion.substring(i + 1));
}

/// Pura, pra teste: devolve o update se o json aponta build MAIOR que o
/// instalado; null pra igual/menor, json torto ou build desconhecido.
UpdateInfo? parseUpdate(Map<String, dynamic> j, int? installed) {
  if (installed == null) return null;
  int? num_(String k) { final v = j[k]; return v is num ? v.toInt() : null; }
  String str(String k) { final v = j[k]; return v is String ? v : ''; }
  final latest = num_('build');
  final url = str('url');
  if (latest == null || latest <= installed || url.isEmpty) return null;
  return UpdateInfo(
    build: latest,
    version: str('version'),
    url: url,
    sha256: str('sha256'),
    force: installed < (num_('minBuild') ?? 0),
    notes: str('notes'),
  );
}

class UpdateService {
  UpdateService._();

  static const _versionUrl =
      'https://storage.googleapis.com/truck-router-apks/version.json';

  /// Nunca lança e nunca vaza erro: sem update, offline e json malformado são
  /// indistinguíveis pro motorista (nada aparece).
  static Future<UpdateInfo?> check() async {
    try {
      final res = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return parseUpdate(jsonDecode(res.body) as Map<String, dynamic>, currentBuild());
    } catch (_) {
      return null;
    }
  }

  /// O `ota_update` baixa em `files/ota_update/` e nunca apaga depois de
  /// instalar: 66 MB esquecidos no celular, e o Auto Backup (teto de 25 MB por
  /// app) falhava inteiro por causa deles — medido em 23/09/2026 no aparelho do
  /// Pedro (`bmgr backupnow` → "Size quota exceeded").
  ///
  /// Não dá pra apagar sempre: o plugin instala por ACTION_INSTALL_PACKAGE e o
  /// instalador do sistema lê o arquivo NA HORA do toque em "Instalar"; com o
  /// diálogo pendente, apagar quebraria a instalação.
  @visibleForTesting
  static bool apkJaInstalado(DateTime baixado, DateTime? instalado) =>
      instalado != null && baixado.isBefore(instalado);

  /// Nunca lança e nunca segura o boot. Chamar depois do sign-in (FieldLog).
  static Future<void> limparApkInstalado() async {
    if (!Platform.isAndroid) return;
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/ota_update');
      if (!dir.existsSync()) return;
      final instalado = (await PackageInfo.fromPlatform()).updateTime;
      var bytes = 0;
      for (final f in dir.listSync().whereType<File>()) {
        final st = f.statSync();
        if (!apkJaInstalado(st.modified, instalado)) continue;
        f.deleteSync();
        bytes += st.size;
      }
      if (bytes > 0) {
        FieldLog.event('ota_limpo', {'mb': (bytes / 1e6).round()});
      }
    } catch (_) {}
  }
}
