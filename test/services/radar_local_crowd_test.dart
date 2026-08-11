import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/services/firestore_radar_service.dart';

// O radar ADICIONADO pelo motorista era o único dado crowd sem cópia local: o
// override (negar radar / corrigir velocidade) sempre sobreviveu sem rede, o radar
// marcado não. Quando a cota diária de leitura do Spark estoura, o Firestore
// devolve vazio e o radar sumia — e radar que some é ALERTA QUE NÃO TOCA, multa.
//
// Os dois lados aqui: sobreviver ao Firestore vazio, e NÃO duplicar quando ele
// responde (o mesmo radar viria do remoto e do local = dois marcadores no mesmo m²).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Polyline DENSA, como a que a HERE devolve (~11 m entre vértices). Densidade
  // importa: isNearRoute amostra de 5 em 5 vértices e mede até o vértice, não até
  // o segmento — com rota rala ela não enxerga um radar em cima da própria rota.
  final rota = List.generate(
      20, (i) => LatLng(-23.2800 + i * 0.0001, -45.8990 + i * 0.0001));
  final marcadoLat = rota[10].latitude, marcadoLng = rota[10].longitude;

  RadarPoint marcado({String? id}) => RadarPoint(
      lat: marcadoLat, lng: marcadoLng, type: 'Radar', speedKmh: 60,
      id: id, source: 'user');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('radar marcado sobrevive ao Firestore devolver vazio', () async {
    await FirestoreRadarService.addLocal(marcado());

    // Simula o que o catch da cota estourada entrega: nada do servidor.
    final naTela = FirestoreRadarService.mergeLocalCrowd(
        const [], [marcado()], rota);

    expect(naTela.length, 1, reason: 'sem isto, cota estourada = radar sem alerta');
    expect(naTela.first.lat, marcadoLat);
  });

  test('não duplica quando o Firestore responde com o mesmo radar', () {
    final doServidor = marcado(id: 'doc123');
    final naTela = FirestoreRadarService.mergeLocalCrowd(
        [doServidor], [marcado()], rota);

    expect(naTela.length, 1, reason: 'dois marcadores no mesmo ponto e alerta dobrado');
    expect(naTela.first.id, 'doc123', reason: 'o remoto manda: é ele que tem id e votos');
  });

  test('radar local fora da rota atual não entra', () {
    final longe = RadarPoint(
        lat: -23.5000, lng: -46.6000, type: 'Radar', speedKmh: 60, source: 'user');
    final naTela = FirestoreRadarService.mergeLocalCrowd(const [], [longe], rota);

    expect(naTela, isEmpty);
  });

  test('persiste entre sessões: o que foi marcado volta depois de reabrir', () async {
    await FirestoreRadarService.addLocal(marcado());
    // Regravar com o id (o que o navigation_screen faz quando o Firestore aceita)
    // sobrescreve pela chave de local, não cria um segundo.
    await FirestoreRadarService.addLocal(marcado(id: 'doc123'));

    final salvo = SharedPreferences.getInstance();
    expect(await salvo.then((p) => p.getString('radar_crowd_local')), isNotNull);
  });
}
