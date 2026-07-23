import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/widgets/map/blocked_sheet.dart';

// O caso que o Gilberto viveu: tocar na restrição não fazia nada. Este teste
// falha se o card parar de disparar onSelect com a restrição certa.
void main() {
  const r = BridgeRestriction(
      lat: -22.9, lng: -45.5, type: 'maxheight', value: 3.6, roadName: 'Dutra');

  Widget wrap({void Function(BridgeRestriction)? onSelect}) => MaterialApp(
        home: Scaffold(
          body: BlockedSheet(
              blocked: const [r], onAddWaypoint: () {}, onSelect: onSelect),
        ),
      );

  testWidgets('tocar no card dispara onSelect com a restrição', (tester) async {
    BridgeRestriction? picked;
    await tester.pumpWidget(wrap(onSelect: (x) => picked = x));
    expect(find.text('Ver no mapa'), findsOneWidget); // affordance visível
    await tester.tap(find.text('Altura máx. 3.6 m'));
    await tester.pump();
    expect(picked, same(r));
  });

  testWidgets('sem onSelect: sem affordance e tap inerte', (tester) async {
    await tester.pumpWidget(wrap(onSelect: null));
    expect(find.text('Ver no mapa'), findsNothing);
    await tester.tap(find.text('Altura máx. 3.6 m')); // não deve lançar
    await tester.pump();
  });
}
