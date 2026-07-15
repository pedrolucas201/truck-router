import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/radar_direction.dart';
import 'package:truck_router/services/radar_service.dart';
import 'package:truck_router/widgets/nav/nav_ui_defs.dart';

// Guarda a camada de direção (T2/T3 da MISSAO_RADAR). Invariante: direção nunca
// suprime alerta — o pior caso da classificação é esconder uma etiqueta.
void main() {
  group('parser retrocompatível (T3)', () {
    test('CSV antigo de 3 campos: 5 campos de enriquecimento ficam null', () {
      final r = RadarService.parseCsv('-46.5,-23.1,Radar Fixo - 30 kmh@30').single;
      expect(r.speedKmh, 30);
      expect(r.dir1, isNull);
      expect(r.dir2, isNull);
      expect(r.truckLimitOff, isNull);
    });

    test('CSV enriquecido: header é pulado; colunas viram campos', () {
      const csv =
          'longitude,latitude,desc,dir1,dir2,dir_src,status,truck_limit_off\n'
          '-46.5,-23.1,Radar Fixo - 100 kmh@100,51,231,antt,active,80\n'
          '-44.0,-22.5,Radar Fixo - 40 kmh@40,,,,,';
      final rs = RadarService.parseCsv(csv);
      expect(rs.length, 2); // header caiu fora
      expect(rs[0].dir1, 51);
      expect(rs[0].dir2, 231); // bidirecional
      expect(rs[0].dirSrc, 'antt');
      expect(rs[0].status, 'active');
      expect(rs[0].truckLimitOff, 80);
      expect(rs[1].dir1, isNull); // campos vazios => null
      expect(rs[1].truckLimitOff, isNull);
    });
  });

  group('truckRadarLimit com limite oficial (T3)', () {
    test('oficial ABAIXA o limite (100 postado, 80 oficial -> 80)', () {
      expect(truckRadarLimit(100, officialTruckLimit: 80), 80);
    });
    test('oficial NUNCA sobe (60 postado, 90 oficial -> 60)', () {
      expect(truckRadarLimit(60, officialTruckLimit: 90), 60);
    });
    test('oficial acima do teto de caminhão ainda capa em 90', () {
      expect(truckRadarLimit(110, officialTruckLimit: 110), 90);
    });
    test('sem oficial: comportamento antigo intacto', () {
      expect(truckRadarLimit(110), 90);
      expect(truckRadarLimit(60), 60);
      expect(truckRadarLimit(0), isNull);
    });
  });

  group('classifyRadarDirection (T2)', () {
    // Dutra: Crescente ~235 (RJ->SP). Motorista indo RJ->SP (heading ~235).
    test('mesmo sentido => same', () {
      expect(
          classifyRadarDirection(
              dir1: 235, dir2: null, dirSrc: 'antt', userHeading: 240),
          RadarDirMatch.same);
    });
    test('sentido oposto (unidirecional, folga) => opposite', () {
      expect(
          classifyRadarDirection(
              dir1: 235, dir2: null, dirSrc: 'antt', userHeading: 55),
          RadarDirMatch.opposite);
    });
    test('bidirecional casa qualquer sentido => same', () {
      expect(
          classifyRadarDirection(
              dir1: 51, dir2: 231, dirSrc: 'antt', userHeading: 235),
          RadarDirMatch.same);
    });
    test('sem dado => unknown (alerta pleno)', () {
      expect(
          classifyRadarDirection(
              dir1: null, dir2: null, dirSrc: null, userHeading: 100),
          RadarDirMatch.unknown);
    });
    test('heading inválido (GPS parado) => unknown', () {
      expect(
          classifyRadarDirection(
              dir1: 235, dir2: null, dirSrc: 'antt', userHeading: -1),
          RadarDirMatch.unknown);
    });
    test('zona morta (110°) => unknown, nunca opposite', () {
      expect(
          classifyRadarDirection(
              dir1: 0, dir2: null, dirSrc: 'antt', userHeading: 110),
          RadarDirMatch.unknown);
    });
    test('accuracy ruim (>45°) => unknown', () {
      expect(
          classifyRadarDirection(
              dir1: 235,
              dir2: null,
              dirSrc: 'antt',
              userHeading: 55,
              headingAccuracy: 60),
          RadarDirMatch.unknown);
    });
  });

  group('RadarPassEvent.toMap normaliza pro range da regra (T6)', () {
    RadarPassEvent ev(double h, double v) => RadarPassEvent(
        radarId: 'x', heading: h, speedKmh: v, ts: DateTime.utc(2026));
    test('heading 359.6 => h == 0 (nunca 360, senão derruba o WriteBatch)', () {
      expect(ev(359.6, 80).toMap()['h'], 0);
    });
    test('heading 360.0 => h == 0', () {
      expect(ev(360.0, 80).toMap()['h'], 0);
    });
    test('heading normal preserva (235.4 => 235)', () {
      expect(ev(235.4, 80).toMap()['h'], 235);
    });
    test('v 250 => 200 (teto de sanidade da regra)', () {
      expect(ev(90, 250).toMap()['v'], 200);
    });
    test('v normal preserva (82.7 => 83)', () {
      expect(ev(90, 82.7).toMap()['v'], 83);
    });
  });

  group('aggregateHeadings (T7 ref)', () {
    test('concentrado unidirecional => promove dir1, sem dir2', () {
      final h = List<double>.filled(12, 235.0);
      final b = aggregateHeadings(h);
      expect(b.promoted, isTrue);
      expect(b.dir1, closeTo(235, 1));
      expect(b.dir2, isNull);
    });
    test('dois clusters opostos => bidirecional (dir1 e dir1+180)', () {
      final h = [for (var i = 0; i < 6; i++) 55.0, for (var i = 0; i < 6; i++) 235.0];
      final b = aggregateHeadings(h);
      expect(b.dir2, isNotNull);
      expect(angleDiff(b.dir1!, b.dir2!), closeTo(180, 2));
    });
    test('poucas amostras => não promove', () {
      expect(aggregateHeadings([235, 236, 234]).promoted, isFalse);
    });
  });
}
