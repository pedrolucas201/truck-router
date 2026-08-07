enum RouteEventType { radar, restriction, police, scale, restArea, weather, dirtRoad }

class RouteEvent {
  final RouteEventType type;
  final double distanceM;
  // Rótulo específico (ex: "Chuva"/"Vento"/"Neblina" pro clima). Null = usa o
  // rótulo padrão do tipo.
  final String? label;

  const RouteEvent({required this.type, required this.distanceM, this.label});
}
