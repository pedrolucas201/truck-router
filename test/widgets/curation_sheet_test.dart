import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/widgets/curation_sheet.dart';
import 'package:truck_router/widgets/speed_plate.dart';

// Pedágio não tem placa: a folha não pode oferecer 60/70/80/90 numa praça
// (foi assim que nasceu um "não existe" em Jacareí, 13/07). Radar segue igual.
void main() {
  Widget montar(RadarPoint r) =>
      MaterialApp(home: Scaffold(body: CurationSheet(radar: r)));

  testWidgets('radar: chips de velocidade + existe/não existe', (t) async {
    await t.pumpWidget(montar(const RadarPoint(
        lat: 0, lng: 0, type: 'Radar Fixo - 90 kmh', speedKmh: 90)));
    expect(find.byType(SpeedPlate), findsNWidgets(4));
    expect(find.text('Radar 90 km/h'), findsOneWidget);
    expect(find.text('Existe (manter velocidade)'), findsOneWidget);
    expect(find.text('Não existe aqui'), findsOneWidget);
  });

  testWidgets('pedágio: sem chips, nome da praça, só existe/não existe',
      (t) async {
    await t.pumpWidget(montar(const RadarPoint(
        lat: 0, lng: 0, type: 'Pedagio', speedKmh: 0, name: 'Jacareí')));
    expect(find.byType(SpeedPlate), findsNothing);
    expect(find.text('Pedágio Jacareí'), findsOneWidget);
    expect(find.text('Existe'), findsOneWidget);
    expect(find.text('Não existe aqui'), findsOneWidget);
    expect(find.byIcon(Icons.toll), findsOneWidget);
  });

  testWidgets('pedágio do CSV (sem nome) mostra só Pedágio', (t) async {
    await t.pumpWidget(montar(
        const RadarPoint(lat: 0, lng: 0, type: 'Pedagio', speedKmh: 0)));
    expect(find.text('Pedágio'), findsOneWidget);
    expect(find.byType(SpeedPlate), findsNothing);
  });

  testWidgets('as respostas saem pelo pop da folha', (t) async {
    String? out;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              out = await showCurationSheet(
                  ctx,
                  const RadarPoint(
                      lat: 0, lng: 0, type: 'Pedagio', speedKmh: 0));
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Não existe aqui'));
    await t.pumpAndSettle();
    expect(out, 'remove');
  });
}
