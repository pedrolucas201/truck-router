import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route_result.dart';
import 'radar_service.dart';

/// Quanto a rota que a HERE devolveu num recálculo difere do que faltava da
/// rota anterior. Só telemetria: decide (com dados) se o recálculo periódico
/// pode esperar mais quando a resposta vem igual e se as praças de pedágio da
/// rota anterior podem ser reaproveitadas sem pedir `tolls` de novo.
///
/// Métrica BRUTA de propósito: o limiar de "mesma rota" se escolhe depois,
/// olhando a distribuição. Fixar a tolerância agora arriscava uma semana
/// inconclusiva.
///
/// - [desvioMaxM]: maior distância lateral de um ponto da rota nova até o
///   trecho restante da anterior.
/// - [pracasNovas]: praças da rota nova que não estavam à frente na anterior.
///   Maior que zero com o traçado igual = reaproveitar as praças calaria um
///   pedágio (sem alarme = multa). É o número que valida o desenho.
/// - [pracasSumiram]: praças que estavam à frente e não vieram na nova.
({int desvioMaxM, int pracasNovas, int pracasSumiram}) compararRotas({
  required List<LatLng> restanteAnterior,
  required List<LatLng> nova,
  required List<TollPlaza> pracasAnteriores,
  required List<TollPlaza> pracasNovas,
}) {
  // Amostra da rota nova a cada 100 m, mas no máximo ~200 amostras: roda na
  // thread da tela, e rota de 370 km que mudou inteira (varredura cheia em
  // cada amostra) sem teto dava ~13 mi de contas. ponytail: 200 amostras numa
  // rota longa = uma a cada ~2 km; desvio mais curto que isso pode escapar,
  // sobe o teto (ou vai pra isolate) se a distribuição vier estranha.
  const janela = 400;   // segmentos à frente na busca monotônica
  const exatoAcimaM = 25.0;
  // Janela acha rápido o caso comum (rotas iguais, andando juntas). Se ela
  // devolve > 25 m, varre a rota inteira: o valor reportado é exato sempre
  // que importa, e o custo cheio só aparece quando a rota mudou de fato.
  final velha = restanteAnterior;
  var desvioMax = 0.0;
  if (velha.length >= 2 && nova.isNotEmpty) {
    var totalM = 0.0;
    for (var i = 1; i < nova.length; i++) {
      totalM += RadarService.haversine(nova[i - 1].latitude,
          nova[i - 1].longitude, nova[i].latitude, nova[i].longitude);
    }
    final passoM = totalM / 200 > 100 ? totalM / 200 : 100.0;
    var j = 0;
    var acumulado = passoM; // força a 1ª amostra
    for (var i = 0; i < nova.length; i++) {
      if (i > 0) {
        acumulado += RadarService.haversine(nova[i - 1].latitude,
            nova[i - 1].longitude, nova[i].latitude, nova[i].longitude);
      }
      if (acumulado < passoM && i != nova.length - 1) continue;
      acumulado = 0;
      final p = nova[i];
      var melhor = double.infinity;
      var melhorJ = j;
      final fim = (j + janela).clamp(0, velha.length - 1);
      for (var k = j; k < fim; k++) {
        final d = _seg(p, velha[k], velha[k + 1]);
        if (d < melhor) { melhor = d; melhorJ = k; }
      }
      if (melhor > exatoAcimaM) {
        for (var k = 0; k < velha.length - 1; k++) {
          final d = _seg(p, velha[k], velha[k + 1]);
          if (d < melhor) { melhor = d; melhorJ = k; }
        }
      }
      j = melhorJ;
      if (melhor > desvioMax) desvioMax = melhor;
    }
  }

  // Praça é a mesma se a HERE devolveu o ponto no mesmo lugar (a coordenada
  // vem do dado dela, estável entre chamadas; 30 m absorve arredondamento).
  bool mesma(TollPlaza a, TollPlaza b) =>
      RadarService.haversine(a.position.latitude, a.position.longitude,
          b.position.latitude, b.position.longitude) < 30;
  // À frente = em cima do trecho restante (o ponto da HERE nasce na linha).
  final aFrente = pracasAnteriores
      .where((t) => RadarService.distanceToPath(
              t.position.latitude, t.position.longitude, velha) < 30)
      .toList();
  return (
    desvioMaxM: desvioMax.isFinite ? desvioMax.round() : -1,
    pracasNovas: pracasNovas.where((n) => !aFrente.any((a) => mesma(a, n))).length,
    pracasSumiram: aFrente.where((a) => !pracasNovas.any((n) => mesma(a, n))).length,
  );
}

double _seg(LatLng p, LatLng a, LatLng b) => RadarService.distanceToSegment(
    p.latitude, p.longitude, a.latitude, a.longitude, b.latitude, b.longitude);
