import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/screens/navigation_screen.dart';

// Guarda o discriminador do free-look (bug "do nada" — o P0 que voltava a cada
// release). Regra: um move de câmera cujo alvo bate com algo que NÓS comandamos é
// eco do follow (ignora); só um alvo nunca comandado é o dedo.
//
// A tolerância do eco é em PIXELS, não em metros: o erro que ela absorve é o
// offset do padding da câmera (o mapa é padded pra jogar o puck embaixo), que é
// fixo em pixels e por isso QUADRUPLICA em metros a cada 2 níveis de zoom.
// Era 40m fixos — passava por sorte no zoom 17 e explodia no 15.
void main() {
  // Níveis reais do app: recuado=15, medio=17 (padrão), aproximado=19.
  const zoomRecuado = 15.0;
  const zoomMedio = 17.0;
  const zoomAproximado = 19.0;

  const base = LatLng(-23.5, -46.6);
  final cmds = [base];

  // ~1° de latitude = 111.320 m.
  LatLng norteDe(LatLng p, double metros) =>
      LatLng(p.latitude + metros / 111320.0, p.longitude);

  group('eco do padding da câmera (não é dedo)', () {
    test('alvo idêntico a um comandado = eco, em qualquer zoom', () {
      for (final z in [zoomRecuado, zoomMedio, zoomAproximado]) {
        expect(targetIsEcho(cmds, base, z), isTrue, reason: 'zoom $z');
      }
    });

    // REGRESSÃO (field Gilberto 2026-07-13): no zoom recuado o offset do padding
    // mede ~127m. Com os 40m fixos antigos isso NÃO era eco → o app lia todo
    // moveCamera nosso como dedo → free-look → botão azul voltando sozinho.
    test('offset de 127m no zoom RECUADO = eco (o bug do botão azul)', () {
      expect(targetIsEcho(cmds, norteDe(base, 127), zoomRecuado), isTrue);
    });

    test('offset de 32m no zoom MÉDIO = eco (o mesmo padding, 4x menor)', () {
      expect(targetIsEcho(cmds, norteDe(base, 32), zoomMedio), isTrue);
    });
  });

  group('arrasto real do usuário (é dedo)', () {
    test('600m no zoom recuado = dedo (bem além do padding)', () {
      expect(targetIsEcho(cmds, norteDe(base, 600), zoomRecuado), isFalse);
    });

    // No zoom aproximado a tolerância NÃO aperta: fica no piso de 40m (a de hoje).
    // A conta em pixels daria ~16m ali, e apertar plantaria free-look espúrio novo.
    test('50m no zoom APROXIMADO = dedo (piso de 40m preservado)', () {
      expect(targetIsEcho(cmds, norteDe(base, 50), zoomAproximado), isFalse);
    });

    test('30m no zoom APROXIMADO = eco (o piso antigo continua valendo)', () {
      expect(targetIsEcho(cmds, norteDe(base, 30), zoomAproximado), isTrue);
    });

    test('buffer vazio não vira eco (nada comandado ainda)', () {
      expect(targetIsEcho(const [], base, zoomMedio), isFalse);
    });
  });

  group('metersPerPixel', () {
    test('quadruplica a cada 2 níveis de zoom (a raiz do bug)', () {
      final z15 = metersPerPixel(15, -23.5);
      final z17 = metersPerPixel(17, -23.5);
      expect(z15 / z17, closeTo(4.0, 0.01));
    });
  });

  // O PORTÃO DURO. Estes são os gates de verdade: valem pra QUALQUER zoom e
  // QUALQUER tamanho de tela, porque não dependem do offset do padding — que é a
  // grandeza que a gente não consegue medir da bancada e que fez este P0 voltar
  // release após release.
  group('cameraMoveIsGesture — gesto exige dedo', () {
    // REGRESSÃO do campo 2026-07-13: 6 free-looks com panM=127m (alvo divergente,
    // isEcho=false) e NINGUÉM tocando na tela. Era o settle da câmera. Com o portão
    // do dedo, morre — não importa quanto o padding deslocou nem em que zoom.
    test('settle de câmera SEM toque nunca é gesto (o botão azul sozinho)', () {
      expect(
        cameraMoveIsGesture(
          touchAgeMs: -1, // nunca tocou no mapa
          isEcho: false, // alvo bem divergente (offset do padding)
          fingerActive: false,
          zoomJustChanged: false,
        ),
        isFalse,
      );
    });

    test('toque velho (fora da janela) não ressuscita gesto', () {
      expect(
        cameraMoveIsGesture(
          touchAgeMs: kGestureGraceMs + 1,
          isEcho: false,
          fingerActive: false,
          zoomJustChanged: false,
        ),
        isFalse,
      );
    });

    test('arrasto lateral com dedo = gesto', () {
      expect(
        cameraMoveIsGesture(
          touchAgeMs: 50,
          isEcho: false, // levou a câmera pra um alvo que nunca comandamos
          fingerActive: true,
          zoomJustChanged: false,
        ),
        isTrue,
      );
    });

    // Arrasto COLINEAR (pra frente): cai perto da rota, então parece eco. Só o dedo
    // salva — é o "item 1 do Gilberto". Não pode regredir com o portão novo.
    test('arrasto COLINEAR (alvo parece eco) ainda é gesto pelo dedo', () {
      expect(
        cameraMoveIsGesture(
          touchAgeMs: 20,
          isEcho: true, // alvo colinear, indistinguível do follow
          fingerActive: true,
          zoomJustChanged: false,
        ),
        isTrue,
      );
    });

    // O settle do cycle de zoom: é move nosso. Mesmo que o dedo tenha acabado de
    // tocar o BOTÃO, o alvo divergente do settle não pode virar olhar-ao-redor.
    test('settle do cycle de zoom não vira gesto (_zoomJustChanged)', () {
      expect(
        cameraMoveIsGesture(
          touchAgeMs: 100,
          isEcho: false,
          fingerActive: false,
          zoomJustChanged: true,
        ),
        isFalse,
      );
    });

    test('eco do follow com dedo parado na tela não vira gesto sozinho', () {
      expect(
        cameraMoveIsGesture(
          touchAgeMs: 500, // tocou há pouco, mas o dedo já saiu
          isEcho: true, // e o alvo é nosso
          fingerActive: false,
          zoomJustChanged: false,
        ),
        isFalse,
      );
    });
  });
}
