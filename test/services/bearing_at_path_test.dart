import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/services/radar_direction.dart';
import 'package:truck_router/services/radar_service.dart';

// Rumo da ROTA no ponto do radar (não o heading do GPS): é ele que classifica
// "pista oposta" desde a 2.4.71. Se este cair, a classificação volta a depender
// do rumo bruto do GPS e a supressão da voz vira roleta em curva/alça.
void main() {
  // rota indo pro LESTE (bearing ~90) num trecho, depois virando pro NORTE
  final path = [
    const LatLng(-23.0000, -46.0100),
    const LatLng(-23.0000, -46.0000), // segmento 1: leste
    const LatLng(-22.9900, -46.0000), // segmento 2: norte
  ];

  test('bearing do segmento mais próximo, no sentido da rota', () {
    // radar colado no segmento leste
    expect(RadarService.bearingAtPath(-23.0001, -46.0050, path), closeTo(90, 1.5));
    // radar colado no segmento norte
    expect(RadarService.bearingAtPath(-22.9950, -46.0001, path), closeTo(0, 1.5));
  });

  test('sem rota (menos de 2 pontos) devolve -1, que classifyRadarDirection trata como unknown', () {
    expect(RadarService.bearingAtPath(-23, -46, const [LatLng(-23, -46)]), -1);
    expect(
      classifyRadarDirection(dir1: 90, dir2: null, dirSrc: 'osm_geom', userHeading: -1),
      RadarDirMatch.unknown,
    );
  });

  test('radar da pista contrária (dir1 = 270) com a rota indo a 90 classifica opposite', () {
    final h = RadarService.bearingAtPath(-23.0001, -46.0050, path);
    expect(
      classifyRadarDirection(dir1: 270, dir2: null, dirSrc: 'osm_geom', userHeading: h),
      RadarDirMatch.opposite,
    );
    expect(
      classifyRadarDirection(dir1: 92, dir2: null, dirSrc: 'osm_geom', userHeading: h),
      RadarDirMatch.same,
    );
  });
}
