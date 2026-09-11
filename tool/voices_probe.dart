// Sonda de vozes: roda no aparelho (`flutter run -t tool/voices_probe.dart`),
// lista as vozes pt do TTS e sintetiza a mesma frase em cada uma pra arquivo,
// em <external files>/voices/. Depois: `adb pull` e análise de F0 no PC.
// Não faz parte do app; entrypoint separado.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _frase = 'Em duzentos metros, vire à direita. Radar a quinhentos metros, limite de oitenta.';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Probe()));
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _log = <String>[];
  @override
  void initState() {
    super.initState();
    _run();
  }

  void _p(String s) {
    debugPrint('PROBE $s');
    setState(() => _log.add(s));
  }

  Future<void> _run() async {
    final tts = FlutterTts();
    // Pasta externa do app (sem permissão extra; `adb pull` alcança).
    final dir = Directory('/storage/emulated/0/Android/data/com.truckrouter.truck_router/files/voices');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final engine = await tts.getDefaultEngine;
    final raw = await tts.getVoices;
    final voices = <Map<String, dynamic>>[];
    for (final v in (raw as List)) {
      if (v is! Map) continue;
      final m = v.map((k, val) => MapEntry('$k', val));
      if ('${m['locale']}'.toLowerCase().startsWith('pt')) voices.add(m);
    }
    _p('engine=$engine total=${(raw).length} pt=${voices.length}');
    await tts.setLanguage('pt-BR');
    await tts.setSpeechRate(0.5);
    await tts.awaitSynthCompletion(true);
    var i = 0;
    for (final v in voices) {
      i++;
      final name = '${v['name']}';
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      try {
        await tts.setVoice({'name': name, 'locale': '${v['locale']}'});
        // flutter_tts grava em <external files>/<fileName> no Android.
        final r = await tts.synthesizeToFile(_frase, '${dir.path}/$safe.wav', true);
        _p('$i/${voices.length} $name -> $r');
      } catch (e) {
        _p('$i/${voices.length} $name ERRO $e');
      }
    }
    File('${dir.path}/voices.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({'engine': engine, 'voices': voices}));
    _p('FIM ${dir.path}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(children: [for (final l in _log) Text(l)]),
      );
}
