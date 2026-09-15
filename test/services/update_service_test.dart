import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/update_service.dart';

void main() {
  const json = {
    'build': 156, 'version': '2.4.69', 'url': 'https://x/apk', 'sha256': 'abc',
    'minBuild': 150, 'notes': 'S.O.S. com aviso',
  };

  test('oferece só build maior; dev/igual/maior instalado não oferece', () {
    final u = parseUpdate(json, 155)!;
    expect(u.build, 156);
    expect(u.sha256, 'abc');
    expect(u.force, isFalse);
    expect(parseUpdate(json, 156), isNull, reason: 'já está nela');
    expect(parseUpdate(json, 157), isNull, reason: 'instalado mais novo (build local)');
    expect(parseUpdate(json, null), isNull, reason: 'flutter run = dev');
    expect(parseUpdate({...json, 'url': ''}, 155), isNull, reason: 'sem url não tem o que baixar');
    expect(parseUpdate(const {'build': 'x'}, 155), isNull, reason: 'json torto');
    expect(parseUpdate(json, 149)!.force, isTrue, reason: 'abaixo do minBuild');
  });

  test('build instalado sai do APP_VERSION', () {
    expect(currentBuild('2.4.68+155'), 155);
    expect(currentBuild('dev'), isNull);
    expect(currentBuild('2.4.67-sos2'), isNull);
  });
}
