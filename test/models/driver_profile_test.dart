import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/driver_profile.dart';
import 'package:truck_router/utils/phone_mask.dart';

void main() {
  test('placa: normaliza e valida Mercosul e antiga', () {
    expect(DriverProfile.normalizePlate(' abc-1d23 '), 'ABC1D23');
    expect(DriverProfile.isValidPlate('ABC1D23'), isTrue);
    expect(DriverProfile.isValidPlate('ABC1234'), isTrue);
    expect(DriverProfile.isValidPlate(''), isTrue); // opcional
    expect(DriverProfile.isValidPlate('AB1234'), isFalse);
    expect(DriverProfile.isValidPlate('ABCD123'), isFalse);
  });

  test('telefone: só dígitos, DDD + 8/9', () {
    expect(DriverProfile.normalizePhone('(11) 99999-8888'), '11999998888');
    expect(DriverProfile.isValidPhone('11999998888'), isTrue);
    expect(DriverProfile.isValidPhone('1133334444'), isTrue);
    expect(DriverProfile.isValidPhone(''), isTrue); // opcional
    expect(DriverProfile.isValidPhone('999998888'), isFalse); // sem DDD
    expect(DriverProfile.isValidPhone('011999998888'), isFalse);
  });

  test('json: ida e volta, campos ausentes viram vazio', () {
    const p = DriverProfile(name: 'Beto', truck: 'Scania', plate: 'ABC1D23');
    final back = DriverProfile.fromJson(p.toJson());
    expect(back.name, 'Beto');
    expect(back.plate, 'ABC1D23');
    expect(back.phone, '');
    expect(DriverProfile.fromJson({'name': 'x'}).color, '');
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
