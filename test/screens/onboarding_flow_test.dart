import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truck_router/providers/truck_profile_provider.dart';
import 'package:truck_router/screens/onboarding_screen.dart';

/// Percorre o fluxo inteiro sem plugin: permissões falsas, caminhão padrão
/// (não grava), e "Começar" marca `onboarding_done`.
class _PermFake implements PermissoesApi {
  LocationPermission loc = LocationPermission.denied;
  int pedidosLoc = 0;
  @override
  Future<LocationPermission> localizacao() async => loc;
  @override
  Future<LocationPermission> pedirLocalizacao() async {
    pedidosLoc++;
    return loc = LocationPermission.whileInUse;
  }
  @override
  Future<bool> notificacaoOk() async => true;
  @override
  Future<void> pedirNotificacao() async {}
  @override
  Future<bool> bateriaIsenta() async => false;
  @override
  Future<void> pedirBateria() async {}
  @override
  Future<void> abrirAjustes() async {}
  @override
  Future<bool> ehXiaomi() async => true;
  @override
  Future<bool> abrirInicioAutomatico() async => true;
}

/// A pista anima em loop, então pumpAndSettle nunca assenta: avança o tempo na mao.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('7 páginas, Pular cai no caminhão, Começar grava onboarding_done', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // markLocationAsked() le a hora da instalacao; sem mock o canal pendura.
    PackageInfo.setMockInitialValues(appName: 'No Trecho', packageName: 'com.truckrouter.truck_router', version: '0', buildNumber: '0', buildSignature: '', installerStore: null);
    final perm = _PermFake();
    var concluiu = false;
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => TruckProfileProvider(),
      child: MaterialApp(
        home: OnboardingScreen(permissoes: perm, aoConcluir: () => concluiu = true),
      ),
    ));
    await tester.pump();

    expect(find.text('Feito pra quem vive no trecho.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onb_proxima')));
    await settle(tester);
    expect(find.text('A rota que cabe no seu caminhão.'), findsOneWidget);

    // Pular na 2ª tela → cadastro do caminhão
    await tester.tap(find.byKey(const Key('onb_pular')));
    await settle(tester);
    expect(find.text('Com que caminhão você roda?'), findsOneWidget);
    expect(find.byKey(const Key('onb_pular')), findsNothing);

    // Próxima com o padrão → permissões (sem gravar caminhão)
    await tester.tap(find.byKey(const Key('onb_proxima')));
    await settle(tester);
    expect(find.text('Pra avisar com a tela apagada.'), findsOneWidget);
    expect(find.text('Início automático (Xiaomi)'), findsOneWidget);
    expect(find.text('Começar'), findsOneWidget);

    // Pedir localização pelo cartão
    final btn = find.widgetWithText(OutlinedButton, 'Permitir').first;
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await settle(tester);
    expect(perm.pedidosLoc, 1);
    expect(find.text('Permitir sempre'), findsOneWidget);

    // Começar libera mesmo com bateria pendente
    await tester.tap(find.byKey(const Key('onb_proxima')));
    await settle(tester);
    expect(concluiu, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_done'), isTrue);
    // e a marca de "já pediu localização" existe pro boot não pedir de novo
    expect(prefs.getBool('location_asked'), isTrue);
  });
}
