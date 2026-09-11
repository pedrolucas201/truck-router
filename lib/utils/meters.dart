/// Campos de medida do caminhão em metros na tela ("4,20"), centímetros no
/// modelo/HERE. Aceita vírgula ou ponto. Pedido do Gilberto (10/09/2026).
int? metersToCm(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || v.isNaN || v.isInfinite) return null;
  return (v * 100).round();
}

String cmToMeters(int cm) => (cm / 100).toStringAsFixed(2).replaceAll('.', ',');
