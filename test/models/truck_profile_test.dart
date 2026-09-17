import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/truck_profile.dart';

void main() {
  test('placa: normaliza e valida Mercosul e antiga', () {
    expect(TruckProfile.normalizePlate(' abc-1d23 '), 'ABC1D23');
    expect(TruckProfile.isValidPlate('ABC1D23'), isTrue);
    expect(TruckProfile.isValidPlate('ABC1234'), isTrue);
    expect(TruckProfile.isValidPlate(''), isTrue); // opcional
    expect(TruckProfile.isValidPlate('AB1234'), isFalse);
    expect(TruckProfile.isValidPlate('ABCD123'), isFalse);
  });

  /// O que não pode regredir: um perfil gravado ANTES da 2.4.74 não tem
  /// model/color/plate. Se o fromJson voltar a fazer cast direto, o primeiro
  /// boot depois do update joga fora o caminhão do motorista — e com ele as
  /// dimensões que decidem se ele passa embaixo do viaduto.
  test('json antigo (sem identidade) carrega sem perder as dimensões', () {
    final p = TruckProfile.fromJson({
      'id': '1', 'name': 'Bitrem', 'heightCm': 440, 'widthCm': 260,
      'lengthCm': 1900, 'weightKg': 57000, 'axleCount': 9,
    });
    expect(p.heightCm, 440);
    expect(p.weightKg, 57000);
    expect(p.model, '');
    expect(p.color, '');
    expect(p.plate, '');
  });

  test('json: ida e volta preserva identidade', () {
    const p = TruckProfile(
      id: '1', name: 'Truck', heightCm: 420, lengthCm: 1400, weightKg: 25000,
      model: 'Scania R450', color: 'Branco', plate: 'ABC1D23',
    );
    final back = TruckProfile.fromJson(p.toJson());
    expect(back.model, 'Scania R450');
    expect(back.color, 'Branco');
    expect(back.plate, 'ABC1D23');
    expect(back.axleCount, 5);
  });

  test('identidadeTexto: sem vírgula solta quando falta campo', () {
    const base = TruckProfile(
        id: '1', name: 'x', heightCm: 420, lengthCm: 1400, weightKg: 25000);
    expect(base.copyWith(model: 'Scania R450', color: 'Branco').identidadeTexto,
        'Scania R450 branco');
    expect(base.copyWith(model: 'Scania R450').identidadeTexto, 'Scania R450');
    expect(base.copyWith(color: 'Branco').identidadeTexto, 'branco');
    expect(base.identidadeTexto, '');
  });
}
