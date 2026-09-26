import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/sos_request.dart';
import 'package:truck_router/services/sos_service.dart';

/// Ponto vermelho no ☰: só pedido ABERTO de OUTRO motorista a até 20 km.
void main() {
  final agora = DateTime.now();
  SosRequest s(String id, String uid, double dLat, {String status = 'aberto'}) => SosRequest(
        id: id, uid: uid, nome: 'M', caminhao: '', cor: '', tipo: SosTipo.values.first, texto: '',
        lat: -8.0 + dLat, lng: -35.0, status: status,
        criadoEm: agora, expireAt: agora.add(const Duration(hours: 1)),
      );

  test('meu pedido, pedido longe e pedido já atendido não contam', () {
    final perto = sosPertoDe([
      s('longe', 'b', .5), // ~55 km
      s('meu', 'eu', .01),
      s('atendido', 'c', .02, status: 'atendendo'),
      s('perto2', 'd', .05), // ~5,5 km
      s('perto1', 'e', .01), // ~1,1 km
    ], 'eu', -8.0, -35.0);
    expect(perto.map((p) => p.$1.id), ['perto1', 'perto2'], reason: 'do mais perto pro mais longe');
  });
}
