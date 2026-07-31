import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/poi.dart';
import 'package:truck_router/services/scale_service.dart';

// O app já anunciava "Balança em X km" — em cima de 3 pontos inventados que
// viviam em lib/data/pois.dart marcados como "hardcoded para teste". Balança que
// não avisa é multa, então o dado aqui não pode ser chute.
void main() {
  const csv = 'longitude,latitude,nome,descricao,status,sentido\n'
      '-47.248200,-15.566200,Balança DNIT Formosa,BR-020 km 12 — Formosa/GO,Operando,C\n'
      '-37.235200,-10.958300,Balança DNIT São Cristovão,BR-101 km 104.1 — São Cristovão/SE,Paralisada,D\n';

  test('parseia e ignora o header', () {
    final l = ScaleService.parseCsv(csv);
    expect(l.length, 2);
    expect(l.first.name, 'Balança DNIT Formosa');
    expect(l.first.category, PoiCategory.scale);
    expect(l.first.position.latitude, closeTo(-15.5662, 1e-4));
    expect(l.first.position.longitude, closeTo(-47.2482, 1e-4));
    expect(l.first.description, contains('BR-020 km 12'));
  });

  test('"Paralisada" continua no mapa — status não suprime', () {
    // Paralisado é estado do EQUIPAMENTO, não garantia de que não há
    // fiscalização ali. Mesmo raciocínio que impediu de silenciar radar
    // oficialmente desativado.
    final l = ScaleService.parseCsv(csv);
    expect(l.length, 2, reason: 'a paralisada não pode sumir da lista');
    expect(l.any((p) => p.name.contains('São Cristovão')), isTrue);
  });

  test('linha inválida não derruba o parse', () {
    final l = ScaleService.parseCsv('$csv,,\nlixo,aqui\n-1.0\n');
    expect(l.length, 2);
  });

  test('balança não tem restrição física — sempre compatível', () {
    // Sem isso o marcador sairia cinza (incompatível) no mapa.
    final l = ScaleService.parseCsv(csv);
    expect(l.first.maxHeightCm, isNull);
    expect(l.first.maxWeightKg, isNull);
  });

  test('lista vazia antes do load, sem estourar', () {
    expect(() => ScaleService.all, returnsNormally);
  });
}
