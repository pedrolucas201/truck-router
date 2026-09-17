import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/driver_profile.dart';
import 'package:truck_router/utils/phone_mask.dart';

void main() {
  // Placa migrou pra TruckProfile em 2.4.74: ver truck_profile_test.dart.
  test('telefone: só dígitos, DDD + 8/9', () {
    expect(DriverProfile.normalizePhone('(11) 99999-8888'), '11999998888');
    expect(DriverProfile.isValidPhone('11999998888'), isTrue);
    expect(DriverProfile.isValidPhone('1133334444'), isTrue);
    expect(DriverProfile.isValidPhone(''), isTrue); // opcional
    expect(DriverProfile.isValidPhone('999998888'), isFalse); // sem DDD
    expect(DriverProfile.isValidPhone('011999998888'), isFalse);
  });

  test('json: ida e volta, campos ausentes viram vazio', () {
    const p = DriverProfile(name: 'Beto', phone: '11999998888');
    final back = DriverProfile.fromJson(p.toJson());
    expect(back.name, 'Beto');
    expect(back.phone, '11999998888');
    expect(DriverProfile.fromJson({'name': 'x'}).phone, '');
  });

  test('perfil da pessoa não carrega mais caminhão', () {
    // A identidade do veículo mudou pra TruckProfile porque um campo só
    // anunciava o caminhão errado em quem roda mais de um. Se alguém
    // reintroduzir 'truck'/'color'/'plate' aqui, o dado volta a ser fake.
    expect(const DriverProfile(name: 'Beto').toJson().keys,
        unorderedEquals(['name', 'phone']));
  });

  test('máscara do telefone: celular, fixo, parcial, vazio, teto de 11', () {
    expect(PhoneMaskFormatter.mask('12999998888'), '(12) 99999-8888');
    expect(PhoneMaskFormatter.mask('1133334444'), '(11) 3333-4444');
    expect(PhoneMaskFormatter.mask('129'), '(12) 9');
    expect(PhoneMaskFormatter.mask('12'), '(12'); // fecha só com o 3º dígito, senão o backspace trava
    expect(PhoneMaskFormatter.mask(''), '');
    expect(PhoneMaskFormatter.mask('129999988889999'), '(12) 99999-8888');
    // ida e volta com a normalização do modelo
    expect(DriverProfile.normalizePhone(PhoneMaskFormatter.mask('12999998888')),
        '12999998888');
  });
}
