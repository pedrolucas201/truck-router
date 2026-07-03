import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/screens/navigation_screen.dart';

// Guarda o discriminador do free-look (bug "do nada" — v2.4.x que voltava a cada
// release). Regra: um move de câmera cujo alvo bate (<40m) com algo que NÓS
// comandamos é eco do follow (ignora); só um alvo nunca comandado é o dedo.
void main() {
  const base = LatLng(-23.5, -46.6);
  final cmds = [
    base,
    const LatLng(-23.501, -46.601), // ~130m adiante (follow avançou)
    const LatLng(-23.502, -46.602),
  ];

  test('alvo idêntico a um comandado = eco (não é gesto)', () {
    expect(targetIsEcho(cmds, base), isTrue);
  });

  test('alvo a ~33m de um comandado = eco (callback atrasado pós-stall)', () {
    // 0.0003° de lat ≈ 33m — dentro do raio de 40m.
    expect(targetIsEcho(cmds, const LatLng(-23.5003, -46.6)), isTrue);
  });

  test('alvo a ~550m de qualquer comandado = dedo do usuário (free-look)', () {
    // 0.005° ≈ 555m — nenhum comandado por perto.
    expect(targetIsEcho(cmds, const LatLng(-23.505, -46.605)), isFalse);
  });

  test('buffer vazio não vira eco (nada comandado ainda)', () {
    expect(targetIsEcho(const [], base), isFalse);
  });
}
