import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/services/radar_service.dart';

/// O dedupe roda antes de qualquer lógica de direção: o que ele descarta nunca
/// chega a alertar. Sem alarme é multa; falso alarme é passável.
void main() {
  RadarPoint r(double lat, double lng, {double? dir1, double? dir2, String? src = 'antt'}) =>
      RadarPoint(lat: lat, lng: lng, type: 'Radar Fixo', speedKmh: 110,
          dir1: dir1, dir2: dir2, dirSrc: dir1 == null ? null : src);

  test('⭐ Caçapava: radares de sentidos opostos a 19 m ficam os dois', () {
    // BR-116, áudio do Beto 23/09: o da volta (243°) era descartado e o da ida
    // aparecia como "sentido oposto".
    final ida = r(-23.123165, -45.727978, dir1: 62);
    final volta = r(-23.123118, -45.728154, dir1: 243);
    expect(RadarService.deduplicateNearby([ida, volta]), [ida, volta]);
  });

  test('mesmo sentido é o mesmo radar: fica um', () {
    final a = r(-23.123165, -45.727978, dir1: 62);
    final b = r(-23.123170, -45.727990, dir1: 58);
    expect(RadarService.deduplicateNearby([a, b]), [a]);
  });

  test('o que ficou sem direção ou bidirecional cobre qualquer vizinho', () {
    final semDir = r(-23.123165, -45.727978);
    final bidir = r(-23.123165, -45.727978, dir1: 62, dir2: 242);
    final unico = r(-23.123118, -45.728154, dir1: 243);
    expect(RadarService.deduplicateNearby([semDir, unico]), [semDir]);
    expect(RadarService.deduplicateNearby([bidir, unico]), [bidir]);
  });

  test('sentido único não cobre vizinho sem direção (pode ser da outra pista)', () {
    final unico = r(-23.123165, -45.727978, dir1: 62);
    final semDir = r(-23.123118, -45.728154);
    expect(RadarService.deduplicateNearby([unico, semDir]), [unico, semDir]);
  });

  test('direção sem fonte não vira sentido único (classificação dá unknown)', () {
    final semFonte = r(-23.123165, -45.727978, dir1: 62, src: null);
    final unico = r(-23.123118, -45.728154, dir1: 243);
    expect(RadarService.deduplicateNearby([semFonte, unico]), [semFonte]);
  });
}
