import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/maneuver_phrase.dart';

void main() {
  group('maneuverPhrase — síntese de action+direction', () {
    test('vira à direita / esquerda', () {
      expect(maneuverPhrase('turn', 'right'), 'vire à direita');
      expect(maneuverPhrase('turn', 'left'), 'vire à esquerda');
    });

    test('curvas acentuadas e leves', () {
      expect(maneuverPhrase('turn', 'sharpRight'), 'vire acentuadamente à direita');
      expect(maneuverPhrase('turn', 'slightLeft'), 'vire levemente à esquerda');
    });

    test('turn sem direção não inventa lado', () {
      expect(maneuverPhrase('turn', null), 'vire');
    });

    test('keep / rotatória / saída / rampa / retorno', () {
      expect(maneuverPhrase('keepRight', null), 'mantenha-se à direita');
      expect(maneuverPhrase('keepLeft', null), 'mantenha-se à esquerda');
      expect(maneuverPhrase('roundaboutExit', 'right'), 'na rotatória, pegue a saída à direita');
      expect(maneuverPhrase('exit', 'right'), 'pegue a saída à direita');
      expect(maneuverPhrase('ramp', null), 'pegue a rampa');
      expect(maneuverPhrase('uTurn', null), 'faça o retorno');
      expect(maneuverPhrase('continue', null), 'siga em frente');
    });

    test('ação desconhecida vira string vazia (não anuncia errado)', () {
      expect(maneuverPhrase('teleport', 'right'), '');
    });
  });

  group('resolveManeuverText — instrução da HERE vence quando existe', () {
    test('usa a instruction quando vem preenchida', () {
      expect(resolveManeuverText('Vire na Rua X', 'turn', 'left'), 'Vire na Rua X');
    });

    test('instruction vazia ou só espaços cai pra síntese (capitalizada)', () {
      expect(resolveManeuverText('', 'turn', 'right'), 'Vire à direita');
      expect(resolveManeuverText('   ', 'turn', 'right'), 'Vire à direita');
    });

    test('síntese capitaliza a 1ª letra pra casar com a HERE', () {
      expect(resolveManeuverText('', 'keepRight', null), 'Mantenha-se à direita');
      expect(resolveManeuverText('', 'roundaboutExit', 'left'), 'Na rotatória, pegue a saída à esquerda');
    });

    test('instruction da HERE é preservada como veio (não re-capitaliza)', () {
      expect(resolveManeuverText('Vire na Rua X', 'turn', 'left'), 'Vire na Rua X');
    });

    test('instruction vazia + ação sem fala -> vazio', () {
      expect(resolveManeuverText('', 'continue', null), 'Siga em frente');
      expect(resolveManeuverText('', 'sei lá', null), '');
    });
  });
}
