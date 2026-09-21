import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/screens/navigation_screen.dart';

/// Storm de campo 18/09 (sessão `mu70mph0-g8khlq`, v2.4.78): caminhão parado
/// ~250 m fora da rota rendeu 105 chamadas HERE em 30 min, todas devolvendo a
/// MESMA rota (`distM=21846`, `points=520`). O gate disparava certo; faltava
/// notar que a resposta não ia mudar.
void main() {
  // Pátio a ~250 m da rota, onde o caminhão do Beto ficou parado.
  const parado = LatLng(-23.2062451, -46.0064483);

  /// Ponto a [m] metros ao norte de [p] (1° de latitude ≈ 111 320 m).
  LatLng aoNorte(LatLng p, double m) =>
      LatLng(p.latitude + m / 111320.0, p.longitude);

  test('primeiro reroute do episodio SEMPRE passa', () {
    // É ele que desenha o caminho de volta na tela: sem isso o motorista fica
    // parado no pátio olhando a rota velha.
    expect(saiuDoLugar(null, parado), isTrue);
  });

  test('parado no mesmo lugar nao pede a mesma rota de novo', () {
    expect(saiuDoLugar(parado, parado), isFalse);
    // Jitter de GPS parado (precisão medida no field: accM 3-5 m).
    expect(saiuDoLugar(parado, aoNorte(parado, 5)), isFalse);
    // Manobra dentro do pátio ainda é o mesmo lugar.
    expect(saiuDoLugar(parado, aoNorte(parado, 40)), isFalse);
  });

  test('andou de verdade destrava o reroute', () {
    // +2 m: a conversao metro->grau daqui e aproximada e encostar na borda
    // testaria o arredondamento, nao a regra.
    expect(saiuDoLugar(parado, aoNorte(parado, kRerouteMovedM + 2)), isTrue);
    expect(saiuDoLugar(parado, aoNorte(parado, 120)), isTrue);
  });

  test('o teto fica abaixo do corredor de off-route', () {
    // Se kRerouteMovedM passar dos 70 m do corredor, a guarda comeria desvio
    // real: dá pra sair da rota inteira sem "sair do lugar".
    expect(kRerouteMovedM, lessThan(70.0));
  });
}
