import 'dart:math';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/geo_bounds.dart';
import '../models/radar_point.dart';

class RadarService {
  static List<RadarPoint>? _cache;

  static Future<List<RadarPoint>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/maparadar.csv');
    _cache = _parse(raw);
    return _cache!;
  }

  static List<RadarPoint> _parse(String csv) {
    final result = <RadarPoint>[];
    for (final line in csv.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final commaIdx1 = trimmed.indexOf(',');
      if (commaIdx1 == -1) continue;
      final commaIdx2 = trimmed.indexOf(',', commaIdx1 + 1);
      if (commaIdx2 == -1) continue;
      final lng = double.tryParse(trimmed.substring(0, commaIdx1));
      final lat = double.tryParse(trimmed.substring(commaIdx1 + 1, commaIdx2));
      if (lng == null || lat == null) continue;
      final desc = trimmed.substring(commaIdx2 + 1);
      final atIdx = desc.lastIndexOf('@');
      final type = atIdx > 0 ? desc.substring(0, atIdx).trim() : desc.trim();
      final speed = atIdx > 0 ? int.tryParse(desc.substring(atIdx + 1).trim()) ?? 0 : 0;
      result.add(RadarPoint(lat: lat, lng: lng, type: type, speedKmh: speed));
    }
    return result;
  }

  static List<RadarPoint> deduplicateNearby(
    List<RadarPoint> radares, {
    double minDistanceMeters = 150,
  }) {
    final result = <RadarPoint>[];
    for (final r in radares) {
      var tooClose = false;
      for (final kept in result) {
        if (haversine(r.lat, r.lng, kept.lat, kept.lng) < minDistanceMeters) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) { result.add(r); }
    }
    return result;
  }

  static List<RadarPoint> filterNearRoute(
    List<RadarPoint> all,
    List<LatLng> polyline, {
    double radiusMeters = 500,
  }) {
    if (polyline.isEmpty) return [];

    // Bounding box com buffer (~500m em graus)
    const buffer = 0.005;
    var (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(polyline);
    minLat -= buffer; maxLat += buffer;
    minLng -= buffer; maxLng += buffer;

    // Amostra a polyline a cada 5 pontos para reduzir cálculos
    final sampled = <LatLng>[];
    for (var i = 0; i < polyline.length; i += 5) {
      sampled.add(polyline[i]);
    }
    if (sampled.isEmpty || sampled.last != polyline.last) {
      sampled.add(polyline.last);
    }


    final result = <RadarPoint>[];
    for (final radar in all) {
      // Filtro rápido por bounding box
      if (radar.lat < minLat || radar.lat > maxLat ||
          radar.lng < minLng || radar.lng > maxLng) { continue; }
      // Verifica distância real a algum ponto amostrado
      for (final p in sampled) {
        if (haversine(radar.lat, radar.lng, p.latitude, p.longitude) <= radiusMeters) {
          result.add(radar);
          break;
        }
      }
    }
    return result;
  }

  /// Distância perpendicular (em metros) de um ponto ao SEGMENTO a→b.
  /// Projeção equiretangular local — precisa o suficiente na escala de rua.
  /// Diferente de medir distância a um ponto solto da polyline: aqui a
  /// separação entre vias vira a distância real, então radar em rua paralela
  /// cai fora do corredor (mata o falso-positivo de paralela).
  static double distanceToSegment(
    double pLat, double pLng,
    double aLat, double aLng,
    double bLat, double bLng,
  ) {
    const mPerLat = 111320.0;
    final mPerLng = 111320.0 * cos(aLat * pi / 180);
    // Projeta para metros locais com origem em a.
    final px = (pLng - aLng) * mPerLng, py = (pLat - aLat) * mPerLat;
    final bx = (bLng - aLng) * mPerLng, by = (bLat - aLat) * mPerLat;
    final segLen2 = bx * bx + by * by;
    var t = segLen2 == 0 ? 0.0 : (px * bx + py * by) / segLen2;
    t = t.clamp(0.0, 1.0); // clampa na ponta: ponto além do segmento mede até a ponta
    final cx = t * bx, cy = t * by;
    final dx = px - cx, dy = py - cy;
    return sqrt(dx * dx + dy * dy);
  }

  /// Menor distância perpendicular (metros) de um ponto ao trajeto (sequência
  /// de segmentos). É o teste de "está na via": compara contra os segmentos da
  /// rota, não contra pontos soltos.
  static double distanceToPath(double lat, double lng, List<LatLng> path) {
    if (path.isEmpty) return double.infinity;
    if (path.length == 1) {
      return haversine(lat, lng, path[0].latitude, path[0].longitude);
    }
    var best = double.infinity;
    for (var i = 0; i < path.length - 1; i++) {
      final d = distanceToSegment(
        lat, lng,
        path[i].latitude, path[i].longitude,
        path[i + 1].latitude, path[i + 1].longitude,
      );
      if (d < best) best = d;
    }
    return best;
  }

  /// Distância restante (metros) ao longo da rota, somando os segmentos de
  /// [fromIdx] até o fim. Para de somar assim que passa de [capM] — barato, o
  /// chamador só quer saber se está abaixo de um teto (ex: reta final da rota).
  /// fromIdx fora do intervalo (>= último vértice) → 0.
  static double remainingAlongRoute(List<LatLng> path, int fromIdx, double capM) {
    var sum = 0.0;
    for (var i = fromIdx; i < path.length - 1 && sum <= capM; i++) {
      sum += haversine(path[i].latitude, path[i].longitude,
          path[i + 1].latitude, path[i + 1].longitude);
    }
    return sum;
  }

  static double haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Ponto está dentro do corredor [corridorM] da [polyline]? Amostra a cada 5
  /// vértices (perf) + checa o último. Compartilhado pelos services de crowd.
  static bool isNearRoute(double lat, double lng, List<LatLng> polyline,
      {double corridorM = 80.0}) {
    for (var i = 0; i < polyline.length; i += 5) {
      if (haversine(lat, lng, polyline[i].latitude, polyline[i].longitude) <= corridorM) {
        return true;
      }
    }
    if (polyline.isNotEmpty) {
      final last = polyline.last;
      if (haversine(lat, lng, last.latitude, last.longitude) <= corridorM) {
        return true;
      }
    }
    return false;
  }
}
