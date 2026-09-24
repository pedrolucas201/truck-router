import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route_maneuver.dart';
import 'radar_service.dart';

/// Quanto tempo a HERE previa pra chegar em cada ponto da rota, somando a
/// duração de cada manobra (já vem na resposta, com o trânsito do momento do
/// cálculo). É o "plano" contra o qual se mede atraso: proporcional à
/// distância não serve, porque 10 km de cidade custam mais que 10 km de
/// rodovia e o começo urbano de toda viagem pareceria "atrasado".
///
/// Fase A (24/09): só telemetria (`atrasoS` no heartbeat e no reroute_done,
/// `perfilS` no nav_start). O gatilho "recalcula quando atrasou" entra depois
/// que a distribuição em campo disser o limiar.
class PlanoRota {
  final List<int> _offsets;   // vértice da polyline onde cada manobra começa
  final List<int> _inicioS;   // previsto acumulado ao INÍCIO de cada manobra
  final List<int> _durS;      // duração de cada manobra
  final List<double> _cumM;   // distância acumulada por vértice
  final int _rotaDurS;        // duração total da rota, pro fallback

  PlanoRota._(this._offsets, this._inicioS, this._durS, this._cumM, this._rotaDurS);

  factory PlanoRota.de(List<RouteManeuver> manobras, List<LatLng> pts, {required int rotaDurS}) {
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum[i - 1] + RadarService.haversine(
          pts[i - 1].latitude, pts[i - 1].longitude, pts[i].latitude, pts[i].longitude));
    }
    final offsets = <int>[], inicio = <int>[], dur = <int>[];
    var acc = 0;
    for (final m in manobras) {
      if (offsets.isNotEmpty && m.polylineOffset < offsets.last) continue; // fora de ordem: ignora
      offsets.add(m.polylineOffset.clamp(0, pts.isEmpty ? 0 : pts.length - 1));
      inicio.add(acc);
      dur.add(m.durationSeconds);
      acc += m.durationSeconds;
    }
    return PlanoRota._(offsets, inicio, dur, cum, rotaDurS);
  }

  /// Soma das durações das manobras. Perto de zero = fonte sem duração por
  /// manobra (TomTom) → [previstoAteS] cai no proporcional. Vai no nav_start
  /// como `perfilS` pra comparar com o `durS` da rota: se divergir muito, o
  /// perfil não presta e o atraso medido não vale.
  int get perfilS => _inicioS.isEmpty ? 0 : _inicioS.last + _durS.last;

  /// Segundos que a rota previa até o vértice [idx].
  int previstoAteS(int idx) {
    if (_cumM.length < 2) return 0;
    final i = idx.clamp(0, _cumM.length - 1);
    if (perfilS == 0) {
      // ponytail: proporcional só como fallback; se a TomTom virar fonte comum,
      // parsear a duração por instrução dela também.
      return _cumM.last > 0 ? (_rotaDurS * _cumM[i] / _cumM.last).round() : 0;
    }
    var k = -1;
    for (var j = 0; j < _offsets.length && _offsets[j] <= i; j++) {
      k = j;
    }
    if (k < 0) return 0;
    final ini = _cumM[_offsets[k]];
    final fim = k + 1 < _offsets.length ? _cumM[_offsets[k + 1]] : _cumM.last;
    final frac = fim > ini ? ((_cumM[i] - ini) / (fim - ini)).clamp(0.0, 1.0) : 1.0;
    return _inicioS[k] + (_durS[k] * frac).round();
  }

  /// Positivo = atrasado em relação ao plano; negativo = adiantado.
  int atrasoS({required int idx, required Duration decorrido}) =>
      decorrido.inSeconds - previstoAteS(idx);
}
