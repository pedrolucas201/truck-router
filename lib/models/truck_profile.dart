class TruckProfile {
  final String id;
  final String name;
  final int heightCm;
  final int widthCm;
  final int lengthCm;
  final int weightKg;
  final int axleCount;

  const TruckProfile({
    required this.id,
    required this.name,
    required this.heightCm,
    this.widthCm = 260,
    required this.lengthCm,
    required this.weightKg,
    this.axleCount = 2,
  });

  Map<String, String> toHereParams() => {
        'vehicle[height]':      heightCm.toString(),
        'vehicle[width]':       widthCm.toString(),
        'vehicle[length]':      lengthCm.toString(),
        'vehicle[grossWeight]': weightKg.toString(),
        'vehicle[axleCount]':   axleCount.toString(),
      };

  TruckProfile copyWith({
    String? id,
    String? name,
    int? heightCm,
    int? widthCm,
    int? lengthCm,
    int? weightKg,
    int? axleCount,
  }) =>
      TruckProfile(
        id:        id        ?? this.id,
        name:      name      ?? this.name,
        heightCm:  heightCm  ?? this.heightCm,
        widthCm:   widthCm   ?? this.widthCm,
        lengthCm:  lengthCm  ?? this.lengthCm,
        weightKg:  weightKg  ?? this.weightKg,
        axleCount: axleCount ?? this.axleCount,
      );

  Map<String, dynamic> toJson() => {
        'id':        id,
        'name':      name,
        'heightCm':  heightCm,
        'widthCm':   widthCm,
        'lengthCm':  lengthCm,
        'weightKg':  weightKg,
        'axleCount': axleCount,
      };

  factory TruckProfile.fromJson(Map<String, dynamic> json) => TruckProfile(
        id:        json['id'] as String,
        name:      json['name'] as String,
        heightCm:  (json['heightCm'] as num).toInt(),
        widthCm:   (json['widthCm'] as num).toInt(),
        lengthCm:  (json['lengthCm'] as num).toInt(),
        weightKg:  (json['weightKg'] as num).toInt(),
        axleCount: (json['axleCount'] as num).toInt(),
      );

  String get summaryText =>
      '${(heightCm / 100).toStringAsFixed(1)}m alt  '
      '${(lengthCm / 100).toStringAsFixed(1)}m comp  '
      '${(weightKg / 1000).toStringAsFixed(0)}t  '
      '$axleCount eixos';
}
