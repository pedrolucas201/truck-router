import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/services/radar_service.dart';

// isNearRoute decide o que é CARREGADO pra rota (crowd + restrição do usuário);
// o alerta em si tem outro gate depois (_radarCorridorM = 22 m perpendicular).
// Quem não passa aqui nunca chega lá: é o estágio onde some sem deixar rastro.
//
// A versão antiga amostrava a polyline de 5 em 5 vértices e media até o VÉRTICE.
// Medido em 273 km de rota real da HERE (12/08/2026): 52,9% da rota ficava
// descoberta — 60,1% na Dutra, onde há 2.611 m entre duas amostras.
void main() {
  // Rota RALA, como a HERE emite em reta de rodovia: ~124 m entre vértices.
  // Com o passo de 5, só os índices 0 e 6 (o último) eram olhados.
  final rodovia = List.generate(
      7, (i) => LatLng(-23.2800 + i * 0.001, -45.8990 + i * 0.0005));

  test('radar EM CIMA da rota, em vértice não amostrado, é encontrado', () {
    final p = rodovia[2]; // o buraco da amostragem antiga
    expect(RadarService.isNearRoute(p.latitude, p.longitude, rodovia), isTrue,
        reason: 'radar não carregado = alerta que não toca = multa');
  });

  test('ponto no MEIO de um segmento longo também é encontrado', () {
    // Nem sequer é vértice: cai entre o 3 e o 4. Amostrar de 1 em 1 continuaria
    // errando aqui se o segmento fosse longo o bastante — medir até o segmento não.
    final a = rodovia[3], b = rodovia[4];
    final meio = LatLng((a.latitude + b.latitude) / 2,
        (a.longitude + b.longitude) / 2);
    expect(RadarService.isNearRoute(meio.latitude, meio.longitude, rodovia), isTrue);
  });

  test('não afrouxou: ponto fora do corredor continua fora', () {
    // ~1,1 km ao lado da rota — via paralela distante, outro bairro.
    expect(RadarService.isNearRoute(-23.2900, -45.8890, rodovia), isFalse);
  });

  test('corredor é respeitado nas duas direções', () {
    final p = rodovia[2];
    // ~55 m ao lado (0.0005 de longitude ≈ 51 m nesta latitude).
    final lado = LatLng(p.latitude, p.longitude + 0.0005);
    expect(RadarService.isNearRoute(lado.latitude, lado.longitude, rodovia,
            corridorM: 80),
        isTrue);
    expect(RadarService.isNearRoute(lado.latitude, lado.longitude, rodovia,
            corridorM: 20),
        isFalse);
  });

  test('polyline vazia não estoura e não encontra nada', () {
    expect(RadarService.isNearRoute(-23.28, -45.89, const []), isFalse);
  });
}
