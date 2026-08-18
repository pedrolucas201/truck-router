import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/voice_settings.dart';

void main() {
  group('ptVoices', () {
    // O retorno cru do getVoices no Android: List<Map> com name/locale.
    test('filtra só português, pt-BR na frente, ordem estável', () {
      final raw = [
        {'name': 'en-us-x-sfg-local', 'locale': 'en-US'},
        {'name': 'pt-pt-x-jmn-local', 'locale': 'pt-PT'},
        {'name': 'pt-br-x-ptd-local', 'locale': 'pt-BR'},
        {'name': 'pt-br-x-afs-local', 'locale': 'pt-BR'},
        {'name': 'es-es-x-eed-local', 'locale': 'es-ES'},
      ];
      final voices = VoiceSettings.ptVoices(raw);
      expect(voices.map((v) => v['name']), [
        'pt-br-x-afs-local', // pt-BR primeiro, alfabético
        'pt-br-x-ptd-local',
        'pt-pt-x-jmn-local', // outros pt depois
      ]);
    });

    test('lixo do platform channel não derruba: null, tipo errado, sem nome', () {
      expect(VoiceSettings.ptVoices(null), isEmpty);
      expect(VoiceSettings.ptVoices('erro'), isEmpty);
      expect(
        VoiceSettings.ptVoices([
          {'locale': 'pt-BR'}, // sem name
          'string solta',
          {'name': 'x', 'locale': 'pt-BR'},
        ]).length,
        1,
      );
    });

    test('a numeração Voz 1..N é estável entre aberturas da tela', () {
      final raw = [
        {'name': 'pt-br-b', 'locale': 'pt-BR'},
        {'name': 'pt-br-a', 'locale': 'pt-BR'},
      ];
      // Mesma entrada em qualquer ordem → mesma saída; senão "Voz 2" de ontem
      // vira "Voz 1" de hoje e a escolha do motorista muda de nome sozinha.
      expect(VoiceSettings.ptVoices(raw),
          VoiceSettings.ptVoices(raw.reversed.toList()));
    });
  });

  test('tons: normal existe e é pitch 1.0; todos os tons são conhecidos', () {
    expect(VoiceSettings.tones['normal'], 1.0);
    expect(VoiceSettings.tones.keys, containsAll(['et', 'robo']));
  });
}
