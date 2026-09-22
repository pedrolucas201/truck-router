import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truck_router/models/truck_profile.dart';
import 'package:truck_router/providers/truck_profile_provider.dart';

/// O espelho dos caminhões é o único dado do app em que sobrescrever o local
/// pelo remoto pode mandar o motorista debaixo de um viaduto: a altura vive
/// aqui. O gate tem UM sentido — aparelho que o motorista configurou nunca
/// recebe nada do banco, e aparelho que nunca foi configurado nunca sobe nada
/// (senão o caminhão de fábrica apaga os reais que estão lá).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('podeRestaurar', () {
    test('aparelho novo com Google: restaura', () {
      expect(
          TruckProfileProvider.podeRestaurar(editado: false, temGoogle: true),
          isTrue);
    });

    test('aparelho JÁ configurado: nunca restaura', () {
      // O caso perigoso. Se isto virar true, a altura digitada neste celular
      // pode ser trocada pela de outro caminhão.
      expect(
          TruckProfileProvider.podeRestaurar(editado: true, temGoogle: true),
          isFalse);
    });

    test('sem Google não há de onde restaurar', () {
      // Uid anônimo troca sozinho; o doc do banco seria de outro uid.
      expect(
          TruckProfileProvider.podeRestaurar(editado: false, temGoogle: false),
          isFalse);
    });
  });

  group('flag de aparelho configurado', () {
    test('instalação limpa nasce MUDA (não sobe caminhão de fábrica)', () async {
      SharedPreferences.setMockInitialValues({});
      final p = TruckProfileProvider();
      await p.load();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('truck_editado'), isNot(true),
          reason: 'o padrão 4,20 m subiria por cima dos caminhões reais');
      expect(
          TruckProfileProvider.podeRestaurar(editado: false, temGoogle: true),
          isTrue);
    });

    test('formato antigo (truck_height em prefs) já conta como configurado',
        () async {
      // Ele digitou 4,40 m numa versão anterior ao multi-caminhão. Tratar esse
      // aparelho como novo deixaria o espelho trocar a altura real dele.
      SharedPreferences.setMockInitialValues({'truck_height': 440});
      final p = TruckProfileProvider();
      await p.load();

      expect(p.profile.heightCm, 440);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('truck_editado'), isTrue);
    });

    test('salvar um caminhão marca o aparelho e fecha a porta do banco',
        () async {
      SharedPreferences.setMockInitialValues({});
      final p = TruckProfileProvider();
      await p.load();
      await p.saveProfile(p.profile.copyWith(heightCm: 460));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('truck_editado'), isTrue);
      expect(
          TruckProfileProvider.podeRestaurar(editado: true, temGoogle: true),
          isFalse);
    });
  });

  test('caminhão de fábrica não fica ativo depois de restaurar', () async {
    // Regressão do furo que matou a fusão por id: o id nasce do relógio do
    // celular, então o caminhão restaurado entra como item NOVO. Se o ativo
    // não vier junto, ele navega com 4,20 m e o de 4,40 m fica parado na lista.
    SharedPreferences.setMockInitialValues({});
    final p = TruckProfileProvider();
    await p.load();
    final fabrica = p.profile.id;

    final real = TruckProfile(
      id: '1700000000000', name: 'Carreta',
      heightCm: 440, lengthCm: 1800, weightKg: 40000,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'truck_profiles_v2', [jsonEncode(real.toJson())]);
    await prefs.setString('truck_active_id', real.id);

    final recarregado = TruckProfileProvider();
    await recarregado.load();

    expect(recarregado.profile.id, isNot(fabrica));
    expect(recarregado.profile.heightCm, 440);
  });
}
