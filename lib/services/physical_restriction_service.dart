import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import '../utils/geo_bounds.dart';
import 'radar_service.dart';

/// Restrições físicas de via (altura / peso / largura) lidas do asset offline.
///
/// Isto era uma consulta HTTP à Overpass no meio do cálculo da rota, e ela nunca
/// funcionou em produção. Medido em 2026-07-22 (8 amostras, mesma bbox da Grande
/// SP): 3x 504, 2x 200 em 17-28s contra um timeout de 15s no cliente, e 1x 200
/// com `remark: Query timed out` — resultado PARCIAL entregue como se fosse
/// completo, sem disparar o `overpass_fail`. Não havia caminho em que desse
/// certo: ou o servidor cortava, ou o cliente cortava. Em campo, `reroute_enrich`
/// reportou `restr: 0` em 4 de 4.
///
/// A raiz era o tamanho da bbox (rota de 43 km na Grande SP → retângulo de ~33x40
/// km na área mais densa do país), não o servidor: a mesma query numa bbox de 1/4
/// completava limpa. O asset resolve os três modos de falha de uma vez e ainda
/// funciona sem sinal — que é o cenário real do caminhoneiro em estrada.
///
/// O asset é gerado por `tools/restricoes_fetch.py` (roda offline, fatia o país e
/// valida o `remark`). Regerar a cada release mantém o dado fresco.
class PhysicalRestrictionService {
  /// Mesma largura de corredor que a busca online usava.
  static const _corridorM = 80.0;

  static List<BridgeRestriction>? _cache;

  static Future<List<BridgeRestriction>> load() async {
    if (_cache != null) return _cache!;
    _cache = parseCsv(await rootBundle.loadString('assets/restricoes.csv'));
    return _cache!;
  }

  /// `longitude,latitude,tipo,valor,via` — mesma ordem de colunas do asset de
  /// radar. O valor já vem numérico (metros ou toneladas): quem interpreta as
  /// grafias do OSM ("4.5 m", "10 t", "4'6\"", "default") é o gerador, não o app.
  @visibleForTesting
  static List<BridgeRestriction> parseCsv(String csv) {
    final result = <BridgeRestriction>[];
    for (final line in csv.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(',');
      if (parts.length < 4) continue;
      final lng   = double.tryParse(parts[0]);
      final lat   = double.tryParse(parts[1]);
      final value = double.tryParse(parts[3]);
      if (lng == null || lat == null || value == null) continue; // header/inválida
      final via = parts.length > 4 ? parts[4].trim() : '';
      result.add(BridgeRestriction(
        lat: lat,
        lng: lng,
        type: parts[2].trim(),
        value: value,
        roadName: via.isEmpty ? null : via,
      ));
    }
    return result;
  }

  /// Restrições dentro do corredor da rota. Não toca a rede e não lança.
  static Future<List<BridgeRestriction>> queryAlongRoute(
      List<LatLng> polyline) async {
    if (polyline.isEmpty) return [];
    return filterNearRoute(await load(), polyline);
  }

  @visibleForTesting
  static List<BridgeRestriction> filterNearRoute(
    List<BridgeRestriction> all,
    List<LatLng> polyline,
  ) {
    if (polyline.length < 2) return [];

    // Bbox da rota derruba o país inteiro por comparação trivial, antes da conta
    // cara. Sem isto seriam 14 mil restrições x centenas de segmentos na UI.
    const buffer = 0.001; // ~110 m, folga sobre o corredor
    var (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(polyline);
    minLat -= buffer; maxLat += buffer;
    minLng -= buffer; maxLng += buffer;

    final result = <BridgeRestriction>[];
    for (final r in all) {
      if (r.lat < minLat || r.lat > maxLat ||
          r.lng < minLng || r.lng > maxLng) { continue; }
      // Perpendicular ao SEGMENTO, não a pontos soltos da polyline: é o que faz
      // a restrição de uma via paralela cair fora do corredor. Mesmo teste que o
      // radar usa desde o fix do falso-positivo de paralela.
      for (var i = 0; i < polyline.length - 1; i++) {
        final d = RadarService.distanceToSegment(
          r.lat, r.lng,
          polyline[i].latitude,     polyline[i].longitude,
          polyline[i + 1].latitude, polyline[i + 1].longitude,
        );
        if (d <= _corridorM) {
          result.add(r);
          break;
        }
      }
    }
    return result;
  }
}
