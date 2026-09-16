import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/services/radar_direction.dart';
import 'package:truck_router/widgets/curation_sheet.dart';

// Guarda da release de 16/09 (etiqueta "pista oposta" no asset, voz intacta):
// da pista OPOSTA não pode existir "não existe" — ele apagaria o radar também
// no sentido em que ele é real (9 dos 53 "não existe" do histórico vieram só
// da pista contrária). E toda passagem grava o LADO, senão o crowd é bimodal.
void main() {
  const radar = RadarPoint(
    lat: -23.0, lng: -46.0, type: 'Radar Fixo', speedKmh: 80, source: 'csv',
    dir1: 60, dirSrc: 'osm_geom',
  );

  testWidgets('folha com canRemove=false não oferece "Não existe aqui"', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: CurationSheet(radar: radar, canRemove: false))));
    expect(find.text('Não existe aqui'), findsNothing);
    expect(find.text('Radar da outra pista'), findsOneWidget);
    expect(find.text('Existe (manter velocidade)'), findsOneWidget);
  });

  testWidgets('folha padrão continua com "Não existe aqui"', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: CurationSheet(radar: radar))));
    expect(find.text('Não existe aqui'), findsOneWidget);
  });

  test('heading oposto ao dir1 do osm_geom classifica opposite (o que esconde o NÃO)', () {
    expect(
      classifyRadarDirection(dir1: 60, dir2: null, dirSrc: 'osm_geom', userHeading: 240),
      RadarDirMatch.opposite,
    );
    expect(
      classifyRadarDirection(dir1: 60, dir2: null, dirSrc: 'osm_geom', userHeading: 65),
      RadarDirMatch.same,
    );
  });

  test('radar_pass grava o lado da passagem', () async {
    final batches = <List<Map<String, dynamic>>>[];
    final logger = RadarPassLogger(flush: (b) async => batches.add(b), batchSize: 1);
    logger.onRadarCrossed(radarId: 'a', heading: 240, speedKmh: 70, side: 'opposite');
    logger.onRadarCrossed(radarId: 'b', heading: 65, speedKmh: 70);
    await logger.endTrip();
    expect(batches.expand((b) => b).map((m) => m['side']), ['opposite', 'unknown']);
    // a regra do Firestore só aceita esses três valores
    for (final m in batches.expand((b) => b)) {
      expect(['same', 'opposite', 'unknown'], contains(m['side']));
    }
  });
}
