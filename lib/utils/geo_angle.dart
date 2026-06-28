/// Interpolação angular pelo MENOR arco entre dois rumos (graus, 0..360).
///
/// Usado pra suavizar a rotação heading-up da câmera de navegação: o bearing
/// alvo (segmento da rota) muda em degraus a cada vértice; aplicar este lerp a
/// ~30fps transforma o degrau num giro contínuo, sem "salto" na curva.
///
/// Escolhe sempre o caminho mais curto (ex: 350° → 10° passa por 0°, não dá a
/// volta de 340° pelo outro lado). [t] em 0..1 (0 = fica em [from], 1 = chega em
/// [to]). Resultado sempre normalizado em [0, 360).
double lerpAngleDeg(double from, double to, double t) {
  // Delta normalizado pra [-180, 180): o sinal indica o sentido do menor arco.
  final delta = ((to - from + 540) % 360) - 180;
  // O % do Dart com divisor positivo retorna sempre >= 0, então o resultado já
  // cai em [0, 360) sem ajuste extra.
  return (from + delta * t) % 360;
}
