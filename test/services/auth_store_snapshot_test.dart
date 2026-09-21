import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/auth_service.dart';

/// O `store` do `auth_signin` do Beto (`3980b:user=1,529b:user=0`) não separava
/// as duas causas possíveis do churn de uid, que têm cura oposta: o SDK gravar
/// num arquivo e ler de outro, ou ele recusar o usuário que ele mesmo escreveu.
/// O que separa é o NOME do arquivo e o uid guardado — é o que estes testes
/// travam.
void main() {
  const pasta = '/data/data/com.truckrouter.truck_router/shared_prefs/';
  const chaveA = 'W0RFRkFVTFRdK0FJemFTeURwSUhYaXA';
  const chaveB = 'W0RFRkFVTFRdK0FJemFTeVhYWFhYWFg';

  String linha(String chave, String conteudo) =>
      AuthService.storeLinha('${pasta}com.google.firebase.auth.api.Store.$chave.xml', 3980, conteudo);

  test('dois stores de persistenceKey diferente não se confundem', () {
    // Começo IGUAL de propósito: "[DEFAULT]" são 12 caracteres base64 cravados,
    // então o prefixo nunca distingue e a cauda tem que distinguir.
    final a = linha(chaveA, '{}');
    final b = linha(chaveB, '{}');
    expect(a, isNot(b));
  });

  test('uid do usuário em disco sai encurtado', () {
    final l = linha(chaveA,
        '<string>{"userId":"vaxXWWabcdefghijklmnopqrstuv","x":1}</string>');
    expect(l, endsWith(':3980b:user=vaxXWW'));
  });

  test('arquivo sem usuário sai user=none', () {
    expect(linha(chaveA, '<map/>'), endsWith(':3980b:user=none'));
  });

  test('FIREBASE_USER com formato desconhecido não vira none', () {
    // Virar 'none' aqui apagaria justamente o caso que se quer enxergar.
    expect(linha(chaveA, 'FIREBASE_USER=?'), endsWith(':3980b:user=ilegivel'));
  });

  test('arquivo que não é store sai marcado, pra não passar por um', () {
    final l = AuthService.storeLinha(
        '${pasta}com.google.firebase.auth.internal.outra.xml', 529, '{}');
    expect(l, startsWith('outro:'));
  });
}
