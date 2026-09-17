import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Telemetria de campo do caminho crítico de navegação (reroute, off-route,
/// chegada). Existe porque o motorista (Gilberto) não consegue capturar logcat
/// dirigindo — quando o app congela, o print dele é o único sinal, e some.
///
/// Dois destinos complementares, ambos best-effort e silenciosos (nunca lançam,
/// nunca vazam pro usuário — princípio do Márcio):
///  - **Crashlytics.log**: vira breadcrumb anexado ao trace de um ANR/crash
///    subsequente. Se o app travar logo depois, vemos a sequência que levou nele.
///  - **Firestore** (`field_logs`): escrito ANTES do travamento, então sobrevive
///    ao freeze e fica consultável ao vivo, sem depender do device do motorista.
class FieldLog {
  FieldLog._();

  /// Identifica esta execução do app (≈ um drive). Gerado uma vez por processo,
  /// pra agrupar todos os breadcrumbs de uma mesma sessão no Firestore.
  static final String sessionId = _genSession();

  /// Versão do app que emitiu o evento. Injetada pelo `release.ps1`
  /// (`--dart-define=APP_VERSION=...`, lido do pubspec); 'dev' num `flutter run`.
  ///
  /// Sem isto, descobrir QUAL build gerou um log só dava por engenharia reversa nos
  /// eventos ("esta versão emite reroute_enrich, aquela não") — feito 2x em
  /// 2026-07-13, e errado uma delas: com o Pedro e o Gilberto dirigindo builds
  /// diferentes ao mesmo tempo, os logs de um viravam evidência sobre o outro.
  static const String appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  static CollectionReference<Map<String, dynamic>>? _col;
  static CollectionReference<Map<String, dynamic>> get _collection =>
      _col ??= FirebaseFirestore.instance.collection('field_logs');

  static String _genSession() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '-${r.nextInt(0x7fffffff).toRadixString(36)}';
  }

  /// Registra um breadcrumb. [data] é um mapa pequeno de contexto (números/strings).
  static void event(String name, [Map<String, dynamic> data = const {}]) {
    final crumb = data.isEmpty ? name : '$name ${_compact(data)}';
    try {
      FirebaseCrashlytics.instance.log(crumb);
    } catch (_) {}
    try {
      // Fire-and-forget: não aguardamos o write (estamos no caminho do GPS).
      _collection.add({
        'session': sessionId,
        'v': appVersion,
        'event': name,
        'data': data,
        'ts': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Erro não-fatal: o app segue vivo, mas o erro não some (mata o `catch(_) {}`
  /// silencioso). Sobe pro Crashlytics como non-fatal + vira breadcrumb.
  static void error(String where, Object error, [StackTrace? stack]) {
    try {
      FirebaseCrashlytics.instance
          .recordError(error, stack, reason: where, fatal: false);
    } catch (_) {}
    event('error', {'where': where, 'message': error.toString()});
  }

  static String _compact(Map<String, dynamic> d) =>
      d.entries.map((e) => '${e.key}=${e.value}').join(' ');
}

/// Registra QUALQUER opinião do motorista sobre um ponto: radar, blitz,
/// restrição. Evento único (`vote`) de propósito — o que interessa é o
/// CONFLITO no mesmo ponto, e isso exige uma consulta só, não seis.
///
/// Pedido do Pedro (17/09/2026): "vai ter motorista dizendo que o radar é da
/// contramão, outro dizendo que não é, outro que não existe, outro que é 80,
/// outro que é 60... tudo isso num ÚNICO radar". Hoje o último a falar vence e
/// os outros não deixam rastro; sem este registro não há como decidir limiar
/// de maioria com dado em vez de chute.
///
/// [what] radar | blitz | restricao. [say] o que ele disse: existe |
/// nao_existe | confirma | sumiu | velocidade | criou. [rid] identifica o
/// ponto — chave geográfica (`lat_lng`) no radar, porque os votos chegam por
/// caminhos diferentes e precisam casar; id do doc na blitz e na restrição.
///
/// Quem votou NÃO vai aqui: o uid sai do `app_start` da sessão, como o
/// `viagem.py` já faz. Duplicar o uid em todo voto é peso à toa.
void logVote({
  required String what,
  required String say,
  required String rid,
  Map<String, dynamic> extra = const {},
}) =>
    FieldLog.event('vote', {'what': what, 'say': say, 'rid': rid, ...extra});
