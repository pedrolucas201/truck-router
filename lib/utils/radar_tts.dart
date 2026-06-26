/// Frase do alerta de radar por voz. Curta de propósito — o motorista
/// reconhece nos primeiros segundos, sem texto longo cortando música/ligação.
/// Mantém o limite quando há (o alerta só dispara acima dele) no formato que o
/// brasileiro fala ("radar de 60"), sem ambiguidade com distância.
String radarAlertPhrase(int speedKmh) =>
    speedKmh > 0 ? 'Radar de $speedKmh à frente' : 'Radar à frente';
