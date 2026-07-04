import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/police_alert.dart';
import 'field_log.dart';

class PoliceAlertService {
  static final _col = FirebaseFirestore.instance.collection('police_alerts');

  static Stream<List<PoliceAlert>> streamInBounds(
    double minLat, double maxLat, double minLng, double maxLng,
  ) {
    final now = Timestamp.now();
    // UM range só no servidor (expireAt). Dois ranges em campos diferentes (lat E
    // expireAt) exigiam índice composto que NUNCA foi criado → o stream falhava em
    // loop (failed-precondition), o alerta de polícia não funcionava e inundava o
    // field_logs (974 erros numa sessão). A coleção é minúscula (TTL 30min,
    // crowd-source), então filtrar lat/lng no cliente é barato e dispensa índice.
    return _col
        .where('expireAt', isGreaterThan: now)
        .snapshots()
        .map((snap) => snap.docs
            .map(PoliceAlert.fromFirestore)
            .where((a) =>
                a.lat >= minLat && a.lat <= maxLat &&
                a.lng >= minLng && a.lng <= maxLng)
            .toList())
        // Sem isto, erro do Firestore ou doc malformado (fromFirestore) mata o
        // stream sem sinal. handleError loga e deixa o stream seguir.
        .handleError((Object e, StackTrace st) => FieldLog.error('police_stream', e, st));
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
