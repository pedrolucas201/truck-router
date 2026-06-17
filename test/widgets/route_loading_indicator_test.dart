import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/widgets/route_loading_indicator.dart';

void main() {
  testWidgets('renderiza o texto e assenta com reduce motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: RouteLoadingIndicator(
                truckAsset: 'assets/loader/truck_carreta.svg',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Calculando rota…'), findsOneWidget);
    // Com reduce motion não há ticker infinito: pumpAndSettle retorna.
    await tester.pumpAndSettle();
    expect(find.text('Calculando rota…'), findsOneWidget);
  });

  testWidgets('monta sem erro com animação ligada', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RouteLoadingIndicator(
              truckAsset: 'assets/loader/truck_bau.svg',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Calculando rota…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500)); // alguns frames
    expect(tester.takeException(), isNull);
  });
}
