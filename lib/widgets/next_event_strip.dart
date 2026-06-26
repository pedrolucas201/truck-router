/// Degrau de proximidade do próximo evento. Controla visibilidade e destaque
/// da faixa. Breakpoints iniciais (tunáveis em campo): 2 km / 800 m.
enum BadgeTier { far, mid, near }

/// FAR: > 2 km · MID: 800 m–2 km (inclusivo nas pontas) · NEAR: < 800 m.
BadgeTier tierFor(double distanceM) {
  if (distanceM < 800) return BadgeTier.near;
  if (distanceM <= 2000) return BadgeTier.mid;
  return BadgeTier.far;
}
