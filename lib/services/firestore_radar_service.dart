import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/geo_bounds.dart';
import '../models/radar_point.dart';
import 'radar_service.dart';

/// Camada crowd-source sobre o CSV estático de radar.
/// - `radars`: radares ADICIONADOS por usuários (mirror de `restrictions`).
/// - `radar_dismissals`: votos de "não existe" contra um ponto (CSV ou user),
///    agregados por chave de localização. Some quando passa o limiar.
class FirestoreRadarService {
  static final _db = FirebaseFirestore.instance;
  static const _radarsCol     = 'radars';
  static const _dismissalsCol = 'radar_dismissals';
  static const _corridorM     = 80.0;   // mesmo corredor do FirestoreRestrictionService
  static const _dismissMatchM = 40.0;   // raio p/ casar dispensa↔radar do CSV

  // ponytail: limiar de votos pra sumir global. 1 enquanto há ~1 usuário; subir
  // conforme a base cresce (3 vira razoável). Vale p/ reportedBy e p/ dismissals.
  static const _hideThreshold = 1;

  /// Radares crowd (adicionados) perto da rota, já filtrando os derrubados por voto.
  static Future<List<RadarPoint>> fetchNearRoute(List<LatLng> points) async {
    if (points.isEmpty) return [];
    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(points);
    const pad = 0.05; // ~5 km
    try {
      final snap = await _db
          .collection(_radarsCol)
          .where('lat', isGreaterThanOrEqualTo: minLat - pad)
          .where('lat', isLessThanOrEqualTo: maxLat + pad)
          .get();
      return snap.docs
          .where((d) {
            final m = d.data();
            final lng = (m['lng'] as num).toDouble();
            final reported = (m['reportedBy'] as num?)?.toInt() ?? 0;
            return lng >= minLng - pad &&
                lng <= maxLng + pad &&
                reported < _hideThreshold &&
                _isNearRoute((m['lat'] as num).toDouble(), lng, points);
          })
          .map((d) {
            final m = d.data();
            return RadarPoint(
              lat: (m['lat'] as num).toDouble(),
              lng: (m['lng'] as num).toDouble(),
              type: m['type'] as String? ?? 'Radar',
              speedKmh: (m['speedKmh'] as num?)?.toInt() ?? 0,
              id: d.id,
              source: 'user',
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Localizações com votos de dispensa acima do limiar (pra suprimir radar do CSV).
  static Future<List<LatLng>> fetchDismissals(List<LatLng> points) async {
    if (points.isEmpty) return [];
    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(points);
    const pad = 0.05;
    try {
      final snap = await _db
          .collection(_dismissalsCol)
          .where('lat', isGreaterThanOrEqualTo: minLat - pad)
          .where('lat', isLessThanOrEqualTo: maxLat + pad)
          .get();
      return snap.docs
          .where((d) {
            final m = d.data();
            final lng = (m['lng'] as num).toDouble();
            final count = (m['count'] as num?)?.toInt() ?? 0;
            return lng >= minLng - pad && lng <= maxLng + pad && count >= _hideThreshold;
          })
          .map((d) {
            final m = d.data();
            return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Junta CSV (perto da rota) + crowd, removendo os pontos do CSV dispensados.
  /// Em falha de rede devolve o CSV intacto (não esconde radar por causa de erro).
  static Future<List<RadarPoint>> mergeCrowd(
      List<RadarPoint> csvNearRoute, List<LatLng> points) async {
    final crowd      = await fetchNearRoute(points);
    final dismissals = await fetchDismissals(points);
    final survivingCsv = csvNearRoute.where((r) => !dismissals.any((d) =>
        RadarService.haversine(r.lat, r.lng, d.latitude, d.longitude) <= _dismissMatchM));
    return [...survivingCsv, ...crowd];
  }

  static Future<String?> add({
    required double lat,
    required double lng,
    required String type,
    required int speedKmh,
    required String uid,
  }) async {
    try {
      final doc = await _db.collection(_radarsCol).add({
        'lat': lat,
        'lng': lng,
        'type': type,
        'speedKmh': speedKmh,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': uid,
        'confirmedBy': 0,
        'reportedBy': 0,
        'source': 'user',
      });
      return doc.id;
    } catch (_) {
      return null;
    }
  }

  /// "Existe sim" num radar crowd → sobe a confiança.
  static Future<void> confirm(String docId) async {
    try {
      await _db.collection(_radarsCol).doc(docId).update(
          {'confirmedBy': FieldValue.increment(1)});
    } catch (_) {}
  }

  /// "Não existe" num radar crowd → voto de remoção.
  static Future<void> report(String docId) async {
    try {
      await _db.collection(_radarsCol).doc(docId).update(
          {'reportedBy': FieldValue.increment(1)});
    } catch (_) {}
  }

  /// "Não existe" num radar do CSV → agrega voto por localização (doc determinístico).
  static Future<void> dismissCsv(double lat, double lng) async {
    try {
      final key = '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';
      await _db.collection(_dismissalsCol).doc(key).set({
        'lat': lat,
        'lng': lng,
        'count': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static bool _isNearRoute(double lat, double lng, List<LatLng> polyline) {
    for (var i = 0; i < polyline.length; i += 5) {
      if (RadarService.haversine(lat, lng, polyline[i].latitude, polyline[i].longitude) <= _corridorM) {
        return true;
      }
    }
    if (polyline.isNotEmpty) {
      final last = polyline.last;
      if (RadarService.haversine(lat, lng, last.latitude, last.longitude) <= _corridorM) {
        return true;
      }
    }
    return false;
  }
}
