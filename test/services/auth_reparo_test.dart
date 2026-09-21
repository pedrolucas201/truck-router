import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/auth_service.dart';

/// O churn de uid deixa o app com um anônimo NOVO no meio da viagem: o S.O.S.
/// deixa de ser escutado (a regra exige Google), o voto conta como outra pessoa
/// e o perfil fica órfão. O sinal de que isso aconteceu é a marca em prefs dizer
/// que este aparelho vinculou o Google enquanto o usuário atual não tem nenhum.
void main() {
  test('marca + usuario anonimo = identidade quebrada, repara', () {
    expect(
        AuthService.precisaReparar(marca: true, temGoogle: false, jaReparou: false),
        isTrue);
  });

  test('quem nunca vinculou segue anonimo em paz', () {
    // Sem isto, todo motorista anônimo levaria uma tentativa de login Google.
    expect(
        AuthService.precisaReparar(marca: false, temGoogle: false, jaReparou: false),
        isFalse);
  });

  test('ja esta com Google: nada a fazer', () {
    expect(
        AuthService.precisaReparar(marca: true, temGoogle: true, jaReparou: false),
        isFalse);
  });

  test('uma vez por sessao', () {
    // O retry do S.O.S. bate de 1 em 1 min; sem esta trava, martelaria o Google.
    expect(
        AuthService.precisaReparar(marca: true, temGoogle: false, jaReparou: true),
        isFalse);
  });
}
