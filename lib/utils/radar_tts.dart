/// Frase do alerta de radar por voz. Curta de propósito — o motorista
/// reconhece nos primeiros segundos, sem texto longo cortando música/ligação.
/// Mantém o limite quando há (o alerta só dispara acima dele) no formato que o
/// brasileiro fala ("radar de 60"), sem ambiguidade com distância.
String radarAlertPhrase(int speedKmh) =>
    speedKmh > 0 ? 'Radar de $speedKmh à frente' : 'Radar à frente';

/// Frase do pedágio com o valor por EXTENSO. O TTS nunca recebe numeral de
/// dinheiro: "R$ 12,60" era loteria (lia "erre cifrão doze vírgula sessenta"),
/// motivo do d7e4202 ter deixado o valor só na tela. Pedido do Beto (16/09):
/// falar antes pra "preparar o bolso". Sem valor (HERE sem fare) fala só o nome.
String tollPhrase(String? name, double? priceBrl) {
  final quem = name == null ? 'Pedágio' : 'Pedágio $name';
  if (priceBrl == null || priceBrl <= 0) return '$quem à frente';
  return '$quem à frente, ${reaisPorExtenso(priceBrl)}';
}

/// 12.60 -> "doze reais e sessenta centavos"; 8.0 -> "oito reais";
/// 1.0 -> "um real"; 0.5 -> "cinquenta centavos". Até 999 reais (praça mais
/// cara do Brasil fica abaixo de 100).
String reaisPorExtenso(double v) {
  final total = (v * 100).round();
  final reais = total ~/ 100, cent = total % 100;
  final partes = <String>[];
  if (reais > 0) partes.add('${_extenso(reais)} ${reais == 1 ? 'real' : 'reais'}');
  if (cent > 0) partes.add('${_extenso(cent)} ${cent == 1 ? 'centavo' : 'centavos'}');
  return partes.isEmpty ? 'zero reais' : partes.join(' e ');
}

const _unidades = ['', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove',
  'dez', 'onze', 'doze', 'treze', 'catorze', 'quinze', 'dezesseis', 'dezessete', 'dezoito', 'dezenove'];
const _dezenas = ['', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa'];
const _centenas = ['', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos', 'seiscentos',
  'setecentos', 'oitocentos', 'novecentos'];

String _extenso(int n) {
  if (n == 100) return 'cem';
  if (n >= 1000) return '$n'; // ponytail: fora da faixa de pedágio, deixa o TTS ler o número
  final c = n ~/ 100, r = n % 100;
  final d = r ~/ 10, u = r % 10;
  final p = <String>[];
  if (c > 0) p.add(_centenas[c]);
  if (r > 0) {
    if (r < 20) {
      p.add(_unidades[r]);
    } else {
      p.add(u > 0 ? '${_dezenas[d]} e ${_unidades[u]}' : _dezenas[d]);
    }
  }
  return p.join(' e ');
}
