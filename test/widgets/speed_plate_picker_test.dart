import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/widgets/speed_plate.dart';

// Guarda o pedido de campo do Gilberto (2026-07-13): ele passou por um radar de 40
// dentro da cidade e o mínimo que dava pra escolher era 60. Os presets cobriam
// rodovia e reprovaram na cidade. A placa EM BRANCO tem que deixar digitar qualquer
// velocidade — e o valor digitado tem que aparecer NA PLACA (ele lê num relance).
void main() {
  Widget montar({int? selected, required ValueChanged<int> onChanged}) =>
      MaterialApp(
        home: Scaffold(
          body: SpeedPlatePicker(selected: selected, onChanged: onChanged),
        ),
      );

  testWidgets('mostra os 4 presets + a placa em branco', (t) async {
    await t.pumpWidget(montar(onChanged: (_) {}));
    for (final s in SpeedPlatePicker.presets) {
      expect(find.text('$s'), findsOneWidget);
    }
    expect(find.text('···'), findsOneWidget, reason: 'a placa em branco');
    expect(find.byType(SpeedPlate), findsNWidgets(5));
  });

  testWidgets('tocar num preset devolve a velocidade', (t) async {
    int? escolhido;
    await t.pumpWidget(montar(onChanged: (s) => escolhido = s));
    await t.tap(find.text('90'));
    expect(escolhido, 90);
  });

  testWidgets('digitar 40 na placa em branco devolve 40', (t) async {
    int? escolhido;
    await t.pumpWidget(montar(onChanged: (s) => escolhido = s));
    await t.tap(find.text('···'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '40');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(escolhido, 40, reason: 'o radar de 40 da cidade — o caso do Gilberto');
  });

  testWidgets('velocidade digitada aparece NA placa (não fica em branco)', (t) async {
    await t.pumpWidget(montar(selected: 40, onChanged: (_) {}));
    expect(find.text('40'), findsOneWidget);
    expect(find.text('···'), findsNothing);
  });

  testWidgets('lixo digitado não vira radar (fora de 10-120 km/h)', (t) async {
    int? escolhido;
    await t.pumpWidget(montar(onChanged: (s) => escolhido = s));

    await t.tap(find.text('···'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '999');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(escolhido, isNull, reason: '999 km/h não existe em placa brasileira');

    await t.tap(find.text('···'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'abc');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(escolhido, isNull, reason: 'texto não numérico não pode virar velocidade');
  });

  testWidgets('cancelar não escolhe nada', (t) async {
    int? escolhido;
    await t.pumpWidget(montar(onChanged: (s) => escolhido = s));
    await t.tap(find.text('···'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '40');
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(escolhido, isNull);
  });
}
