import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/screens/navigation_screen.dart';

// pickUpcomingRadar decide QUAL radar ocupa o slot de alerta. O risco aqui é do
// lado "multa": um radar da contramão coladinho não pode mascarar o radar do
// sentido do motorista logo atrás. Ao mesmo tempo, nenhum radar pode SUMIR.
void main() {
  // Motorista rumo ao NORTE (heading 0). Radares ao norte, na "frente".
  const eu = LatLng(-23.5000, -46.6000);
  const norte = 0.0;

  // ~metros ao norte viram graus de latitude (111320 m/grau).
  RadarPoint radar(double metros, {double? dir1, String? dirSrc}) => RadarPoint(
        lat: -23.5000 + metros / 111320.0,
        lng: -46.6000,
        type: 'Radar Fixo',
        speedKmh: 60,
        dir1: dir1,
        dirSrc: dirSrc,
      );

  // dir1=0 (radar olha pra quem vai ao norte) => mesmo sentido.
  // dir1=180 (radar olha pra quem vem do norte) => oposto ao motorista rumo norte.
  RadarPoint mesmo(double m) => radar(m, dir1: 0, dirSrc: 'dnit');
  RadarPoint oposto(double m) => radar(m, dir1: 180, dirSrc: 'dnit');
  RadarPoint semDir(double m) => radar(m); // maioria da base: sem direção

  RadarPoint? pick(List<RadarPoint> rs) =>
      NavigationScreen.pickUpcomingRadar(rs, eu, norte, 5.0);

  test('sem dado de direção: escolhe o mais próximo (idêntico ao de antes)', () {
    final r = pick([semDir(300), semDir(100), semDir(200)]);
    expect(r!.lat, semDir(100).lat);
  });

  test('O BUG: oposto coladinho não mascara o do sentido logo atrás', () {
    final r = pick([oposto(31), mesmo(200)]);
    expect(r!.dir1, 0, reason: 'devia escolher o do MEU sentido, não o oposto colado');
  });

  test('oposto sozinho no raio AINDA alerta — nada some', () {
    final r = pick([oposto(50)]);
    expect(r, isNotNull);
    expect(r!.dir1, 180);
  });

  test('entre dois não-opostos, ganha o mais próximo', () {
    final r = pick([mesmo(250), semDir(90)]);
    expect(r!.lat, semDir(90).lat);
  });

  test('oposto mais perto perde para não-oposto mais longe, mas dentro do raio', () {
    final r = pick([oposto(40), semDir(390)]);
    expect(r!.dirSrc, isNull, reason: 'o semDir(390) ainda está dentro dos 400m');
  });

  test('nada dentro de 400m: slot vazio', () {
    expect(pick([mesmo(450), oposto(500)]), isNull);
  });

  test('lista vazia não explode', () {
    expect(pick([]), isNull);
  });

  test('heading inválido (GPS sem rumo): tudo vira unknown, volta ao mais próximo', () {
    // heading negativo => classify retorna unknown => nada é despriorizado.
    final r = NavigationScreen.pickUpcomingRadar([oposto(31), mesmo(200)], eu, -1, null);
    expect(r!.dir1, 180, reason: 'sem rumo confiável, não arriscamos esconder: mais próximo');
  });
}
