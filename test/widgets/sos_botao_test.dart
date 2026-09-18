import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/sos_request.dart';
import 'package:truck_router/widgets/sos/sos_botao.dart';

void main() {
  final pedido = SosRequest(
    id: 'id1', uid: 'u1', nome: 'Pedro', caminhao: '', cor: '', tipo: SosTipo.pneu,
    texto: '', lat: -23.2, lng: -45.9, status: 'aberto',
    criadoEm: DateTime.now(), expireAt: DateTime.now().add(const Duration(hours: 1)),
  );

  Future<void> monta(WidgetTester t, {required bool aberto, int total = 1}) =>
      t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SosBotao(sos: pedido, distM: 7200, aberto: aberto, total: total, onTap: () {}))));

  testWidgets('chega aberto: diz quem pede, o que é e a quantos km', (t) async {
    await monta(t, aberto: true);
    expect(find.text('Pedro pede ajuda'), findsOneWidget);
    expect(find.text('Pneu · a 7 km'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
  });

  testWidgets('recolhido: só o SOS e os km, sem a descrição', (t) async {
    await monta(t, aberto: false);
    expect(find.text('Pedro pede ajuda'), findsNothing);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('7 km'), findsOneWidget);
  });

  testWidgets('mais de um pedido perto ganha o número', (t) async {
    await monta(t, aberto: false, total: 3);
    expect(find.text('3'), findsOneWidget);
  });
}
