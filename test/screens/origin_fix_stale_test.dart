import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/screens/map_screen.dart';

// Guarda do fix de 19/08: a rota das 14:56 nasceu da origem GPS de 71 min
// antes (map_screen só buscava posição quando _origin era null) — 24 km de
// rota com o caminhão a 50 km dela, off_route imediato e reroute urgente.
void main() {
  final now = DateTime(2026, 8, 19, 14, 56);

  test('origem de busca/histórico (fixAt null) nunca é stale', () {
    expect(originFixIsStale(null, now), isFalse);
  });

  test('fix recente segue valendo como origem', () {
    expect(
      originFixIsStale(now.subtract(const Duration(minutes: 1)), now),
      isFalse,
    );
  });

  test('fix no limiar exato ainda vale (stale é estritamente depois)', () {
    expect(originFixIsStale(now.subtract(kOriginFreshFor), now), isFalse);
  });

  test('fix velho força re-busca (o caso dos 71 min do field)', () {
    expect(
      originFixIsStale(now.subtract(const Duration(minutes: 71)), now),
      isTrue,
    );
  });
}
