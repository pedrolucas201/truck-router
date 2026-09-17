import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:truck_router/screens/map_screen.dart';

/// A regra que não pode regredir: o boot pede a localização UMA vez e nunca
/// insiste. O Android promove a segunda negação a permanente — se o boot
/// gastar as duas, o motorista fica com um navegador que não navega e sem
/// saída dentro do app.
void main() {
  test('pede no primeiro boot sem permissão', () {
    expect(shouldAskLocationOnBoot(LocationPermission.denied, false), isTrue);
  });

  test('não insiste depois de já ter pedido', () {
    expect(shouldAskLocationOnBoot(LocationPermission.denied, true), isFalse);
  });

  test('nunca pede quando já está bloqueado de vez', () {
    // deniedForever: o diálogo não sobe mais, pedir aqui só queima o boot.
    // A saída é o botão de GPS com a ação AJUSTES.
    expect(
        shouldAskLocationOnBoot(LocationPermission.deniedForever, false), isFalse);
    expect(
        shouldAskLocationOnBoot(LocationPermission.deniedForever, true), isFalse);
  });

  test('não pede quando já tem permissão', () {
    for (final p in [
      LocationPermission.always,
      LocationPermission.whileInUse,
    ]) {
      expect(shouldAskLocationOnBoot(p, false), isFalse);
      expect(shouldAskLocationOnBoot(p, true), isFalse);
    }
  });
}
