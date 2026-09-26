import 'dart:math' as math;

import '../../models/bridge_restriction.dart';
import '../../models/radar_point.dart';
import '../../services/radar_service.dart';
import '../nav/nav_ui_defs.dart';

/// O "seu trecho" do onboarding: o que o asset OFFLINE tem em volta do
/// motorista, pro caminhão que ele acabou de montar. Puro e testável.
///
/// O asset AVISA (radar, passagem baixa); quem DESVIA é a rota da HERE. Por
/// isso nenhum texto daqui promete desvio.

enum CasoTrecho {
  /// Há passagem mais baixa que o caminhão no raio.
  viadutos,

  /// Nenhuma passagem baixa (interior), mas há radar: mostra o mais perto com
  /// o limite de caminhão, o dado que ninguém mais tem.
  radarMaisPerto,

  /// Nada nem a 100 km.
  tranquilo,
}

enum TipoPonto { radar, viaduto }

/// Ponto pra varredura: rumo (rad, 0 = norte, horário) e distância (km).
class PontoTrecho {
  final TipoPonto tipo;
  final double rumo;
  final double km;
  const PontoTrecho(this.tipo, this.rumo, this.km);
}

class ResumoTrecho {
  final CasoTrecho caso;
  final double raioKm;
  final int radares;
  final int viadutos;
  /// Mais perto, qualquer caso (null se não há radar no raio).
  final double? radarKm;
  /// Limite de caminhão do radar mais perto (null se ele não tem velocidade).
  final int? radarLimite;
  /// Até [maxPontos] pontos mais perto, pra desenhar.
  final List<PontoTrecho> pontos;
  const ResumoTrecho({
    required this.caso, required this.raioKm, required this.radares, required this.viadutos,
    this.radarKm, this.radarLimite, this.pontos = const [],
  });

  /// Frase curta (tela e voz).
  String get titulo => switch (caso) {
        CasoTrecho.viadutos => '$radares ${radares == 1 ? 'radar' : 'radares'} e '
            '$viadutos ${viadutos == 1 ? 'passagem baixa' : 'passagens baixas'}',
        CasoTrecho.radarMaisPerto => 'Radar mais perto: ${_km(radarKm!)}',
        CasoTrecho.tranquilo => 'Aqui tá tranquilo',
      };

  String get texto => switch (caso) {
        CasoTrecho.viadutos => 'Num raio de ${raioKm.round()} km de você, mais baixas que o seu caminhão. '
            'O app avisa cada uma, no limite do seu caminhão.',
        CasoTrecho.radarMaisPerto => radarLimite != null
            ? 'Pro seu caminhão, o limite ali é $radarLimite km/h. '
                'São $radares radares num raio de ${raioKm.round()} km, e o app avisa cada um.'
            : 'São $radares radares num raio de ${raioKm.round()} km, e o app avisa cada um no limite do seu caminhão.',
        CasoTrecho.tranquilo => 'Nenhum radar nem passagem baixa perto. Quando aparecer, eu aviso.',
      };

  static String _km(double km) =>
      km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Só radar de velocidade: o asset tem 19 mil "Lombada" e "Semaforo com
/// Camera" (avanço de sinal), que não são radar e inflariam a conta ~2×.
bool ehRadarDeVelocidade(RadarPoint r) => r.type.contains('Radar');

/// Passagem mais baixa que o caminhão (mesma regra do `conflictsWith`).
bool ehViadutoBaixo(BridgeRestriction b, int alturaCm) =>
    b.type == 'maxheight' && alturaCm / 100.0 >= b.value;

/// Varre os caches num raio (bbox + haversine). Se não há nada em [raioKm],
/// tenta [raioMaxKm] antes de dizer "tranquilo".
ResumoTrecho calcularTrecho({
  required double lat,
  required double lng,
  required int alturaCm,
  required List<RadarPoint> radares,
  required List<BridgeRestriction> restricoes,
  double raioKm = 30,
  double raioMaxKm = 100,
  int maxPontos = 60,
}) {
  ResumoTrecho? tenta(double r) {
    final dLat = r / 111.0;
    final dLng = r / (111.0 * math.cos(lat * math.pi / 180).abs().clamp(.2, 1.0));
    bool naCaixa(double la, double ln) => (la - lat).abs() <= dLat && (ln - lng).abs() <= dLng;

    final pontos = <PontoTrecho>[];
    var nRadar = 0, nViaduto = 0;
    RadarPoint? maisPerto;
    var maisPertoKm = double.infinity;
    for (final p in radares) {
      if (!ehRadarDeVelocidade(p) || !naCaixa(p.lat, p.lng)) continue;
      final km = RadarService.haversine(lat, lng, p.lat, p.lng) / 1000;
      if (km > r) continue;
      nRadar++;
      pontos.add(PontoTrecho(TipoPonto.radar, _rumo(lat, lng, p.lat, p.lng), km));
      if (km < maisPertoKm) {
        maisPertoKm = km;
        maisPerto = p;
      }
    }
    for (final b in restricoes) {
      if (!ehViadutoBaixo(b, alturaCm) || !naCaixa(b.lat, b.lng)) continue;
      final km = RadarService.haversine(lat, lng, b.lat, b.lng) / 1000;
      if (km > r) continue;
      nViaduto++;
      pontos.add(PontoTrecho(TipoPonto.viaduto, _rumo(lat, lng, b.lat, b.lng), km));
    }
    if (nRadar == 0 && nViaduto == 0) return null;
    pontos.sort((a, b) => a.km.compareTo(b.km));
    return ResumoTrecho(
      caso: nViaduto > 0 ? CasoTrecho.viadutos : CasoTrecho.radarMaisPerto,
      raioKm: r,
      radares: nRadar,
      viadutos: nViaduto,
      radarKm: maisPerto == null ? null : maisPertoKm,
      radarLimite: maisPerto?.truckKmh,
      pontos: pontos.take(maxPontos).toList(),
    );
  }

  final perto = tenta(raioKm);
  // Só viaduto sem radar no raio curto ainda é "viadutos"; zero de tudo expande.
  if (perto != null) return perto;
  final longe = tenta(raioMaxKm);
  if (longe != null) return longe;
  return ResumoTrecho(caso: CasoTrecho.tranquilo, raioKm: raioMaxKm, radares: 0, viadutos: 0);
}

double _rumo(double lat1, double lng1, double lat2, double lng2) {
  final f1 = lat1 * math.pi / 180, f2 = lat2 * math.pi / 180;
  final dl = (lng2 - lng1) * math.pi / 180;
  final y = math.sin(dl) * math.cos(f2);
  final x = math.cos(f1) * math.sin(f2) - math.sin(f1) * math.cos(f2) * math.cos(dl);
  return math.atan2(y, x);
}

/// Faixa pra telemetria: nunca o número exato nem o lugar.
String faixa(int n) => n == 0 ? '0' : n <= 10 ? '1-10' : n <= 100 ? '11-100' : '100+';
