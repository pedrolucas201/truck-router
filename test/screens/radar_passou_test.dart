import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/screens/navigation_screen.dart';
import 'package:truck_router/services/firestore_radar_service.dart' show dismissalKey;

/// Esta é a única lógica do app que **cala um alerta de radar**, então o teste
/// existe pra provar o cinto de segurança, não a feature: radar em que o
/// caminhão nunca chegou não pode sumir da tela em hipótese nenhuma.
///
/// Sem alarme é multa; falso alarme é passável.
void main() {
  group('não suprime nada que o caminhão esteja se aproximando', () {
    test('radar longe, nunca alcançado: fica na tela', () {
      // 300 m de distância mínima. Mesmo que ele se afaste 1 km depois, nunca
      // chegou nele — pode ser que a rota ainda o leve lá.
      expect(NavigationScreen.radarPassou(d: 1300, dMin: 300), isFalse);
    });

    test('⭐ GPS pulando 40 m com o caminhão parado ANTES do radar', () {
      // O caso perigoso que derrubou o desenho por "distância cresceu" puro:
      // parado a 200 m do radar, accM ruim, a posição pula pra 245 m. Se isso
      // suprimisse, ele passaria pelo radar sem aviso nenhum.
      expect(NavigationScreen.radarPassou(d: 245, dMin: 200), isFalse);
    });

    test('quase chegando: 61 m é 1 m a mais que o limiar de chegada', () {
      expect(NavigationScreen.radarPassou(d: 200, dMin: 61), isFalse);
    });

    test('chegou mas ainda está em cima dele', () {
      expect(NavigationScreen.radarPassou(d: 10, dMin: 5), isFalse);
      expect(NavigationScreen.radarPassou(d: 44, dMin: 5), isFalse);
    });
  });

  group('suprime só depois de chegar E se afastar', () {
    test('passou por cima e seguiu', () {
      expect(NavigationScreen.radarPassou(d: 46, dMin: 5), isTrue);
    });

    test('pista oposta: mínimo de 25 m (largura do canteiro), depois afasta', () {
      // É o print do Beto na Dutra, 22/09.
      expect(NavigationScreen.radarPassou(d: 66, dMin: 25), isTrue);
      expect(NavigationScreen.radarPassou(d: 64, dMin: 25), isFalse);
    });

    test('limite exato da chegada (60 m) ainda conta como chegou', () {
      expect(NavigationScreen.radarPassou(d: 101, dMin: 60), isTrue);
    });
  });

  test('aproximar de novo traz o radar de volta', () {
    // Retorno: depois de suprimido a 46 m, ele volta. Assim que a distância
    // cai pra dentro da margem, o alerta reaparece.
    expect(NavigationScreen.radarPassou(d: 46, dMin: 5), isTrue);
    expect(NavigationScreen.radarPassou(d: 44, dMin: 5), isFalse);
  });

  test('⭐ retorno em pista dupla: o radar da OUTRA pista não fica calado na volta', () {
    // Reprodução do Beto em Caçapava (23/09, BR-116): na ida ele passa a ~13 m
    // (perpendicular) do radar da volta, que entra no corredor; depois faz o
    // retorno previsto na própria rota (sem reroute) e volta pela outra pista.
    const ida = RadarPoint(lat: -23.123165, lng: -45.727978, type: 'Radar Fixo',
        speedKmh: 110, dir1: 62, dirSrc: 'antt');
    const volta = RadarPoint(lat: -23.123118, lng: -45.728154, type: 'Radar Fixo',
        speedKmh: 110, dir1: 243, dirSrc: 'antt');
    LatLng mover(RadarPoint o, double metros, double rumo) {
      final b = rumo * math.pi / 180;
      return LatLng(o.lat + metros * math.cos(b) / 111320,
          o.lng + metros * math.sin(b) / (111320 * math.cos(o.lat * math.pi / 180)));
    }
    final distMin = <String, (double, double)>{};
    final vistos = <String>{};
    // Ida: de 300 m antes a 300 m depois do radar da ida, rumo 62°.
    for (var m = -300.0; m <= 300; m += 10) {
      NavigationScreen.tiraPassados([ida, volta], mover(ida, m, 62), 62, distMin, vistos);
    }
    // Volta, rumo 242°, pela pista do radar da volta: a 200 m dele tem que avisar.
    final naVolta = NavigationScreen.tiraPassados(
        [ida, volta], mover(volta, -200, 242), 242, distMin, vistos);
    expect(naVolta, contains(volta),
        reason: 'a 200 m do radar da pista dele, ele não pode estar suprimido');
  });

  test('⭐ pedido de 22/09 segue valendo: passou no mesmo sentido e parou, não volta', () {
    // Dutra: radar da pista oposta preso na tela depois de passar. Rumo da rota
    // constante (inclusive parado) = o mesmo "passou" continua valendo.
    const oposto = RadarPoint(lat: -23.123118, lng: -45.728154, type: 'Radar Fixo',
        speedKmh: 110, dir1: 243, dirSrc: 'antt');
    LatLng em(double metros) => LatLng(oposto.lat + metros * math.cos(62 * math.pi / 180) / 111320,
        oposto.lng + metros * math.sin(62 * math.pi / 180) / (111320 * math.cos(oposto.lat * math.pi / 180)));
    final distMin = <String, (double, double)>{};
    final vistos = <String>{};
    for (var m = -300.0; m <= 100; m += 10) {
      NavigationScreen.tiraPassados([oposto], em(m), 62, distMin, vistos);
    }
    for (var i = 0; i < 30; i++) { // parado 100 m depois, GPS no mesmo ponto
      expect(NavigationScreen.tiraPassados([oposto], em(100), 62, distMin, vistos), isEmpty);
    }
    expect(vistos, hasLength(1));
  });

  test('sem rota (rumo < 0) nunca reinicia; com rota invertida, reinicia', () {
    const r = RadarPoint(lat: -23.0, lng: -45.0, type: 'Radar Fixo', speedKmh: 60);
    final k = dismissalKey(r.lat, r.lng);
    const longe = LatLng(-23.0018, -45.0); // ~200 m
    Map<String, (double, double)> passou() => {k: (10.0, 62.0)};
    final semRota = passou();
    expect(NavigationScreen.tiraPassados([r], longe, -1, semRota, <String>{}), isEmpty);
    expect(semRota[k], (10.0, 62.0));
    final voltando = passou();
    expect(NavigationScreen.tiraPassados([r], longe, 242, voltando, <String>{}), [r]);
  });
}
