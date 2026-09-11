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

    test('par -local/-network vira UMA voz, preferindo a -local', () {
      // Era o "milhão de vozes iguais": o Google TTS lista cada voz 2x.
      // A -local fala sem internet — zona morta de sinal não pode calar o guia.
      final voices = VoiceSettings.ptVoices([
        {'name': 'pt-br-x-afs-network', 'locale': 'pt-BR'},
        {'name': 'pt-br-x-afs-local', 'locale': 'pt-BR'},
        {'name': 'pt-br-x-ptd-network', 'locale': 'pt-BR'},
      ]);
      expect(voices.map((v) => v['name']), [
        'pt-br-x-afs-local',   // par colapsado na -local
        'pt-br-x-ptd-network', // sem par: entra como está
      ]);
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

  group('aliases e nomes (medidos no Redmi, 10/09)', () {
    test('pt-BR-language some quando existe voz x- do mesmo idioma', () {
      final raw = [
        {'name': 'pt-BR-language', 'locale': 'pt-BR'},
        {'name': 'pt-br-x-afs-local', 'locale': 'pt-BR'},
        {'name': 'pt-br-x-afs-network', 'locale': 'pt-BR'},
        {'name': 'pt-PT-language', 'locale': 'pt-PT'},
        {'name': 'pt-pt-x-jfb-local', 'locale': 'pt-PT'},
      ];
      expect(VoiceSettings.ptVoices(raw).map((v) => v['name']),
          ['pt-br-x-afs-local', 'pt-pt-x-jfb-local']);
    });
    test('alias fica quando é a única voz do idioma', () {
      final raw = [{'name': 'pt-BR-language', 'locale': 'pt-BR'}];
      expect(VoiceSettings.ptVoices(raw).map((v) => v['name']), ['pt-BR-language']);
    });
    test('rótulo por id, Portugal marcado, desconhecido vira Voz N', () {
      expect(voiceLabel('pt-br-x-ptd-local', 'pt-BR', 0), 'Tião');
      expect(voiceLabel('pt-br-x-afs-network', 'pt-BR', 0), 'Cida');
      expect(voiceLabel('pt-pt-x-jmn-local', 'pt-PT', 3), 'Joaquim (Portugal)');
      expect(voiceLabel('pt-br-x-zzz-local', 'pt-BR', 4), 'Voz 5');
    });
  });
}
