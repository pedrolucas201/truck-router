import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/widgets/map/result_card.dart';

// Card de preview: o motorista vê quantas praças e quanto custa ANTES de sair.
void main() {
  testWidgets('mostra contagem e total das praças', (t) async {
    const r = RouteResult(
      polylinePoints: [LatLng(0, 0)],
      distanceMeters: 0,
      durationSeconds: 0,
      tolls: [
        TollPlaza('Jacareí', LatLng(0, 0), priceBrl: 40.5),
        TollPlaza('Guararema', LatLng(0, 0), priceBrl: 28.5),
      ],
    );
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: TollBanner(result: r))));
    expect(find.text('2 pedágios · R\$ 69,00 na rota'), findsOneWidget);
    expect(find.byIcon(Icons.toll), findsOneWidget);
  });
}
