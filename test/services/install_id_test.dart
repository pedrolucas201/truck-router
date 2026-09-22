import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truck_router/services/install_id.dart';

/// O id do aparelho é o que impede um motorista sozinho de atravessar o piso de
/// 3 votos quando o uid do Firebase troca a cada abertura. Se ele mudar entre
/// aberturas, o conserto não conserta nada — a estabilidade É a feature.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('estavel: a segunda leitura devolve o mesmo id', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await InstallId.get();
    final b = await InstallId.get();
    expect(a, b);
    expect(InstallId.valido(a), isTrue);
  });

  test('persiste em prefs, nao so em memoria', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await InstallId.get();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('install_id'), a,
        reason: 'sem disco, todo boot viraria um votante novo');
  });

  test('lixo em prefs e substituido em vez de enviado', () async {
    // O servidor recusa o que não casa com 32 hex e cai no uid; gravar lixo
    // aqui significaria contar por uid pra sempre, sem ninguém perceber.
    SharedPreferences.setMockInitialValues({'install_id': 'nao-sou-hex'});
    final a = await InstallId.get();
    expect(InstallId.valido(a), isTrue);
    expect(a, isNot('nao-sou-hex'));
  });

  test('gerar produz 32 hex minusculo e nao repete', () {
    final a = InstallId.gerar();
    final b = InstallId.gerar();
    expect(InstallId.valido(a), isTrue);
    expect(a.length, 32);
    expect(a, isNot(b));
  });

  test('valido recusa o que o servidor recusaria', () {
    expect(InstallId.valido('0123456789abcdef0123456789abcdef'), isTrue);
    expect(InstallId.valido('0123456789ABCDEF0123456789ABCDEF'), isFalse);
    expect(InstallId.valido('curto'), isFalse);
    expect(InstallId.valido(''), isFalse);
    expect(InstallId.valido('0123456789abcdef0123456789abcdefx'), isFalse);
  });
}
