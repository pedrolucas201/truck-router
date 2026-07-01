import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_result.dart';

RouteResult _route(List<SpeedLimitSpan> spans) => RouteResult(
      polylinePoints: const [LatLng(0, 0)],
      distanceMeters: 100,
      durationSeconds: 60,
      speedLimits: spans,
    );

void main() {
  group('RouteResult.limitAt', () {
    test('retorna o limite do trecho vigente (último offset <= idx)', () {
      final r = _route(const [
        SpeedLimitSpan(0, 40),
        SpeedLimitSpan(10, 80),
        SpeedLimitSpan(25, 90),
      ]);
      expect(r.limitAt(0), 40);
      expect(r.limitAt(9), 40);
      expect(r.limitAt(10), 80); // começa exatamente no offset
      expect(r.limitAt(24), 80);
      expect(r.limitAt(30), 90); // além do último span mantém o último limite
    });

    test('idx antes do primeiro offset conhecido devolve null', () {
      final r = _route(const [SpeedLimitSpan(5, 60)]);
      expect(r.limitAt(0), isNull);
      expect(r.limitAt(5), 60);
    });

    test('rota sem dados de limite devolve null (fallback fica no chamador)', () {
      final r = _route(const []);
      expect(r.limitAt(0), isNull);
      expect(r.maxTruckSpeedKmh, isNull);
    });

    test('maxTruckSpeedKmh é o maior limite da rota', () {
      final r = _route(const [
        SpeedLimitSpan(0, 40),
        SpeedLimitSpan(10, 90),
        SpeedLimitSpan(25, 80),
      ]);
      expect(r.maxTruckSpeedKmh, 90);
    });
  });

  group('TrafficLevel.fromRatio', () {
    test('classifica fluindo / lento / pesado nos limiares', () {
      expect(TrafficLevel.fromRatio(1.0), TrafficLevel.free);
      expect(TrafficLevel.fromRatio(0.85), TrafficLevel.free); // limiar inferior de free
      expect(TrafficLevel.fromRatio(0.84), TrafficLevel.slow);
      expect(TrafficLevel.fromRatio(0.5), TrafficLevel.slow);   // limiar inferior de slow
      expect(TrafficLevel.fromRatio(0.49), TrafficLevel.heavy);
      expect(TrafficLevel.fromRatio(0.1), TrafficLevel.heavy);
    });
  });
}
