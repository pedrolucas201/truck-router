import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/physical_restriction_service.dart';

// Guarda o asset de restrições físicas (tools/restricoes_fetch.py), que substituiu
// a consulta à Overpass no meio do cálculo da rota — ela falhava em 100% dos casos
// medidos e o app via `restr: 0` em 4 de 4 reroutes de campo.
//
// O que estes testes protegem é o GERADOR: se ele voltar a incluir objeto que não
// é via, ou corromper unidade, quem paga é o motorista com desvio inventado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset carrega e tem volume compatível com o Brasil', () async {
    final r = await PhysicalRestrictionService.load();
    // 12.359 na geração de 2026-07-22. A faixa é larga de propósito: o OSM cresce.
    // O que isto pega é o asset vazio/truncado ou uma explosão de duplicata.
    expect(r.length, greaterThan(8000));
    expect(r.length, lessThan(40000));
  });

  test('só os três tipos que o TruckProfile sabe comparar', () async {
    final r = await PhysicalRestrictionService.load();
    const conhecidos = {'maxheight', 'maxweight', 'maxwidth'};
    final tipos = r.map((e) => e.type).toSet();
    expect(tipos.difference(conhecidos), isEmpty,
        reason: 'tipo desconhecido no asset cai no _ => false do conflictsWith '
            'e vira restrição que nunca alerta');
  });

  test('coordenadas dentro do retângulo baixado', () async {
    final r = await PhysicalRestrictionService.load();
    for (final e in r) {
      expect(e.lat, inInclusiveRange(-34, 6), reason: '${e.type} em ${e.lat},${e.lng}');
      expect(e.lng, inInclusiveRange(-74, -34), reason: '${e.type} em ${e.lat},${e.lng}');
    }
  });

  test('nenhum valor <= 0 — pega erro de unidade do gerador', () async {
    final r = await PhysicalRestrictionService.load();
    for (final e in r) {
      expect(e.value, greaterThan(0),
          reason: 'valor não-positivo conflita com TODO caminhão: '
              '${e.type}=${e.value} em ${e.lat},${e.lng}');
    }
  });

  test('helipontos ficaram fora: peso vs. altura em proporção de via', () async {
    final r = await PhysicalRestrictionService.load();
    final peso  = r.where((e) => e.type == 'maxweight').length;
    final altura = r.where((e) => e.type == 'maxheight').length;
    // 1.114 `aeroway=helipad` do OSM carregam maxweight = peso do HELICÓPTERO.
    // Incluí-los inflava maxweight em ~34% e fazia o caminhão desviar de heliponto.
    // Na geração limpa: 3.355 peso / 8.518 altura = 0,39. Se o filtro semântico do
    // gerador cair, esta razão dispara.
    expect(peso / altura, lessThan(0.60),
        reason: 'maxweight inflado ($peso peso / $altura altura) — o filtro '
            'NAO_E_VIA do restricoes_fetch.py provavelmente caiu');
  });
}
