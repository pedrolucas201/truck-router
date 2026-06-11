import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/police_alert.dart';

void main() {
  group('PoliceAlert.timeRemainingText', () {
    test('retorna minutos quando há tempo restante', () {
      final alert = PoliceAlert(
        type: PoliceAlertType.radar,
        lat: 0, lng: 0, uid: 'u1',
        createdAt: DateTime.now(),
        expireAt: DateTime.now().add(const Duration(minutes: 15, seconds: 30)),
      );
      expect(alert.timeRemainingText, '15min restantes');
    });

    test('retorna Expirando quando tempo zerado', () {
      final alert = PoliceAlert(
        type: PoliceAlertType.police,
        lat: 0, lng: 0, uid: 'u1',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        expireAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(alert.timeRemainingText, 'Expirando');
    });
  });
}
