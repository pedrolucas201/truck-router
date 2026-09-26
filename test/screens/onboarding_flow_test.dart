import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truck_router/providers/truck_profile_provider.dart';
import 'package:truck_router/screens/onboarding_screen.dart';

/// Percorre o fluxo "Monta o seu caminhão" sem plugin: permissões falsas e
/// "Começar" marca `onboarding_done`.
class _PermFake implements PermissoesApi {
  LocationPermission loc = LocationPermission.denied;
  int pedidosLoc = 0;
  int pedidosNotif = 0;
  @override
  Future<LocationPermission> localizacao() async => loc;
  @override
  Future<LocationPermission> pedirLocalizacao() async {
    pedidosLoc++;
    return loc = LocationPermission.denied;
  }
  @override
  Future<({double lat, double lng})?> posicao() async => null;
  @override
  Future<bool> notificacaoOk() async => pedidosNotif > 0;
  @override
  Future<void> pedirNotificacao() async => pedidosNotif++;
  @override
  Future<void> abrirAjustes() async {}
  @override
  Future<bool> ehXiaomi() async => true;
  @override
  Future<bool> abrirInicioAutomatico() async => true;
}

/// A cena anima em loop, então pumpAndSettle nunca assenta: avança o tempo na mão.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<(_PermFake, TruckProfileProvider, bool Function())> _abre(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  // markLocationAsked() lê a hora da instalação; sem mock o canal pendura.
  PackageInfo.setMockInitialValues(appName: 'No Trecho', packageName: 'com.truckrouter.truck_router', version: '0', buildNumber: '0', buildSignature: '', installerStore: null);
  final perm = _PermFake();
  final prov = TruckProfileProvider();
  await prov.load();
  var concluiu = false;
  await tester.binding.setSurfaceSize(const Size(400, 860));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: prov,
    child: MaterialApp(
      home: OnboardingScreen(permissoes: perm, aoConcluir: () => concluiu = true),
    ),
  ));
  await tester.pump();
  return (perm, prov, () => concluiu);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pular em tudo chega no Começar, grava onboarding_done e não grava caminhão', (tester) async {
    final (perm, prov, concluiu) = await _abre(tester);
    expect(find.text('Oi! Sou seu parceiro no trecho.'), findsOneWidget);
    expect(find.byKey(const Key('onb_pular')), findsNothing, reason: 'chegada não tem Pular');

    await tester.tap(find.byKey(const Key('onb_proxima'))); // Bora
    await settle(tester);
    expect(find.text('Com que caminhão você roda?'), findsOneWidget);
    expect(find.byKey(const Key('onb_tipo_meu')), findsNothing, reason: 'instalação limpa não tem "O meu"');

    await tester.tap(find.byKey(const Key('onb_pular'))); // garagem → local
    await settle(tester);
    expect(find.text('Deixa eu ver onde você está.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onb_pular'))); // local → ajuda (sem trecho)
    await settle(tester);
    expect(find.text('Deu problema? Quem está perto recebe.'), findsOneWidget);
    expect(perm.pedidosLoc, 0, reason: 'Pular não pede permissão');

    await tester.tap(find.byKey(const Key('onb_pular'))); // ajuda → bora
    await settle(tester);
    expect(find.text('Bora pro trecho?'), findsOneWidget);
    expect(find.text('Início automático (Xiaomi)'), findsOneWidget);
    expect(perm.pedidosNotif, 0);

    await tester.tap(find.byKey(const Key('onb_comecar')));
    await settle(tester);
    expect(concluiu(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_done'), isTrue);
    expect(prov.editado, isFalse, reason: 'pular não pode matar a restauração do espelho');
    expect(prov.profile.heightCm, 440, reason: 'padrão de fábrica = teto legal');
  });

  testWidgets('escolher Bitrem grava 7 eixos; negar localização pede uma vez e oferece cidade', (tester) async {
    final (perm, prov, _) = await _abre(tester);
    await tester.tap(find.byKey(const Key('onb_proxima')));
    await settle(tester);

    expect(tester.widget<FilledButton>(find.byKey(const Key('onb_e_esse'))).onPressed, isNull,
        reason: 'sem tipo escolhido não confirma');
    await tester.tap(find.byKey(const Key('onb_tipo_bitrem')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('onb_e_esse')));
    await settle(tester);
    expect(prov.profile.axleCount, 7);
    expect(prov.profile.weightKg, 57000);
    expect(prov.editado, isTrue);

    await tester.tap(find.byKey(const Key('onb_meu_trecho')));
    await settle(tester);
    expect(perm.pedidosLoc, 1);
    // Negou: abre a lista de cidades.
    expect(find.text('São Paulo'), findsOneWidget);
  });
}
