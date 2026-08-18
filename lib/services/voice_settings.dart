import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'field_log.dart';

/// Voz do guia escolhida pelo motorista: qual voz do aparelho fala e em que
/// tom. Padrão = voz default do engine, tom normal — quem nunca mexeu aqui
/// não muda de comportamento em nada.
class VoiceSettings {
  static const _kName   = 'tts_voice_name';
  static const _kLocale = 'tts_voice_locale';
  static const _kTone   = 'tts_voice_tone';

  /// Tons disponíveis. O pitch é o que fabrica a "voz de E.T." — funciona
  /// sobre qualquer voz de qualquer aparelho, ao contrário da lista de vozes,
  /// que depende do engine instalado.
  // Knob DE OUVIDO, não de papel: 1.7/0.7 foram escolhidos sem ouvir e o
  // Pedro reprovou ("péssimas") — extremos de pitch viram ruído no engine.
  // Valores atuais são o próximo chute; calibrar ouvindo antes de mexer.
  static const tones = <String, double>{
    'normal': 1.0,
    'et':     1.4, // aguda, "E.T."
    'robo':   0.8, // grave, robótica
  };

  static Future<({String? name, String? locale, String tone})> load() async {
    final p = await SharedPreferences.getInstance();
    final tone = p.getString(_kTone);
    return (
      name:   p.getString(_kName),
      locale: p.getString(_kLocale),
      tone:   tones.containsKey(tone) ? tone! : 'normal',
    );
  }

  static Future<void> save(
      {String? name, String? locale, required String tone}) async {
    final p = await SharedPreferences.getInstance();
    if (name == null) {
      await p.remove(_kName);
      await p.remove(_kLocale);
    } else {
      await p.setString(_kName, name);
      await p.setString(_kLocale, locale ?? 'pt-BR');
    }
    await p.setString(_kTone, tone);
  }

  /// Aplica a escolha salva numa instância de TTS. Falha aqui nunca cala a
  /// navegação: voz salva que sumiu (update/troca de engine) devolve 0 no
  /// setVoice, o engine segue na default e fica o rastro.
  static Future<void> apply(FlutterTts tts) async {
    try {
      final s = await load();
      if (s.name != null) {
        final ok =
            await tts.setVoice({'name': s.name!, 'locale': s.locale ?? 'pt-BR'});
        if (ok != 1) FieldLog.event('tts_voice_fallback', {'voice': s.name!});
      }
      await tts.setPitch(tones[s.tone] ?? 1.0);
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
    final out = byBase.values.toList();
    out.sort((a, b) {
      final aBr = a['locale']!.toLowerCase() == 'pt-br' ? 0 : 1;
      final bBr = b['locale']!.toLowerCase() == 'pt-br' ? 0 : 1;
      return aBr != bBr ? aBr - bBr : a['name']!.compareTo(b['name']!);
    });
    return out;
  }
}
