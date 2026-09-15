import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/sos_request.dart';

void main() {
  SosRequest sos({String caminhao = 'Scania R450', String cor = 'Branco', SosTipo tipo = SosTipo.pneu}) =>
      SosRequest(
        id: 'x', uid: 'u', nome: 'Beto', caminhao: caminhao, cor: cor, tipo: tipo,
        texto: '', lat: -23.2, lng: -45.8, status: 'aberto',
        criadoEm: DateTime(2026, 9, 15), expireAt: DateTime(2026, 9, 15, 2),
      );

  test('voz: uma frase curta, km arredondado, tipo falado', () {
    expect(sosSpeech(sos(), 8.4), 'Motorista pedindo ajuda a 8 quilômetros. pneu.');
    expect(sosSpeech(sos(tipo: SosTipo.mecanica), 0.3),
        'Motorista pedindo ajuda a menos de 1 quilômetro. problema mecânico.');
  });

  test('distância: m abaixo de 1 km, km inteiro acima', () {
    expect(sosDistText(800), '800 m');
    expect(sosDistText(8400), '8 km');
  });

  test('caminhão + cor sem vírgula solta', () {
    expect(sos().caminhaoTexto, 'Scania R450 branco');
    expect(sos(cor: '').caminhaoTexto, 'Scania R450');
    expect(sos(caminhao: '', cor: '').caminhaoTexto, '');
  });

  test('tipo desconhecido vira outro; ativo respeita status e expireAt', () {
    expect(SosTipo.parse('guincho'), SosTipo.outro);
    final velho = SosRequest(
      id: 'x', uid: 'u', nome: 'B', caminhao: '', cor: '', tipo: SosTipo.outro,
      texto: '', lat: 0, lng: 0, status: 'aberto',
      criadoEm: DateTime(2020), expireAt: DateTime(2020, 1, 1, 2),
    );
    expect(velho.ativo, isFalse);
  });
}
