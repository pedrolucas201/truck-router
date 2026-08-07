import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/services/here_routing_service.dart';

// Fixture medida na rota REAL do relato (06/08, Gilberto): a HERE devolveu 4
// spans marcados dirtRoad para o que é, no chão, 2 estradas — ela quebra o span
// a cada mudança de atributo, não a cada mudança de pavimento.
//   offset 587 |  960 m | Estrada Municipal Tijuco Preto
//   offset 608 | 1931 m | (sem nome)          <- contíguo ao anterior
//   offset 659 |  501 m | Rua Mariano Moreira de Toledo
//   offset 665 |  149 m | (sem nome)          <- contíguo ao anterior

List<LatLng> _linha(int n) =>
    List.generate(n, (i) => LatLng(-23.0 - i * 0.0001, -45.6));

DirtSpan _sp(int offset, {bool dirt = false, int meters = 0}) =>
    (offset: offset, dirt: dirt, meters: meters);

void main() {
  group('groupDirtSpans', () {
    test('spans de terra contíguos viram UM trecho, somando os metros', () {
      final segs = HereRoutingService.groupDirtSpans([
        _sp(0),
        _sp(10, dirt: true, meters: 960),
        _sp(20, dirt: true, meters: 1931),
        _sp(30),
      ], _linha(40));

      expect(segs.length, 1, reason: 'uma estrada só, não dois trechos');
      expect(segs.first.meters, 2891);
      // Início do trecho, não o meio: é onde ele precisa ser avisado.
      expect(segs.first.position, _linha(40)[10]);
    });

    test('trechos separados por asfalto continuam separados', () {
      final segs = HereRoutingService.groupDirtSpans([
        _sp(10, dirt: true, meters: 960),
        _sp(20, dirt: true, meters: 1931),
        _sp(30), // asfalto no meio
        _sp(40, dirt: true, meters: 501),
        _sp(50, dirt: true, meters: 149),
      ], _linha(60));

      expect(segs.length, 2);
      expect(segs[0].meters, 2891);
      expect(segs[1].meters, 650);
      expect(segs[1].position, _linha(60)[40]);
    });

    test('rota que TERMINA na terra fecha o trecho (destino em estrada rural)', () {
      // Sem o fecho final este trecho sumia — e é justamente o caso que mais
      // precisa do aviso: o destino fica na terra.
      final segs = HereRoutingService.groupDirtSpans([
        _sp(0),
        _sp(10, dirt: true, meters: 789),
      ], _linha(20));

      expect(segs.length, 1);
      expect(segs.single.meters, 789);
    });

    test('rota toda asfaltada não gera trecho nenhum', () {
      final segs = HereRoutingService.groupDirtSpans(
          [_sp(0), _sp(10), _sp(20)], _linha(30));
      expect(segs, isEmpty);
    });

    test('offset além da polyline cai no último ponto em vez de estourar', () {
      final segs = HereRoutingService.groupDirtSpans(
          [_sp(999, dirt: true, meters: 100)], _linha(5));
      expect(segs.single.position, _linha(5).last);
    });

    test('polyline vazia não quebra', () {
      expect(HereRoutingService.groupDirtSpans([_sp(0, dirt: true)], const []),
          isEmpty);
    });
  });

  group('RouteResult.dirtText', () {
    test('abaixo de 1 km sai em metros', () {
      const r = RouteResult(
        polylinePoints: [],
        distanceMeters: 3051,
        durationSeconds: 463,
        dirtSegments: [DirtRoadSegment(LatLng(-23.0, -45.6), 881)],
      );
      expect(r.dirtMeters, 881);
      expect(r.dirtText, '881 m');
    });

    test('acima de 1 km sai em km com vírgula decimal', () {
      const r = RouteResult(
        polylinePoints: [],
        distanceMeters: 39602,
        durationSeconds: 2954,
        dirtSegments: [
          DirtRoadSegment(LatLng(-23.0, -45.6), 2891),
          DirtRoadSegment(LatLng(-23.1, -45.6), 650),
        ],
      );
      expect(r.dirtMeters, 3541); // total medido na rota real
      expect(r.dirtText, '3,5 km');
    });

    test('rota sem terra não reporta nada', () {
      const r = RouteResult(
          polylinePoints: [], distanceMeters: 100, durationSeconds: 10);
      expect(r.dirtMeters, 0);
      expect(r.dirtSegments, isEmpty);
    });
  });
}
