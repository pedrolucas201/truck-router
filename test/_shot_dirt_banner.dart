// Ferramenta de inspeção visual: gera test/dirt_banner.png com o aviso de
// estrada de terra renderizado, pra conferir sem device.
//
//   flutter test test/_shot_dirt_banner.dart --update-goldens
//
// NÃO entra na suíte: `flutter test` só coleta arquivos `*_test.dart`. É de
// propósito — golden depende de fonte instalada na máquina e quebraria em outro
// PC. A garantia de comportamento mora em widgets/dirt_road_banner_test.dart,
// que testa o TEXTO e não os pixels.
// O caminho do SDK abaixo é da máquina do Pedro; noutra, avisa e sai com caixinha.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/services/here_routing_service.dart';
import 'package:truck_router/widgets/map/result_card.dart';

List<LatLng> _pontos(int n) =>
    List.generate(n, (i) => LatLng(-23.19 + i * 0.0001, -45.72 + i * 0.0001));

DirtSpan _sp(int o, {bool dirt = false, int meters = 0}) =>
    (offset: o, dirt: dirt, meters: meters);

Future<void> _carrega(String familia, List<String> caminhos) async {
  for (final p in caminhos) {
    final file = File(p);
    if (!file.existsSync()) continue;
    await (FontLoader(familia)
          ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
        .load();
    return;
  }
  // ignore: avoid_print
  print('AVISO: fonte $familia nao encontrada, vai sair como caixinha');
}

Future<void> _carregaFonte() async {
  await _carrega('Roboto', [
    r'C:\src\flutter\bin\cache\artifacts\material_fonts\roboto-regular.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    r'C:\Windows\Fonts\segoeui.ttf',
  ]);
  // Sem isto o Icons.terrain vira um quadrado vazio: o glifo mora na
  // MaterialIcons, que o harness de teste nao carrega sozinho.
  await _carrega('MaterialIcons', [
    r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
  ]);
}

void main() {
  testWidgets('shot', (t) async {
    await _carregaFonte();

    final pts = _pontos(340);
    final rotaLonga = RouteResult(
      polylinePoints: pts,
      distanceMeters: 11754,
      durationSeconds: 1200,
      maneuvers: const [],
      dirtSegments: HereRoutingService.groupDirtSpans([
        _sp(0, meters: 29), _sp(1, meters: 306), _sp(14, meters: 672),
        _sp(46, dirt: true, meters: 238), _sp(54, dirt: true, meters: 41),
        _sp(55, dirt: true, meters: 39), _sp(56, meters: 293),
        _sp(68, meters: 115), _sp(71, meters: 10), _sp(72, meters: 1480),
        _sp(105, meters: 1690), _sp(152, meters: 1257), _sp(193, meters: 260),
        _sp(203, meters: 465), _sp(216, meters: 84), _sp(218, meters: 1205),
        _sp(248, meters: 29), _sp(252, dirt: true, meters: 960),
        _sp(273, dirt: true, meters: 1931), _sp(324, dirt: true, meters: 501),
        _sp(330, dirt: true, meters: 149),
      ], pts),
    );

    final ptsCurta = _pontos(60);
    final rotaCurta = RouteResult(
      polylinePoints: ptsCurta,
      distanceMeters: 3051,
      durationSeconds: 463,
      maneuvers: const [],
      dirtSegments: HereRoutingService.groupDirtSpans(
          [_sp(0), _sp(10, dirt: true, meters: 881), _sp(50)], ptsCurta),
    );

    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        backgroundColor: const Color(0xFFEFEFEF),
        body: Center(
          child: RepaintBoundary(
            child: Container(
              width: 400,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DirtRoadBanner(result: rotaLonga),
                const SizedBox(height: 10),
                DirtRoadBanner(result: rotaCurta),
              ]),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    await expectLater(
        find.byType(RepaintBoundary).first, matchesGoldenFile('dirt_banner.png'));
  });
}
