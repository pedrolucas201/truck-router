// radar_direction.dart
// Camada de sentido do radar: classificação (decoração visual) + coleta passiva.
//
// INVARIANTE DO PROJETO: nada aqui suprime alerta. O resultado da classificação
// só decora o payload que _upcomingRadar entrega para UI/voz. Errar a
// classificação, no pior caso, esconde uma etiqueta — nunca cala um alerta.

import 'dart:math' as math;

/// Resultado da comparação heading do motorista x sentido fiscalizado.
enum RadarDirMatch {
  /// Radar fiscaliza o sentido do motorista (ou é bidirecional casando).
  same,

  /// Radar unidirecional, fonte oficial, claramente do sentido oposto.
  /// ALERTA CONTINUA — só ganha etiqueta "sentido oposto".
  opposite,

  /// Sem dado, zona morta angular, ou qualquer dúvida. Alerta pleno, sem etiqueta.
  unknown,
}

/// Diferença angular mínima entre dois bearings, em [0, 180].
double angleDiff(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// Classifica o radar em relação ao heading atual.
///
/// [dir1]/[dir2]: bearings do CSV enriquecido (dir2 != null => bidirecional).
/// [dirSrc]: 'dnit' | 'antt' | 'pass' | null.
/// [userHeading]: heading do GPS em graus (Position.heading).
/// [headingAccuracy]: se disponível e ruim (> 45°), classifica unknown.
///
/// Zona morta 100–145°: implementa a assimetria da nota técnica —
/// só rotula "oposto" com margem folgada; na dúvida, unknown (alerta pleno).
RadarDirMatch classifyRadarDirection({
  required double? dir1,
  required double? dir2,
  required String? dirSrc,
  required double userHeading,
  double? headingAccuracy,
}) {
  if (dir1 == null || dirSrc == null || dirSrc.isEmpty) {
    return RadarDirMatch.unknown;
  }
  if (userHeading < 0) return RadarDirMatch.unknown; // GPS sem heading
  if (headingAccuracy != null && headingAccuracy > 45) {
    return RadarDirMatch.unknown;
  }

  const sameMax = 100.0; // tolerância generosa: curvas, alças, GPS
  const oppositeMin = 145.0; // só rotula oposto com folga

  final d1 = angleDiff(userHeading, dir1);
  if (d1 <= sameMax) return RadarDirMatch.same;

  // Bidirecional: se qualquer um dos sentidos casa, é "same".
  if (dir2 != null) {
    if (angleDiff(userHeading, dir2) <= sameMax) return RadarDirMatch.same;
    // Bidirecional que não casa com nenhum sentido = geometria estranha
    // (alça, retorno). Dúvida => unknown.
    return RadarDirMatch.unknown;
  }

  if (d1 >= oppositeMin) return RadarDirMatch.opposite;
  return RadarDirMatch.unknown; // zona morta
}

// ---------------------------------------------------------------------------
// Coleta passiva: radar_pass
// ---------------------------------------------------------------------------

/// Registro de uma passagem por radar. Zero efeito na tela.
/// Gravar no Firestore em `radar_pass/{autoId}` — batched, 1 por radar por viagem.
class RadarPassEvent {
  final String radarId;
  final double heading; // graus 0-359 no momento da passagem
  final double speedKmh;
  final DateTime ts;

  const RadarPassEvent({
    required this.radarId,
    required this.heading,
    required this.speedKmh,
    required this.ts,
  });

  Map<String, dynamic> toMap() => {
        'rid': radarId,
        // Normaliza pro range da regra do Firestore (0-359): 360° ≡ 0°. Sem isso,
        // um heading de 359.6° arredonda pra 360, viola a regra e derruba o
        // WriteBatch inteiro (atômico).
        'h': heading.round() % 360,
        // Teto de sanidade (a regra exige <= 200); v não entra na agregação de
        // bearing, só é guardado. Clampa glitch de GPS em vez de perder o batch.
        'v': speedKmh.round().clamp(0, 200),
        'ts': ts.toUtc().millisecondsSinceEpoch,
      };
}

/// Controla dedupe por viagem e fila de flush.
/// Chamar [onRadarCrossed] no mesmo ponto onde o corredor do radar é cruzado
/// (o gate já existente em _upcomingRadar detecta isso de graça).
class RadarPassLogger {
  final Set<String> _loggedThisTrip = {};
  final List<RadarPassEvent> _queue = [];
  final Future<void> Function(List<Map<String, dynamic>>) flush;

  /// [flush] recebe o batch pronto — plugar no FirestoreRadarService
  /// (WriteBatch, coleção radar_pass). Chamado a cada [batchSize] eventos
  /// e no fim da viagem via [endTrip].
  RadarPassLogger({required this.flush, this.batchSize = 10});

  final int batchSize;

  void onRadarCrossed({
    required String radarId,
    required double heading,
    required double speedKmh,
  }) {
    if (heading < 0) return; // sem heading confiável, não polui a base
    if (!_loggedThisTrip.add(radarId)) return; // 1 write por radar por viagem
    _queue.add(RadarPassEvent(
      radarId: radarId,
      heading: heading,
      speedKmh: speedKmh,
      ts: DateTime.now(),
    ));
    if (_queue.length >= batchSize) _drain();
  }

  Future<void> endTrip() async {
    await _drain();
    _loggedThisTrip.clear();
  }

  Future<void> _drain() async {
    if (_queue.isEmpty) return;
    final batch = _queue.map((e) => e.toMap()).toList(growable: false);
    _queue.clear();
    try {
      await flush(batch);
    } catch (_) {
      // Coleta é best-effort: perder um batch não pode afetar a navegação.
    }
  }
}

// ---------------------------------------------------------------------------
// Agregação circular (rodar em batch — Cloud Function ou tools/ offline)
// ---------------------------------------------------------------------------

/// Resultado da promoção de bearing a partir das passagens crowd.
class CrowdBearing {
  final double? dir1;
  final double? dir2; // != null => bidirecional confirmado
  final int samples;
  final double concentration; // R em [0,1]

  const CrowdBearing(this.dir1, this.dir2, this.samples, this.concentration);

  bool get promoted => dir1 != null;
}

/// Promove um bearing crowd a partir dos headings das passagens.
///
/// Regras (conservadoras, na linha do invariante):
/// - n >= [minSamples] e concentração R >= [minR]  => unidirecional (dir1)
/// - R baixo mas os headings "dobrados" (mod 180) concentram => bidirecional
/// - qualquer outra coisa => não promove (fica unknown, alerta pleno)
CrowdBearing aggregateHeadings(
  List<double> headings, {
  int minSamples = 10,
  double minR = 0.9,
}) {
  final n = headings.length;
  if (n < minSamples) return CrowdBearing(null, null, n, 0);

  double sx = 0, sy = 0;
  for (final h in headings) {
    sx += math.cos(h * math.pi / 180);
    sy += math.sin(h * math.pi / 180);
  }
  final r = math.sqrt(sx * sx + sy * sy) / n;
  final mean = (math.atan2(sy, sx) * 180 / math.pi + 360) % 360;

  if (r >= minR) return CrowdBearing(mean, null, n, r);

  // Teste bimodal: dobra os ângulos (mod 180). Dois clusters opostos a ~180°
  // colapsam num só; se o dobrado concentra, é bidirecional.
  double fx = 0, fy = 0;
  for (final h in headings) {
    final f = (h % 180) * 2 * math.pi / 180;
    fx += math.cos(f);
    fy += math.sin(f);
  }
  final rf = math.sqrt(fx * fx + fy * fy) / n;
  if (rf >= minR) {
    final axis = ((math.atan2(fy, fx) * 180 / math.pi + 360) % 360) / 2;
    return CrowdBearing(axis, (axis + 180) % 360, n, rf);
  }

  return CrowdBearing(null, null, n, r); // disperso demais: não promove
}
