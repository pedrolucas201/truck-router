import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'field_log.dart';

/// Voz do guia escolhida pelo motorista. Padrão = voz default do engine —
/// quem nunca mexeu aqui não muda de comportamento em nada.
///
/// Os tons E.T./Robô (pitch) foram CORTADOS em 2026-08-18 a pedido do Pedro:
/// pitch de TTS tem teto de qualidade baixo e reprovou de ouvido (1.7/0.7 e
/// depois 1.4/0.8). Voz de personagem de verdade = DSP pós-síntese
/// (synthesizeToFile + ring modulator), spec à parte se um dia valer o risco
/// no subsistema de voz. A chave antiga 'tts_voice_tone' fica órfã no
/// SharedPreferences de quem instalou a v2.4.50 — inofensiva, ninguém lê.
class VoiceSettings {
  static const _kName   = 'tts_voice_name';
  static const _kLocale = 'tts_voice_locale';

  static Future<({String? name, String? locale})> load() async {
    final p = await SharedPreferences.getInstance();
    return (name: p.getString(_kName), locale: p.getString(_kLocale));
  }

  static Future<void> save({String? name, String? locale}) async {
    final p = await SharedPreferences.getInstance();
    if (name == null) {
      await p.remove(_kName);
      await p.remove(_kLocale);
    } else {
      await p.setString(_kName, name);
      await p.setString(_kLocale, locale ?? 'pt-BR');
    }
  }

  /// Aplica a escolha salva numa instância de TTS. Falha aqui nunca cala a
  /// navegação: voz salva que sumiu (update/troca de engine) devolve 0 no
  /// setVoice, o engine segue na default e fica o rastro.
  static Future<void> apply(FlutterTts tts) async {
    try {
      final s = await load();
      if (s.name == null) return;
      final ok =
          await tts.setVoice({'name': s.name!, 'locale': s.locale ?? 'pt-BR'});
      if (ok != 1) FieldLog.event('tts_voice_fallback', {'voice': s.name!});
    } catch (e, st) {
      FieldLog.error('tts_voice_apply', e, st);
    }
  }

  /// Filtra o retorno cru do getVoices para as vozes em português do aparelho,
  /// pt-BR primeiro, ordem estável — é ela que numera "Voz 1..N" na tela.
  ///
  /// O Google TTS lista cada voz DUAS vezes: `...-local` (sintetiza no
  /// aparelho) e `...-network` (no servidor). Era o "milhão de vozes iguais"
  /// da tela — colapsamos o par preferindo a -local, que fala sem internet
  /// (voz que some em zona morta de sinal não serve pra caminhão).
  static List<Map<String, String>> ptVoices(dynamic rawVoices) {
    if (rawVoices is! List) return const [];
    final byBase = <String, Map<String, String>>{};
    for (final v in rawVoices) {
      if (v is! Map) continue;
      final name   = '${v['name'] ?? ''}';
      final locale = '${v['locale'] ?? ''}';
      if (name.isEmpty || !locale.toLowerCase().startsWith('pt')) continue;
      final base = name.replaceFirst(RegExp(r'-(local|network)$'), '');
      final atual = byBase[base];
      if (atual == null || name.endsWith('-local')) {
        byBase[base] = {'name': name, 'locale': locale};
      }
    }
    // `pt-BR-language` / `pt-PT-language` são ALIASES da primeira voz `x-` do
    // idioma (medido no Redmi do Pedro, 10/09: espectro idêntico, 1.000). Se o
    // idioma tem voz `x-`, o alias é a "voz repetida" que o Gilberto vê.
    final locaisComX = byBase.values
        .where((v) => v['name']!.contains('-x-'))
        .map((v) => v['locale']!.toLowerCase())
        .toSet();
    byBase.removeWhere((base, v) =>
        base.endsWith('-language') && locaisComX.contains(v['locale']!.toLowerCase()));
    final out = byBase.values.toList();
    out.sort((a, b) {
      final aBr = a['locale']!.toLowerCase() == 'pt-br' ? 0 : 1;
      final bBr = b['locale']!.toLowerCase() == 'pt-br' ? 0 : 1;
      return aBr != bBr ? aBr - bBr : a['name']!.compareTo(b['name']!);
    });
    return out;
  }
}

/// Nome de gente pra cada voz do Google TTS, por id. Gênero MEDIDO no áudio
/// (F0: afs 258 Hz, pte 253, ptd 140, jfb 216, sfs 211, jmn 132, pmj 129;
/// `tools/voices_analyze.py`, 10/09/2026). Id desconhecido cai em "Voz N".
const Map<String, String> kVoiceNames = {
  'pt-br-x-afs': 'Cida',
  'pt-br-x-pte': 'Rose',
  'pt-br-x-ptd': 'Tião',
  'pt-pt-x-jfb': 'Maria',
  'pt-pt-x-sfs': 'Inês',
  'pt-pt-x-jmn': 'Joaquim',
  'pt-pt-x-pmj': 'Manuel',
};

String voiceLabel(String name, String locale, int index) {
  final base = name.replaceFirst(RegExp(r'-(local|network)$'), '');
  final n = kVoiceNames[base] ?? 'Voz ${index + 1}';
  return locale.toLowerCase() == 'pt-pt' ? '$n (Portugal)' : n;
}

