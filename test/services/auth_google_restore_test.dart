import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/auth_service.dart';

void main() {
  test('sem a marca de Google vinculado, o boot nunca tenta o login Google', () {
    // Sem isto todo motorista que nunca vinculou veria um seletor de contas
    // ao abrir o app (o lightweight do Android cai no seletor).
    expect(AuthService.tentaGoogleNoLogin('boot', false), isFalse);
    expect(AuthService.tentaGoogleNoLogin('lazy', false), isFalse);
  });

  test('com a marca, boot e lazy recuperam; o botao de vincular tem fluxo proprio', () {
    expect(AuthService.tentaGoogleNoLogin('boot', true), isTrue);
    expect(AuthService.tentaGoogleNoLogin('lazy', true), isTrue);
    expect(AuthService.tentaGoogleNoLogin('link', true), isFalse);
  });
}
