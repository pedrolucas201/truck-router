import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/screens/navigation_screen.dart';

/// Esta é a única lógica do app que **cala um alerta de radar**, então o teste
/// existe pra provar o cinto de segurança, não a feature: radar em que o
/// caminhão nunca chegou não pode sumir da tela em hipótese nenhuma.
///
/// Sem alarme é multa; falso alarme é passável.
void main() {
  group('não suprime nada que o caminhão esteja se aproximando', () {
    test('radar longe, nunca alcançado: fica na tela', () {
      // 300 m de distância mínima. Mesmo que ele se afaste 1 km depois, nunca
      // chegou nele — pode ser que a rota ainda o leve lá.
      expect(NavigationScreen.radarPassou(d: 1300, dMin: 300), isFalse);
    });

    test('⭐ GPS pulando 40 m com o caminhão parado ANTES do radar', () {
      // O caso perigoso que derrubou o desenho por "distância cresceu" puro:
      // parado a 200 m do radar, accM ruim, a posição pula pra 245 m. Se isso
      // suprimisse, ele passaria pelo radar sem aviso nenhum.
      expect(NavigationScreen.radarPassou(d: 245, dMin: 200), isFalse);
    });

    test('quase chegando: 61 m é 1 m a mais que o limiar de chegada', () {
      expect(NavigationScreen.radarPassou(d: 200, dMin: 61), isFalse);
    });

    test('chegou mas ainda está em cima dele', () {
      expect(NavigationScreen.radarPassou(d: 10, dMin: 5), isFalse);
      expect(NavigationScreen.radarPassou(d: 44, dMin: 5), isFalse);
    });
  });

  group('suprime só depois de chegar E se afastar', () {
    test('passou por cima e seguiu', () {
      expect(NavigationScreen.radarPassou(d: 46, dMin: 5), isTrue);
    });

    test('pista oposta: mínimo de 25 m (largura do canteiro), depois afasta', () {
      // É o print do Beto na Dutra, 22/09.
      expect(NavigationScreen.radarPassou(d: 66, dMin: 25), isTrue);
      expect(NavigationScreen.radarPassou(d: 64, dMin: 25), isFalse);
    });

    test('limite exato da chegada (60 m) ainda conta como chegou', () {
      expect(NavigationScreen.radarPassou(d: 101, dMin: 60), isTrue);
    });
  });

  test('aproximar de novo traz o radar de volta', () {
    // Retorno: depois de suprimido a 46 m, ele volta. Assim que a distância
    // cai pra dentro da margem, o alerta reaparece.
    expect(NavigationScreen.radarPassou(d: 46, dMin: 5), isTrue);
    expect(NavigationScreen.radarPassou(d: 44, dMin: 5), isFalse);
  });
}
