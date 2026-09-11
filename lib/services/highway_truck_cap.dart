import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/radar_point.dart';
import '../models/route_result.dart';
import 'radar_service.dart';

/// Teto de caminhão por rodovia (km/h), chaveado pelo `routeNumbers` que a
/// HERE devolve por trecho (`spans=routeNumbers`). Só entra rodovia com limite
/// de caminhão CONFIRMADO em fonte oficial ou notícia da concessão; placa de
/// carro não serve.
///
/// Por que existe: o MapaRadar cadastra a placa de carro (100 no Rodoanel) e o
/// app capava em 90, o teto genérico. O Gilberto (11/09, áudio) viu "90" num
/// radar do Rodoanel que fiscaliza caminhão a 80. `spans=speedLimit` da HERE já
/// foi tentado e reprovado (cravava 40 em via de 90, 09/07). Tabela é constante
/// calibrada, sim — mas curta, por rodovia, e SÓ ABAIXA: errar pra menos é
/// falso alarme (passável), errar pra mais é multa.
///
/// ponytail: mapa fixo. Se passar de meia dúzia de entradas, vira asset.
const Map<String, int> kHighwayTruckCapKmh = {
  // Rodoanel Mário Covas, anel inteiro: 100 leve / 80 pesado
  // (gov SP, trechos Sul e Leste; Via SP Serra, trecho Norte).
  'SP-021': 80,
};

/// Aplica o teto da rodovia como `truckLimitOff` do radar (a mesma regra do
/// limite oficial ANTT: `truckRadarLimit` faz o min). Radar sem velocidade
/// (pedágio, lombada, dado ausente) fica como está — sem número não há o que
/// abaixar, e o official viraria a velocidade "do" pedágio. Curador que cravou
/// 90 num ponto de rodovia de 80 também cai pra 80: o menor manda.
List<RadarPoint> applyHighwayCaps(List<RadarPoint> radars, RouteResult route) {
  if (route.routeRefs.isEmpty || radars.isEmpty) return radars;
  final pts = route.polylinePoints;
  if (pts.isEmpty) return radars;
  return [
    for (final r in radars)
      if (r.speedKmh <= 0) r else _capped(r, route, pts),
  ];
}

RadarPoint _capped(RadarPoint r, RouteResult route, List<LatLng> pts) {
  // Vértice mais perto do radar → trecho (span) → rodovia → teto.
  var bestIdx = 0;
  var bestD = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    final d = RadarService.haversine(r.lat, r.lng, pts[i].latitude, pts[i].longitude);
    if (d < bestD) { bestD = d; bestIdx = i; }
  }
  int? cap;
  for (final ref in route.refsAt(bestIdx)) {
    final c = kHighwayTruckCapKmh[ref];
    if (c != null && (cap == null || c < cap)) cap = c;
  }
  if (cap == null) return r;
  final off = r.truckLimitOff;
  if (off != null && off <= cap) return r; // oficial já é menor: não sobe
  return r.copyWith(truckLimitOff: min(cap, off ?? cap));
}
