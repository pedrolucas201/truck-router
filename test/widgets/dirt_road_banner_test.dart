import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/services/here_routing_service.dart';
import 'package:truck_router/widgets/map/result_card.dart';

/// Prova de ponta a ponta do aviso de estrada de terra: spans REAIS da HERE
/// entram, e sai o texto que o motorista lê na tela.
///
/// Os 21 spans abaixo foram medidos na chave real em 10/08/2026, rota de
/// caminhão `-23.1900,-45.7200` → `-23.1657052,-45.6931100` (11.754 m), a mesma
/// região do caso que o Gilberto reportou em 06/08. A chamada levava
/// `avoid[features]=dirtRoad` e a HERE entregou a terra assim mesmo, sem notice
/// nenhum — é exatamente por isso que o app lê o span em vez de confiar no avoid.
///
/// A rota tem os dois formatos que importam: um trecho curto no começo e um
/// longo no fim, e o ÚLTIMO span é de terra — ou seja, o destino fica na estrada
/// de chão, que é o caso que mais precisa do aviso.
List<LatLng> _pontos(int n) =>
    List.generate(n, (i) => LatLng(-23.19 + i * 0.0001, -45.72 + i * 0.0001));

DirtSpan _sp(int offset, {bool dirt = false, int meters = 0}) =>
    (offset: offset, dirt: dirt, meters: meters);

final _spansReais = <DirtSpan>[
  _sp(0, meters: 29), // Rua José dos Santos
  _sp(1, meters: 306), // Rua Francisco Medeiros
  _sp(14, meters: 672), // Rua Francisco José de Assis
  _sp(46, dirt: true, meters: 238), // Rua Francisco José de Assis   TERRA
  _sp(54, dirt: true, meters: 41), // Rua Benedito de Andrade        TERRA
  _sp(55, dirt: true, meters: 39), // Praça Luís Galdini             TERRA
  _sp(56, meters: 293),
  _sp(68, meters: 115),
  _sp(71, meters: 10), // Rodovia João do Amaral Gurgel
  _sp(72, meters: 1480),
  _sp(105, meters: 1690),
  _sp(152, meters: 1257),
  _sp(193, meters: 260),
  _sp(203, meters: 465),
  _sp(216, meters: 84), // Rua Sn
  _sp(218, meters: 1205), // Estrada João Borsoi
  _sp(248, meters: 29),
  _sp(252, dirt: true, meters: 960), // Estrada Municipal Tijuco Preto TERRA
  _sp(273, dirt: true, meters: 1931), // (sem nome)                    TERRA
  _sp(324, dirt: true, meters: 501), // Rua Mariano Moreira de Toledo  TERRA
  _sp(330, dirt: true, meters: 149), // (sem nome)                     TERRA
];

void main() {
  testWidgets('rota real da HERE vira o aviso que o motorista lê', (t) async {
    final pontos = _pontos(340);
    final segmentos = HereRoutingService.groupDirtSpans(_spansReais, pontos);

    // 7 spans de terra viram 2 trechos: a HERE quebra o span a cada mudança de
    // atributo (nome, ponte), não de pavimento. Sem agrupar, o motorista leria
    // "em 7 trechos" para o que são duas estradas.
    expect(segmentos.length, 2);
    expect(segmentos[0].meters, 318); // 238 + 41 + 39
    expect(segmentos[1].meters, 3541); // 960 + 1931 + 501 + 149

    final rota = RouteResult(
      polylinePoints: pontos,
      distanceMeters: 11754,
      durationSeconds: 1200,
      maneuvers: const [],
      dirtSegments: segmentos,
    );
    expect(rota.dirtMeters, 3859);
    expect(rota.dirtText, '3,9 km');

    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: DirtRoadBanner(result: rota)),
    ));

    // O que aparece na tela, antes de ele sair:
    expect(find.text('3,9 km de estrada de terra na rota, em 2 trechos'),
        findsOneWidget);
    expect(find.byIcon(Icons.terrain), findsOneWidget);

    debugPrint('[BANNER] ${(t.widget(find.byType(Text)) as Text).data}');
  });

  testWidgets('um trecho só não diz "em N trechos"', (t) async {
    final pontos = _pontos(60);
    final rota = RouteResult(
      polylinePoints: pontos,
      distanceMeters: 5000,
      durationSeconds: 600,
      maneuvers: const [],
      dirtSegments: HereRoutingService.groupDirtSpans([
        _sp(0),
        _sp(10, dirt: true, meters: 881), // a rota que ele testou em 06/08
        _sp(50),
      ], pontos),
    );

    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: DirtRoadBanner(result: rota)),
    ));

    expect(find.text('881 m de estrada de terra na rota'), findsOneWidget);
    debugPrint('[BANNER] ${(t.widget(find.byType(Text)) as Text).data}');
  });
}
