// Termo 6.3.1 da Google Maps Platform: coordenada da Geocoding API pode ficar
// guardada por 30 dias e depois TEM de ser apagada. Cobre os dois lugares que
// guardam endereço (recentes do campo e histórico/favoritos de rota).
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truck_router/models/route_history.dart';
import 'package:truck_router/services/favorites_service.dart';
import 'package:truck_router/services/history_service.dart';
import 'package:truck_router/services/places_service.dart';
import 'package:truck_router/utils/google_cache.dart';

RouteHistory _route({required bool google, required DateTime at, String dest = 'B'}) =>
    RouteHistory(
      originLabel: 'A',
      originPosition: const LatLng(-23, -45),
      waypoints: const [],
      destinationLabel: dest,
      destinationPosition: const LatLng(-23.1, -45.1),
      distanceText: '1 km',
      durationText: '1 min',
      calculatedAt: at,
      google: google,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now    = DateTime.now();
  final old    = now.subtract(const Duration(days: 31));
  final recent = now.subtract(const Duration(days: 29));

  test('googleCacheExpired: 30 dias é o limite', () {
    expect(googleCacheExpired(now.subtract(const Duration(days: 30)), now), isFalse);
    expect(googleCacheExpired(now.subtract(const Duration(days: 30, seconds: 1)), now), isTrue);
  });

  test('RouteHistory: marca sobrevive ao JSON; entrada antiga sem a chave lê false', () {
    final j = _route(google: true, at: now).toJson();
    expect(RouteHistory.fromJson(j).google, isTrue);
    expect(RouteHistory.fromJson(j).copyWith(name: 'x').google, isTrue);
    j.remove('google');
    expect(RouteHistory.fromJson(j).google, isFalse);
  });

  test('histórico e favoritos: rota da Google some do disco após 30 dias; HERE fica', () async {
    final list = [
      _route(google: true,  at: old,    dest: 'google velha'),
      _route(google: true,  at: recent, dest: 'google no prazo'),
      _route(google: false, at: old,    dest: 'here velha'),
    ];
    SharedPreferences.setMockInitialValues({
      'route_history':      RouteHistory.listToJson(list),
      'favorite_routes_v1': RouteHistory.listToJson(list),
    });
    for (final load in [HistoryService.load, FavoritesService.load]) {
      final kept = await load();
      expect(kept.map((h) => h.destinationLabel), ['google no prazo', 'here velha']);
    }
    final prefs = await SharedPreferences.getInstance();
    for (final k in ['route_history', 'favorite_routes_v1']) {
      expect(RouteHistory.listFromJson(prefs.getString(k)!).length, 2, reason: '$k no disco');
    }
  });

  test('recentes: expira, re-escolha não renova o prazo, chamada nova renova', () async {
    SharedPreferences.setMockInitialValues({});
    const key = 'known_places_v1_destination';
    const pos = LatLng(-23, -45);
    final prefs = await SharedPreferences.getInstance();
    Future<void> age(DateTime to) async => prefs.setStringList(key, [
          for (final s in prefs.getStringList(key)!)
            s.replaceAll(RegExp(r'"at":\d+'), '"at":${to.millisecondsSinceEpoch}'),
        ]);

    await PlacesService.record('destination', 'rua x, 36', pos, google: true);
    await PlacesService.record('destination', 'rua here', pos);
    var all = await PlacesService.all('destination');
    expect(all.map((p) => (p.$1, p.$3)).toList(), [('rua here', false), ('rua x, 36', true)]);

    // 29 dias depois o motorista toca no recente: sobe na lista, marca fica,
    // data NÃO renova (o prazo conta da entrega da Google).
    await age(recent);
    await PlacesService.record('destination', 'rua x, 36', pos);
    all = await PlacesService.all('destination');
    expect(all.first, ('rua x, 36', pos, true));
    expect(prefs.getStringList(key)!.first, contains('"at":${recent.millisecondsSinceEpoch}'));

    // 31 dias: some da lista E do disco.
    await age(old);
    all = await PlacesService.all('destination');
    expect(all.map((p) => p.$1).toList(), ['rua here']);
    expect(prefs.getStringList(key)!.length, 1);

    // Busca nova na Google: volta com prazo novo.
    await PlacesService.record('destination', 'rua x, 36', pos, google: true);
    all = await PlacesService.all('destination');
    expect(all.map((p) => (p.$1, p.$3)).toList(), [('rua x, 36', true), ('rua here', false)]);
  });
}
