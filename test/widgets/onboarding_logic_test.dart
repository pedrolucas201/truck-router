import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:truck_router/screens/map_screen.dart';
import 'package:truck_router/widgets/onboarding/onboarding_logic.dart';

/// Regras do onboarding que não podem regredir: pra onde vai o "Pular", o que
/// cada resposta do sistema vira no cartão, quando o caminhão é gravado, e
/// que o boot NÃO volta a pedir localização depois do onboarding pedir.
void main() {
  test('Pular só existe na apresentação e cai no cadastro do caminhão', () {
    for (var i = 0; i < kPaginaCaminhao; i++) {
      expect(pularDestino(i), kPaginaCaminhao, reason: 'página $i');
    }
    expect(pularDestino(kPaginaCaminhao), isNull);
    expect(pularDestino(kPaginaPermissoes), isNull);
  });

  test('7 páginas: 5 de apresentação + caminhão + permissões', () {
    expect(kTelasOnboarding.length, kPaginaCaminhao);
    expect(kTotalPaginas, kPaginaPermissoes + 1);
  });

  test('cartão de localização: durante o uso já conta como concedida', () {
    expect(estadoLocalizacao(LocationPermission.whileInUse), PermissaoEstado.concedida);
    expect(estadoLocalizacao(LocationPermission.always), PermissaoEstado.concedida);
    expect(estadoLocalizacao(LocationPermission.denied), PermissaoEstado.pendente);
    expect(estadoLocalizacao(LocationPermission.deniedForever), PermissaoEstado.negadaDeVez);
  });

  test('passar direto pelo caminhão padrão não grava nada', () {
    expect(
        caminhaoMudou(
            alturaCm: 420, comprimentoCm: 1400, pesoKg: 25000, eixos: 5,
            alturaAtualCm: 420, comprimentoAtualCm: 1400, pesoAtualKg: 25000, eixosAtual: 5),
        isFalse);
    expect(
        caminhaoMudou(
            alturaCm: 440, comprimentoCm: 1400, pesoKg: 25000, eixos: 5,
            alturaAtualCm: 420, comprimentoAtualCm: 1400, pesoAtualKg: 25000, eixosAtual: 5),
        isTrue);
  });

  test('depois do onboarding pedir, o boot não gasta a segunda negação', () {
    // O onboarding carimba a marca (alreadyAsked=true) ANTES de pedir. Se o
    // motorista negou lá, o boot tem que ficar quieto: a 2ª negação é permanente.
    expect(shouldAskLocationOnBoot(LocationPermission.denied, true), isFalse);
  });
}
