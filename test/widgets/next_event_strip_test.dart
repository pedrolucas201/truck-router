import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/widgets/next_event_strip.dart';

void main() {
  group('tierFor', () {
    test('mapeia distância para o degrau certo', () {
      expect(tierFor(350), BadgeTier.near);
      expect(tierFor(799), BadgeTier.near);
      expect(tierFor(800), BadgeTier.mid);   // limite inferior do MID (inclusivo)
      expect(tierFor(1200), BadgeTier.mid);
      expect(tierFor(2000), BadgeTier.mid);  // limite superior do MID (inclusivo)
      expect(tierFor(2001), BadgeTier.far);
      expect(tierFor(5000), BadgeTier.far);
    });
  });
}
