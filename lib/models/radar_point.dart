class RadarPoint {
  final double lat;
  final double lng;
  final String type;
  final int speedKmh;
  final String? id;    // doc no Firestore (null = veio do CSV estático)
  final String source; // 'csv' | 'user'

  // Enriquecimento oficial (DNIT/ANTT via pipeline radar-enrich). Todos opcionais:
  // CSV antigo sem estas colunas => todos null (100% retrocompatível). Direção é
  // DECORAÇÃO VISUAL — nunca gate de alerta (invariante do projeto).
  final double? dir1;        // bearing do sentido fiscalizado (graus)
  final double? dir2;        // 2º sentido; != null => radar BIDIRECIONAL
  final String? dirSrc;      // 'dnit' | 'antt' | 'pass'
  final String? status;      // 'active' | 'inactive' (só de fonte oficial)
  final int? truckLimitOff;  // limite de caminhão oficial (só ABAIXA truckRadarLimit)
  // Nome da praça quando o pedágio vem da rota da HERE (`return=tolls`). Null
  // no CSV e no crowd. Só entra na fala e no chip; nunca é chave nem gate.
  final String? name;
  // Valor da praça (R$) pro perfil enviado à HERE (eixos incluídos). Só no
  // pedágio vindo da rota; null = sem dado, o chip mostra só o nome.
  final double? priceBrl;

  /// "Radar Movel" do MapaRadar = ponto onde a fiscalização costuma parar com
  /// radar portátil, não câmera fixa. Alerta igual (invariante), visual diferente:
  /// o Gilberto negava esses como "radar que não existe" (drive 2026-09-02).
  bool get isMovel {
    final t = type.toLowerCase();
    return t.contains('movel') || t.contains('móvel');
  }

  const RadarPoint({
    required this.lat,
    required this.lng,
    required this.type,
    required this.speedKmh,
    this.id,
    this.source = 'csv',
    this.dir1,
    this.dir2,
    this.dirSrc,
    this.status,
    this.truckLimitOff,
    this.name,
    this.priceBrl,
  });

  RadarPoint copyWith({
    int? speedKmh,
    double? dir1,
    double? dir2,
    String? dirSrc,
    String? status,
    int? truckLimitOff,
  }) =>
      RadarPoint(
        lat: lat,
        lng: lng,
        type: type,
        speedKmh: speedKmh ?? this.speedKmh,
        id: id,
        source: source,
        dir1: dir1 ?? this.dir1,
        dir2: dir2 ?? this.dir2,
        dirSrc: dirSrc ?? this.dirSrc,
        status: status ?? this.status,
        truckLimitOff: truckLimitOff ?? this.truckLimitOff,
        name: name,
        priceBrl: priceBrl,
      );
}
