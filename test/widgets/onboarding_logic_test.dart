import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/models/truck_profile.dart';
import 'package:truck_router/screens/map_screen.dart';
import 'package:truck_router/widgets/onboarding/onboarding_logic.dart';
import 'package:truck_router/widgets/onboarding/trecho.dart';

/// Regras do onboarding "Monta o seu caminhão" que não podem regredir.
void main() {
  group('páginas', () {
    test('Pular: garagem → local; local e trecho → ajuda; ajuda → bora; chegada e bora sem Pular', () {
      expect(pularDestino(kPagChegada), isNull);
      expect(pularDestino(kPagGaragem), kPagLocal);
      expect(pularDestino(kPagLocal), kPagAjuda, reason: 'sem localização não há trecho pra mostrar');
      expect(pularDestino(kPagTrecho), kPagAjuda);
      expect(pularDestino(kPagAjuda), kPagBora);
      expect(pularDestino(kPagBora), isNull);
      expect(kTotalPaginas, kPagBora + 1);
    });

    test('a varredura aparece só em local e trecho', () {
      for (var p = 0; p < kTotalPaginas; p++) {
        expect(mostraVarredura(p), p == kPagLocal || p == kPagTrecho, reason: 'página $p');
      }
    });
  });

  group('garagem', () {
    test('⭐ altura padrão é o teto legal 4,40 m (falso alarme incomoda, sem alarme bate)', () {
      expect(kAlturaPadraoCm, 440);
      for (final t in TipoCaminhao.values) {
        expect(t.alturaCm, 440, reason: t.nome);
      }
    });

    test('tipos: eixos e pesos da Lei da Balança (conferidos 25/09/2026)', () {
      expect([for (final t in TipoCaminhao.values) t.eixos], [2, 3, 5, 7, 9]);
      expect(TipoCaminhao.toco.pesoKg, 16000); // 6 + 10 t
      expect(TipoCaminhao.truck.pesoKg, 23000); // 6 + 17 t
      expect(TipoCaminhao.carreta.pesoKg, 41500); // 6 + 10 + 25,5 t
      expect(TipoCaminhao.bitrem.pesoKg, 57000);
      expect(TipoCaminhao.rodotrem.pesoKg, 74000); // com AET
      for (final t in TipoCaminhao.values) {
        expect(t.comprimentoCm, lessThanOrEqualTo(3000), reason: t.nome);
      }
    });

    test('ajuste de altura: 5 em 5 cm, entre 3,00 e 4,80', () {
      expect(ajustaAltura(440, -5), 435);
      expect(ajustaAltura(300, -5), 300);
      expect(ajustaAltura(480, 5), 480);
    });

    test('pedágio do exemplo: tarifa por eixo × eixos, com vírgula', () {
      expect(pedagioExemplo(5), '5 eixos · R\$ 47,50');
      expect(pedagioExemplo(2), '2 eixos · R\$ 19,00');
      expect(pedagioExemplo(9), '9 eixos · R\$ 85,50');
    });

    test('escolher tipo dá nome ao caminhão de fábrica, nunca a um nome do motorista', () {
      expect(nomeDoCaminhao(atual: 'Padrão', tipo: TipoCaminhao.carreta), 'Carreta');
      expect(nomeDoCaminhao(atual: 'Scania do Beto', tipo: TipoCaminhao.carreta), 'Scania do Beto');
      expect(nomeDoCaminhao(atual: 'Padrão'), 'Padrão');
    });

    test('caminhão igual a um tipo marca o tipo; medidas próprias não casam', () {
      expect(tipoIgual(Medidas.doTipo(TipoCaminhao.carreta)), TipoCaminhao.carreta);
      expect(tipoIgual(const Medidas(alturaCm: 420, comprimentoCm: 1860, pesoKg: 41500, eixos: 5)), isNull);
    });

    test('cartão do caminhão atual mostra o nome dele, não "O meu"', () {
      expect(nomeDoAtual('Carreta'), 'Carreta');
      expect(nomeDoAtual('Padrão'), 'Seu atual');
    });

    test('"O meu" só aparece pra quem já tem caminhão (protege o espelho)', () {
      expect(abreComOMeu(editado: true), isTrue);
      expect(abreComOMeu(editado: false), isFalse);
    });

    test('confirmar sem mudar não grava nada', () {
      expect(
          caminhaoMudou(
              alturaCm: 440, comprimentoCm: 1400, pesoKg: 25000, eixos: 5,
              alturaAtualCm: 440, comprimentoAtualCm: 1400, pesoAtualKg: 25000, eixosAtual: 5),
          isFalse);
      final c = Medidas.doTipo(TipoCaminhao.carreta);
      expect(
          caminhaoMudou(
              alturaCm: c.alturaCm, comprimentoCm: c.comprimentoCm, pesoKg: c.pesoKg, eixos: c.eixos,
              alturaAtualCm: 440, comprimentoAtualCm: 1400, pesoAtualKg: 25000, eixosAtual: 5),
          isTrue);
    });
  });

  group('permissões', () {
    test('durante o uso já conta como concedida', () {
      expect(estadoLocalizacao(LocationPermission.whileInUse), PermissaoEstado.concedida);
      expect(estadoLocalizacao(LocationPermission.always), PermissaoEstado.concedida);
      expect(estadoLocalizacao(LocationPermission.denied), PermissaoEstado.pendente);
      expect(estadoLocalizacao(LocationPermission.deniedForever), PermissaoEstado.negadaDeVez);
    });

    test('depois do onboarding pedir, o boot não gasta a segunda negação', () {
      expect(shouldAskLocationOnBoot(LocationPermission.denied, true), isFalse);
    });
  });

  group('seu trecho', () {
    // Centro em São Paulo; ~0,009° ≈ 1 km.
    const lat = -23.55, lng = -46.63;
    RadarPoint radar(double dLat, String tipo, {int kmh = 60, int? oficial}) =>
        RadarPoint(lat: lat + dLat, lng: lng, type: tipo, speedKmh: kmh, truckLimitOff: oficial);
    BridgeRestriction viaduto(double dLat, double alturaM) =>
        BridgeRestriction(lat: lat + dLat, lng: lng, type: 'maxheight', value: alturaM);

    test('⭐ lombada e semáforo com câmera não contam como radar', () {
      final r = calcularTrecho(lat: lat, lng: lng, alturaCm: 440, restricoes: const [], radares: [
        radar(.01, 'Radar Fixo - 60 kmh'),
        radar(.02, 'Lombada - 0 kmh', kmh: 0),
        radar(.03, 'Semaforo com Camera - 0 kmh', kmh: 0),
        radar(.04, 'Semaforo com Radar - 50 kmh', kmh: 50),
      ]);
      expect(r.radares, 2);
    });

    test('passagem baixa: só a mais baixa que o caminhão, pela altura dele', () {
      final restr = [viaduto(.01, 4.30), viaduto(.02, 4.50), viaduto(.03, 3.80)];
      final alto = calcularTrecho(lat: lat, lng: lng, alturaCm: 440, radares: const [], restricoes: restr);
      expect(alto.caso, CasoTrecho.viadutos);
      expect(alto.viadutos, 2, reason: '4,30 e 3,80 < 4,40; 4,50 passa');
      final baixo = calcularTrecho(lat: lat, lng: lng, alturaCm: 350, radares: const [], restricoes: restr);
      expect(baixo.caso, isNot(CasoTrecho.viadutos), reason: 'caminhão de 3,50 passa em todas');
    });

    test('sem viaduto: mostra o radar mais perto com o limite de CAMINHÃO', () {
      final r = calcularTrecho(lat: lat, lng: lng, alturaCm: 440, restricoes: const [], radares: [
        radar(.05, 'Radar Fixo - 110 kmh', kmh: 110),
        radar(.02, 'Radar Fixo - 100 kmh', kmh: 100, oficial: 80),
      ]);
      expect(r.caso, CasoTrecho.radarMaisPerto);
      expect(r.radarKm, closeTo(2.2, .1));
      expect(r.radarLimite, 80, reason: 'o oficial de caminhão só abaixa');
      expect(r.titulo, contains('2,2 km'));
    });

    test('nada em 30 km expande pra 100 km; nada em 100 km é "tranquilo"', () {
      final longe = calcularTrecho(lat: lat, lng: lng, alturaCm: 440, restricoes: const [],
          radares: [radar(.6, 'Radar Fixo - 60 kmh')]); // ~67 km
      expect(longe.raioKm, 100);
      expect(longe.radares, 1);
      final nada = calcularTrecho(lat: lat, lng: lng, alturaCm: 440, restricoes: const [],
          radares: [radar(2.0, 'Radar Fixo - 60 kmh')]); // ~220 km
      expect(nada.caso, CasoTrecho.tranquilo);
    });

    test('texto nunca promete desvio (quem desvia é a rota da HERE)', () {
      final r = calcularTrecho(lat: lat, lng: lng, alturaCm: 440, radares: const [], restricoes: [viaduto(.01, 4.0)]);
      expect('${r.titulo} ${r.texto}'.toLowerCase(), isNot(contains('desvi')));
      expect(r.texto, contains('avisa'));
    });

    test('telemetria em faixas, nunca o número exato', () {
      expect([faixa(0), faixa(7), faixa(55), faixa(2052)], ['0', '1-10', '11-100', '100+']);
    });
  });
}
