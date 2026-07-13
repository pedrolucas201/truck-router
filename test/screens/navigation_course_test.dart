import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/screens/navigation_screen.dart';

// Guarda o gate do `course` (o rumo que o app manda pra HERE no recálculo).
//
// P0 de campo 2026-07-13: 42 reroutes em 13 minutos, todos com course=null.
// O caminhão andava CONTRA a rota → não avançava NA rota → a velocidade "ao longo
// da rota" zerava → o gate do course olhava JUSTAMENTE essa velocidade → mandava
// null → a HERE recalculava sem saber pra onde ele apontava → devolvia a mesma
// meia-volta → hdgDelta seguia ~177° → rerotava de novo. Deadlock.
//
// Invariante que este teste crava: quem decide "confio no rumo?" olha a velocidade
// FÍSICA do GPS, nunca a velocidade ao longo da rota. Fonte única para as duas
// perguntas ("desviou?" e "mando o course?") — foi a divergência entre elas que
// criou o bug.
void main() {
  const kmh = 1 / 3.6; // m/s por km/h

  test('parado: rumo do GPS é ruído, não manda course', () {
    expect(headingIsReliable(0, 90), isFalse);
    expect(headingIsReliable(3 * kmh, 90), isFalse); // 3 km/h — jitter
  });

  test('andando: rumo confiável, manda course', () {
    expect(headingIsReliable(30 * kmh, 90), isTrue);
    expect(headingIsReliable(80 * kmh, 271), isTrue);
  });

  test('heading inválido (-1, GPS sem rumo) nunca é confiável', () {
    expect(headingIsReliable(80 * kmh, -1), isFalse);
  });

  // O CASO DO BUG: andando a 40 km/h de verdade, mas na contramão da rota — a
  // velocidade ao longo da rota é 0. O rumo continua confiável e o course TEM que
  // ir, senão a HERE recalcula cega e o storm não morre nunca.
  test('andando CONTRA a rota: rumo continua confiável (velocidade da rota=0)', () {
    const velocidadeFisica = 40 * kmh;
    expect(headingIsReliable(velocidadeFisica, 338), isTrue,
        reason: 'a velocidade ao longo da rota zera aqui — não pode calar o course');
  });

  test('o piso é o mesmo dos dois lados (fonte única)', () {
    expect(headingIsReliable((kRerouteCourseMinKmh - 0.1) * kmh, 0), isFalse);
    expect(headingIsReliable((kRerouteCourseMinKmh + 0.1) * kmh, 0), isTrue);
  });
}
