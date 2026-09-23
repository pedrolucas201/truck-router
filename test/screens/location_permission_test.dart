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

  group('marca de "já pedimos" é por INSTALAÇÃO', () {
    const inst = 1000, outra = 2000;

    test('reinstalação com prefs do backup pergunta de novo', () {
      // Auto Backup devolve a marca da instalação antiga; a permissão veio zerada.
      expect(locationAskedThisInstall(marcadoEm: inst, instalacao: outra, legado: true),
          isFalse);
    });

    test('mesma instalação (atualização por cima) não insiste', () {
      expect(locationAskedThisInstall(marcadoEm: inst, instalacao: inst, legado: true),
          isTrue);
    });

    test('migração: marca antiga sem hora vale pra instalação atual', () {
      // Quem negou de propósito não pode tomar o diálogo de novo só por atualizar.
      expect(locationAskedThisInstall(instalacao: inst, legado: true), isTrue);
      expect(locationAskedThisInstall(instalacao: inst, legado: false), isFalse);
    });

    test('sem hora de instalação vale a regra antiga', () {
      expect(locationAskedThisInstall(legado: true), isTrue);
      expect(locationAskedThisInstall(legado: false), isFalse);
    });
  });
}
