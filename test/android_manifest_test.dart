// Trava do fix da task do WhatsApp (12/08/2026).
//
// O bug "abri a localização do WhatsApp e não consigo mais ver o WhatsApp" já
// voltou 4 vezes, sempre por ser atacado no Dart. A cura real é uma linha de
// XML — e linha de XML é justamente o que um merge, um upgrade de Flutter ou um
// `flutter create` de reparo desfaz sem ninguém notar. Este teste roda no
// `flutter test` que já é obrigatório antes do release, então a regressão
// aparece aqui em vez de aparecer na estrada.
//
// Não substitui teste em device: comportamento de task não é testável em
// flutter test. Isto só garante que a configuração que funcionou continua lá.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidManifest — task do deep link (regressão do WhatsApp)', () {
    final xml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('MainActivity é singleTask', () {
      expect(
        xml.contains('android:launchMode="singleTask"'),
        isTrue,
        reason: 'Sem singleTask o Android empilha a MainActivity dentro da task '
            'do app que abriu o link (WhatsApp) e o motorista fica preso.',
      );
      expect(
        xml.contains('android:launchMode="singleTop"'),
        isFalse,
        reason: 'singleTop é o valor que causava o bug. Não voltar.',
      );
    });

    test('taskAffinity vazia não voltou', () {
      expect(
        xml.contains('android:taskAffinity=""'),
        isFalse,
        reason: 'Com affinity nula o singleTask não reencontra a task existente '
            'e cada link abre uma task nova do app.',
      );
    });

    test('os intent-filters de localização compartilhada continuam lá', () {
      // Se o filtro sumir, o app nem aparece no chooser do WhatsApp — o sintoma
      // seria "o app parou de receber localização", não este bug.
      expect(xml.contains('android:scheme="geo"'), isTrue);
      expect(xml.contains('android:host="maps.google.com"'), isTrue);
      expect(xml.contains('android:host="maps.app.goo.gl"'), isTrue);
    });
  });

  test('canal do push do S.O.S. tem o mesmo id no app, no manifest e no backend', () {
    // Id divergente = o push cai no "Diversos" do FCM, que o MIUI esconde
    // (18/09: badge no ícone e nada na barra). Falha em silêncio, só na estrada.
    final xml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final kt = File('android/app/src/main/kotlin/com/truckrouter/truck_router/MainActivity.kt')
        .readAsStringSync();
    final go = File('backend/internal/handlers/sos_push.go').readAsStringSync();
    expect(
        RegExp(r'default_notification_channel_id"\s+android:value="sos"').hasMatch(xml),
        isTrue);
    expect(kt, contains('NotificationChannel("sos"'));
    expect(kt, contains('IMPORTANCE_HIGH'));
    expect(go, contains('ChannelID: "sos"'));
  });
}
