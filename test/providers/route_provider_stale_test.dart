import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/models/user_restriction.dart';
import 'package:truck_router/providers/route_provider.dart';
import 'package:truck_router/repositories/restriction_repository.dart';

/// Repositório que nunca é chamado: o que se testa aqui é a geração do cálculo,
/// não a rota.
class _RepoVazio implements RestrictionRepository {
  @override
  Future<List<BridgeRestriction>> fetchNearRoute(List<LatLng> points) async => [];
  @override
  Future<List<BridgeRestriction>> fetchByBounds(
          double minLat, double maxLat, double minLng, double maxLng) async =>
      [];
  @override
  Future<String> add(UserRestriction r, String uid) async => '';
  @override
  Future<void> confirm(String id) async {}
  @override
  Future<void> report(String id) async {}
}

/// `calculate()` são até 2 chamadas HERE + asset + Firestore + TomTom em série:
/// segundos em que o motorista pode trocar o endereço ou apertar voltar. Sem
/// invalidar a geração, a resposta da busca ABANDONADA chega depois e vira a
/// rota da tela (ou uma tela de erro por cima da rota nova).
void main() {
  test('clear() invalida o calculo em curso', () {
    final p = RouteProvider(_RepoVazio());
    final antes = p.calcSeq;
    p.clear();
    expect(p.calcSeq, greaterThan(antes),
        reason: 'sem isto a rota abandonada reaparece sozinha na tela');
  });

  test('cada clear invalida de novo (voltar duas vezes seguidas)', () {
    final p = RouteProvider(_RepoVazio());
    final a = p.calcSeq;
    p.clear();
    p.clear();
    expect(p.calcSeq, greaterThan(a + 1));
  });
}
