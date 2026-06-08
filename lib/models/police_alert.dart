import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum PoliceAlertType { radar, police, blitz }

class PoliceAlert {
  final String? id;
  final PoliceAlertType type;
  final double lat;
  final double lng;
  final String uid;
  final DateTime createdAt;
  final DateTime expireAt;
  final int confirmations;
  final int notThereCount;

  const PoliceAlert({
    this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.uid,
    required this.createdAt,
    required this.expireAt,
    this.confirmations = 0,
    this.notThereCount = 0,
  });

  LatLng get position => LatLng(lat, lng);

  Duration get timeRemaining {
    final r = expireAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  String get timeRemainingText {
    final m = timeRemaining.inMinutes;
    if (m <= 0) return 'Expirando';
    return '${m}min restantes';
  }

  factory PoliceAlert.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PoliceAlert(
      id: doc.id,
      type: PoliceAlertType.values.firstWhere(
        (e) => e.name == (d['type'] as String? ?? 'police'),
        orElse: () => PoliceAlertType.police,
      ),
      lat: (d['lat'] as num).toDouble(),
      lng: (d['lng'] as num).toDouble(),
      uid: d['uid'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      expireAt: (d['expireAt'] as Timestamp).toDate(),
      confirmations: (d['confirmations'] as num?)?.toInt() ?? 0,
      notThereCount: (d['notThereCount'] as num?)?.toInt() ?? 0,
    );
  }
}
