import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/geo_bounds.dart';
import '../models/bridge_restriction.dart';
import '../models/user_restriction.dart';
import 'field_log.dart';
import 'radar_service.dart';

class FirestoreRestrictionService {
  static final _db = FirebaseFirestore.instance;
  static const _col = 'restrictions';

  // Busca restrições num bounding box ao redor da rota.
  // Filtra lat via Firestore; lng filtrado client-side (limitação do Firestore).
  static Future<List<BridgeRestriction>> fetchNearRoute(
      List<LatLng> points) async {
    if (points.isEmpty) return [];

    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(points);
    const pad = 0.05; // ~5 km de margem

    try {
      final snap = await _db
          .collection(_col)
          .where('lat', isGreaterThanOrEqualTo: minLat - pad)
          .where('lat', isLessThanOrEqualTo: maxLat + pad)
          .get();

      return snap.docs
          .map(_fromDoc)
          .where((r) =>
              r.lng >= minLng - pad &&
              r.lng <= maxLng + pad &&
              RadarService.isNearRoute(r.lat, r.lng, points))
          .toList();
    } catch (e, st) {
      // Pega falha de rede E doc malformado (_fromDoc lança CastError aqui).
      FieldLog.error('restriction_fetch', e, st);
      return [];
    }
  }

  static Future<List<BridgeRestriction>> fetchByBounds(
    double minLat, double maxLat, double minLng, double maxLng,
  ) async {
    try {
      final snap = await _db
          .collection(_col)
          .where('lat', isGreaterThanOrEqualTo: minLat)
          .where('lat', isLessThanOrEqualTo: maxLat)
          .get();
      return snap.docs
          .map(_fromDoc)
          .where((r) => r.lng >= minLng && r.lng <= maxLng)
          .toList();
    } catch (e, st) {
      FieldLog.error('restriction_fetch_bounds', e, st);
      return [];
    }
  }

  static BridgeRestriction _fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BridgeRestriction(
      id:          doc.id,
      lat:         (d['lat']   as num).toDouble(),
      lng:         (d['lng']   as num).toDouble(),
      type:        d['type']   as String,
      value:       (d['value'] as num).toDouble(),
      roadName:    d['roadName'] as String?,
      confirmedBy: (d['confirmedBy'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<String> add(UserRestriction r, String uid) async {
    final doc = await _db.collection(_col).add({
      'lat': r.lat,
      'lng': r.lng,
      'type': r.type,
      'value': r.value,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': uid,
      'confirmedBy': 0,
      'reportedBy': 0,
      'source': 'user',
    });
    return doc.id;
  }

  static Future<void> confirm(String docId) async {
    await _db
        .collection(_col)
        .doc(docId)
        .update({'confirmedBy': FieldValue.increment(1)});
  }

  static Future<void> report(String docId) async {
    await _db
        .collection(_col)
        .doc(docId)
        .update({'reportedBy': FieldValue.increment(1)});
  }
}
