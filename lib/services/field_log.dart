import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

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
    // Qualquer evento esvazia o buffer ANTES de si: é isso que faz o
    // agrupamento não custar diagnóstico. Quando algo interessante acontece
    // (off_route, reroute, chegada, erro), as amostras que levaram até ele
    // chegam junto, no mesmo instante — que é exatamente quando elas valem.
    _flush();
    _crumb(name, data);
    _escrever(name, data);
  }

  /// Amostra periódica e repetitiva (hoje só o `heartbeat`, de 30 em 30 s).
  ///
  /// Um documento por amostra era o maior consumidor de escrita do projeto:
  /// ~960 por motorista em 8 h de viagem, contra o teto de 20.000/dia do plano
  /// Spark — ou seja, ~20 motoristas e a telemetria morre (e o Firestore aqui
  /// não tem billing, então não vira conta, vira silêncio). Agrupadas de
  /// [_loteMax] em [_loteMax], o mesmo dado cabe em 1 documento.
  ///
  /// **O intervalo NÃO muda.** Foi a resolução de 30 s que revelou os 105
  /// recálculos com o caminhão parado; aumentá-la perderia achado, agrupar não
  /// perde nenhuma amostra.
  ///
  /// O Crashlytics continua recebendo CADA amostra na hora (o breadcrumb é o
  /// que sobrevive a um ANR), então o rastro fino não depende deste buffer.
  static void amostra(String name, Map<String, dynamic> data) {
    // Trocar de tipo de amostra fecha o lote anterior: misturar dois nomes num
    // documento só faria o `event` do documento mentir sobre o que tem dentro.
    if (_lote.isNotEmpty && name != _loteNome) _flush();
    _loteNome = name;
    _crumb(name, data);
    _lote.add(data);
    if (_lote.length >= _loteMax) _flush();
  }

  /// ponytail: 10 × 30 s = 5 min de janela. Teto do que se perde num freeze
  /// TOTAL sem nenhum evento junto — e mesmo aí as amostras estão no
  /// Crashlytics. Se um dia precisar de mais fôlego, este é o número a subir.
  static const _loteMax = 10;
  static final List<Map<String, dynamic>> _lote = [];
  static String _loteNome = 'heartbeat';

  static void _flush() {
    if (_lote.isEmpty) return;
    final amostras = List<Map<String, dynamic>>.from(_lote);
    _lote.clear();
    _escrever(_loteNome, {'n': amostras.length, 'hb': amostras});
  }

  static void _crumb(String name, Map<String, dynamic> data) {
    try {
      FirebaseCrashlytics.instance
          .log(data.isEmpty ? name : '$name ${_compact(data)}');
    } catch (_) {}
  }

  /// Desvia os writes num teste. A ordem em que eles saem É a feature aqui (o
  /// lote tem que sair ANTES do evento que o fechou), e isso não dá pra provar
  /// por função pura — só olhando a sequência.
  @visibleForTesting
  static void Function(String name, Map<String, dynamic> data)? sinkDeTeste;

  @visibleForTesting
  static void limparLoteParaTeste() => _lote.clear();

  /// Só o write. O breadcrumb é responsabilidade de quem chama: no lote as
  /// amostras já foram para o Crashlytics UMA a UMA, na hora em que
  /// aconteceram, e repetir o lote inteiro aqui duplicaria o rastro.
  static void _escrever(String name, Map<String, dynamic> data) {
    if (sinkDeTeste != null) {
      sinkDeTeste!(name, data);
      return;
    }
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
