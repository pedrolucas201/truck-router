class RadarPoint {
  final double lat;
  final double lng;
  final String type;
  final int speedKmh;
  final String? id;    // doc no Firestore (null = veio do CSV estático)
  final String source; // 'csv' | 'user'

  const RadarPoint({
    required this.lat,
    required this.lng,
    required this.type,
    required this.speedKmh,
    this.id,
    this.source = 'csv',
  });
}
