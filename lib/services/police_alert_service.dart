import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/police_alert.dart';

class PoliceAlertService {
  static final _col = FirebaseFirestore.instance.collection('police_alerts');

  static Stream<List<PoliceAlert>> streamInBounds(
    double minLat, double maxLat, double minLng, double maxLng,
  ) {
    final now = Timestamp.now();
    return _col
        .where('lat', isGreaterThanOrEqualTo: minLat)
        .where('lat', isLessThanOrEqualTo: maxLat)
        .where('expireAt', isGreaterThan: now)
        .snapshots()
        .map((snap) => snap.docs
            .map(PoliceAlert.fromFirestore)
            .where((a) => a.lng >= minLng && a.lng <= maxLng)
            .toList());
  }

  static Future<void> report({
    required PoliceAlertType type,
    required double lat,
    required double lng,
    required String uid,
  }) async {
    final now = DateTime.now();
    await _col.add({
      'type': type.name,
      'lat': lat,
      'lng': lng,
      'uid': uid,
      'createdAt': Timestamp.fromDate(now),
      'expireAt': Timestamp.fromDate(now.add(const Duration(minutes: 30))),
      'confirmations': 0,
      'notThereCount': 0,
    });
  }

  static Future<void> confirm(String id) async {
    final ref = _col.doc(id);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap['expireAt'] as Timestamp).toDate();
      tx.update(ref, {
        'confirmations': FieldValue.increment(1),
        'expireAt': Timestamp.fromDate(
          current.add(const Duration(minutes: 15)),
        ),
      });
    });
  }

  static Future<void> notThere(String id) async {
    final ref = _col.doc(id);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final count = (snap['notThereCount'] as num).toInt() + 1;
      if (count >= 3) {
        tx.update(ref, {
          'notThereCount': count,
          'expireAt': Timestamp.now(),
        });
      } else {
        tx.update(ref, {'notThereCount': count});
      }
    });
  }
}
