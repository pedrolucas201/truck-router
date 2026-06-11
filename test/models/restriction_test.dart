import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/user_restriction.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/models/truck_profile.dart';

void main() {
  group('truck_ban type', () {
    test('UserRestriction.fullLabel retorna texto correto para truck_ban', () {
      final r = UserRestriction(
        lat: 0, lng: 0, type: 'truck_ban', value: 0,
        createdAt: DateTime.now(),
      );
      expect(r.fullLabel, 'Proibido caminhões');
    });

    test('BridgeRestriction.label retorna texto correto para truck_ban', () {
      const r = BridgeRestriction(lat: 0, lng: 0, type: 'truck_ban', value: 0);
      expect(r.label, 'Proibido caminhões');
    });

    test('BridgeRestriction.conflictsWith retorna true para truck_ban', () {
      const r = BridgeRestriction(lat: 0, lng: 0, type: 'truck_ban', value: 0);
      const truck = TruckProfile(id: 't1', name: 'Teste', heightCm: 420, lengthCm: 1400, widthCm: 260, weightKg: 25000);
      expect(r.conflictsWith(truck), isTrue);
    });
  });
}
