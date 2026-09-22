import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/field_log.dart';

/// O heartbeat de 30 s era o maior consumidor de escrita do projeto (~960 por
/// motorista em 8 h, contra 20.000/dia do Spark). Agrupar reduz 10×, mas só
/// vale se NÃO custar diagnóstico — e o que garante isso é a ordem: qualquer
/// evento esvazia o lote ANTES de si, então as amostras que antecedem um
/// off_route chegam junto com ele.
///
/// Se esta ordem inverter, o dado não some: chega DEPOIS do evento que
/// importava, e a leitura de campo passa a mentir sobre a sequência. É um erro
/// que nenhum crash denuncia, por isso ele tem teste.
void main() {
  late List<(String, Map<String, dynamic>)> escritas;

  setUp(() {
    escritas = [];
    FieldLog.limparLoteParaTeste();
    FieldLog.sinkDeTeste = (n, d) => escritas.add((n, d));
  });

  tearDown(() => FieldLog.sinkDeTeste = null);

  test('amostra nao escreve na hora', () {
    FieldLog.amostra('heartbeat', {'kmh': 60});
    expect(escritas, isEmpty, reason: 'seria 1 documento por amostra de novo');
  });

  test('fecha o lote sozinho no decimo', () {
    for (var i = 0; i < 10; i++) {
      FieldLog.amostra('heartbeat', {'kmh': i});
    }
    expect(escritas.length, 1);
    expect(escritas.single.$1, 'heartbeat');
    expect(escritas.single.$2['n'], 10);
    expect((escritas.single.$2['hb'] as List).length, 10);
    // Nenhuma amostra pode se perder no caminho.
    expect((escritas.single.$2['hb'] as List).first['kmh'], 0);
    expect((escritas.single.$2['hb'] as List).last['kmh'], 9);
  });

  test('⭐ evento esvazia o lote ANTES de si', () {
    FieldLog.amostra('heartbeat', {'kmh': 60});
    FieldLog.amostra('heartbeat', {'kmh': 0});
    FieldLog.event('off_route', {'offM': 250});

    expect(escritas.length, 2);
    expect(escritas[0].$1, 'heartbeat',
        reason: 'o lote tem que sair PRIMEIRO, senao a sequencia mente');
    expect(escritas[0].$2['n'], 2);
    expect(escritas[1].$1, 'off_route');
  });

  test('evento sem lote pendente nao escreve documento vazio', () {
    FieldLog.event('nav_start', {'wpts': 0});
    expect(escritas.length, 1);
    expect(escritas.single.$1, 'nav_start');
  });

  test('trocar de tipo de amostra fecha o lote anterior', () {
    // Senao o `event` do documento diria 'heartbeat' com outra coisa dentro.
    FieldLog.amostra('heartbeat', {'kmh': 60});
    FieldLog.amostra('outra_coisa', {'x': 1});
    expect(escritas.length, 1);
    expect(escritas.single.$1, 'heartbeat');
    expect(escritas.single.$2['n'], 1);
  });

  test('nav_end leva o lote junto (fim de viagem nao perde amostra)', () {
    for (var i = 0; i < 3; i++) {
      FieldLog.amostra('heartbeat', {'kmh': i});
    }
    FieldLog.event('nav_end', {'arrived': true});
    expect(escritas.length, 2);
    expect(escritas[0].$2['n'], 3);
    expect(escritas[1].$1, 'nav_end');
  });
}
