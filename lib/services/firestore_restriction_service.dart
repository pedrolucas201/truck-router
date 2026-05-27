import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import '../models/user_restriction.dart';
import 'radar_service.dart';

class FirestoreRestrictionService {
  static final _db = FirebaseFirestore.instance;
  static const _col = 'restrictions';
  static const _corridorM = 80.0;

  // Busca restrições num bounding box ao redor da rota.
  // Filtra lat via Firestore; lng filtrado client-side (limitação do Firestore).
  static Future<List<BridgeRestriction>> fetchNearRoute(
      List<LatLng> points) async {
    if (points.isEmpty) return [];

    double minLat = points[0].latitude, maxLat = points[0].latitude;
    double minLng = points[0].longitude, maxLng = points[0].longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
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
              _isNearRoute(r.lat, r.lng, points))
          .toList();
    } catch (_) {
      return [];
    }
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

  static BridgeRestriction _fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BridgeRestriction(
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
