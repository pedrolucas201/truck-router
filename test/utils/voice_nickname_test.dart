import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/voice_settings.dart';

void main() {
  test('apelidos cobrem a lista e caem em Voz N depois', () {
    expect(voiceNickname(0), 'Copiloto');
    expect(voiceNickname(kVoiceNicknames.length - 1), 'Navegador');
    expect(voiceNickname(kVoiceNicknames.length), 'Voz ${kVoiceNicknames.length + 1}');
    expect(kVoiceNicknames.toSet().length, kVoiceNicknames.length);
  });
}
