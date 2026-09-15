import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/voice_queue.dart';

void main() {
  test('fala enfileirada sai na ordem, sem repetir, e a cheia derruba a mais antiga', () {
    final q = VoiceQueue();
    expect(q.enfileirar('Rota passa pelo motorista que pediu ajuda.'), isTrue);
    expect(q.enfileirar('Rota passa pelo motorista que pediu ajuda.'), isFalse,
        reason: 'repetida não entra');
    expect(q.enfileirar('Você chegou no motorista que pediu ajuda.'), isTrue);
    // Cheia (2): a terceira derruba a mais antiga, nunca a mais nova.
    expect(q.enfileirar('Pedido de ajuda encerrado. Seguindo pro destino.'), isTrue);
    expect(q.length, VoiceQueue.capacidade);
    expect(q.proxima(), 'Você chegou no motorista que pediu ajuda.');
    expect(q.proxima(), 'Pedido de ajuda encerrado. Seguindo pro destino.');
    expect(q.proxima(), isNull);
    expect(q.isEmpty, isTrue);
  });
}
