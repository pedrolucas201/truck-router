// Ferramenta de inspeção visual: gera test/swap_popup.png com o popup de troca
// de destino (link recebido em navegação), pra conferir sem device.
//
//   flutter test test/_shot_swap_popup.dart --update-goldens
//
// NÃO entra na suíte: `flutter test` só coleta arquivos `*_test.dart`. É de
// propósito — golden depende de fonte instalada na máquina e quebraria em outro
// PC. O markup abaixo é uma CÓPIA do AlertDialog de _showSwapOffer
// (navigation_screen.dart) com labels realistas no lugar dos futures.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  testWidgets('shot', (t) async {
    await _carrega('Roboto', [
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\roboto-regular.ttf',
      r'C:\Windows\Fonts\arial.ttf',
      r'C:\Windows\Fonts\segoeui.ttf',
    ]);

    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      // Mesmo seed do app (main.dart): o botão sai na cor real, não no roxo M3.
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
        useMaterial3: true,
      ),
      home: Scaffold(
        // Fundo escuro fazendo as vezes do mapa da navegação por trás.
        backgroundColor: const Color(0xFF263238),
        body: Center(
          child: RepaintBoundary(
            child: Container(
              width: 400,
              height: 400,
              alignment: Alignment.center,
              color: const Color(0xFF37474F),
              child: AlertDialog(
                title: const Text('Nova localização recebida'),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: 'De: ', style: TextStyle(color: Colors.grey)),
                      TextSpan(
                          text: 'R. Quinze de Novembro, 830 - Centro, Lorena - SP'),
                    ])),
                    SizedBox(height: 8),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: 'Para: ', style: TextStyle(color: Colors.grey)),
                      TextSpan(
                        text:
                            'Av. Andrômeda, 2000 - Jardim Satélite, São José dos Campos - SP',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ])),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Descartar')),
                  FilledButton(onPressed: () {}, child: const Text('Alterar rota')),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    await expectLater(
        find.byType(RepaintBoundary).first, matchesGoldenFile('swap_popup.png'));
  });
}
