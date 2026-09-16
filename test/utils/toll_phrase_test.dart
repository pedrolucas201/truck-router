import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/radar_tts.dart';

// O TTS nunca recebe numeral de dinheiro (a "loteria" do d7e4202). Se alguém
// voltar a mandar "R$ 12,60" pra voz, este teste cai.
void main() {
  test('valor por extenso', () {
    expect(reaisPorExtenso(12.60), 'doze reais e sessenta centavos');
    expect(reaisPorExtenso(8.0), 'oito reais');
    expect(reaisPorExtenso(1.0), 'um real');
    expect(reaisPorExtenso(0.5), 'cinquenta centavos');
    expect(reaisPorExtenso(23.4), 'vinte e três reais e quarenta centavos');
    expect(reaisPorExtenso(100.0), 'cem reais');
    expect(reaisPorExtenso(107.70), 'cento e sete reais e setenta centavos');
    expect(reaisPorExtenso(15.01), 'quinze reais e um centavo');
    expect(reaisPorExtenso(19.9), 'dezenove reais e noventa centavos');
  });

  test('frase do pedágio: nome + valor; sem valor fala só o nome', () {
    expect(tollPhrase('Itatiba', 23.4), 'Pedágio Itatiba à frente, vinte e três reais e quarenta centavos');
    expect(tollPhrase(null, 8.0), 'Pedágio à frente, oito reais');
    expect(tollPhrase('Jacareí', null), 'Pedágio Jacareí à frente');
    expect(tollPhrase('Jacareí', 0), 'Pedágio Jacareí à frente');
    // nunca numeral nem cifrão na frase
    expect(tollPhrase('X', 12.6), isNot(contains('R\$')));
    expect(tollPhrase('X', 12.6), isNot(matches(RegExp(r'\d'))));
  });
}
