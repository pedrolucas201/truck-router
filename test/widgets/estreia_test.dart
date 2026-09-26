import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/widgets/map/estreia_sheet.dart';

/// O cartão de estreia só mostra o que aconteceu de verdade na rota.
void main() {
  test('pedágio, radar e desvio viram uma linha cada', () {
    final l = linhasEstreia(pedagios: 4, tollText: '4 pedágios · R\$ 107,70', radares: 14, desvios: 2);
    expect(l.map((e) => e.$2), [
      '4 pedágios · R\$ 107,70, no valor do seu eixo',
      '14 radares no caminho, no limite de caminhão',
      'Desviou de 2 pontos que não cabem no seu caminhão',
    ]);
  });

  test('sem pedágio a linha some (nunca "R\$ 0"); singular certo', () {
    final l = linhasEstreia(pedagios: 0, tollText: '0 pedágios', radares: 1, desvios: 1);
    expect(l.map((e) => e.$2), [
      '1 radar no caminho, no limite de caminhão',
      'Desviou de 1 ponto que não cabe no seu caminhão',
    ]);
  });

  test('rota sem nada não abre o cartão (guarda a estreia pra próxima)', () {
    expect(linhasEstreia(pedagios: 0, tollText: '', radares: 0, desvios: 0), isEmpty);
  });
}
