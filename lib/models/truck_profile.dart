/// Um caminhão do motorista. Além das dimensões (que decidem a rota), carrega
/// a identidade VISUAL — modelo, cor e placa — porque é o que o outro motorista
/// precisa pra achar este caminhão na estrada quando alguém pede S.O.S.
///
/// Isso morava em `DriverProfile`, num campo só, e produzia dado falso em quem
/// roda mais de um caminhão: a ficha do S.O.S. anunciava a carreta branca com o
/// cara dirigindo o truck azul. Aqui fica certo por construção — o S.O.S. copia
/// do perfil ATIVO, o mesmo que já decide se o caminhão passa embaixo do
/// viaduto. Quem confia nele pra não bater pode confiar pra ser encontrado.
class TruckProfile {
  final String id;
  final String name;
  final int heightCm;
  final int widthCm;
  final int lengthCm;
  final int weightKg;
  final int axleCount;
  final String model; // texto livre: "Scania R450"
  final String color;
  final String plate; // normalizada: "ABC1D23"

  const TruckProfile({
    required this.id,
    required this.name,
    required this.heightCm,
    this.widthCm = 260,
    required this.lengthCm,
    required this.weightKg,
    this.axleCount = 5,
    this.model = '',
    this.color = '',
    this.plate = '',
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
    String? model,
    String? color,
    String? plate,
  }) =>
      TruckProfile(
        id:        id        ?? this.id,
        name:      name      ?? this.name,
        heightCm:  heightCm  ?? this.heightCm,
        widthCm:   widthCm   ?? this.widthCm,
        lengthCm:  lengthCm  ?? this.lengthCm,
        weightKg:  weightKg  ?? this.weightKg,
        axleCount: axleCount ?? this.axleCount,
        model:     model     ?? this.model,
        color:     color     ?? this.color,
        plate:     plate     ?? this.plate,
      );

  Map<String, dynamic> toJson() => {
        'id':        id,
        'name':      name,
        'heightCm':  heightCm,
        'widthCm':   widthCm,
        'lengthCm':  lengthCm,
        'weightKg':  weightKg,
        'axleCount': axleCount,
        'model':     model,
        'color':     color,
        'plate':     plate,
      };

  /// Tolerante de propósito nos campos novos: os perfis já gravados em
  /// `truck_profiles_v2` não os têm, e um cast direto zeraria o caminhão do
  /// motorista no primeiro boot depois do update.
  factory TruckProfile.fromJson(Map<String, dynamic> json) => TruckProfile(
        id:        json['id'] as String,
        name:      json['name'] as String,
        heightCm:  (json['heightCm'] as num).toInt(),
        widthCm:   (json['widthCm'] as num).toInt(),
        lengthCm:  (json['lengthCm'] as num).toInt(),
        weightKg:  (json['weightKg'] as num).toInt(),
        axleCount: (json['axleCount'] as num).toInt(),
        model:     (json['model'] as String?) ?? '',
        color:     (json['color'] as String?) ?? '',
        plate:     (json['plate'] as String?) ?? '',
      );

  /// "Scania R450 branco" — o que a ficha do S.O.S. mostra. Vazio se o
  /// motorista não preencheu (a ficha já lida com vazio).
  String get identidadeTexto =>
      [model, color.toLowerCase()].where((s) => s.isNotEmpty).join(' ');

  /// "abc-1d23" → "ABC1D23". Não valida; ver [isValidPlate].
  static String normalizePlate(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Mercosul (AAA1A11) ou antiga (AAA1111). Vazio é válido: campo opcional.
  static bool isValidPlate(String normalized) =>
      normalized.isEmpty ||
      RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$').hasMatch(normalized);

  String get summaryText =>
      '${(heightCm / 100).toStringAsFixed(1)}m alt  '
      '${(lengthCm / 100).toStringAsFixed(1)}m comp  '
      '${(weightKg / 1000).toStringAsFixed(0)}t  '
      '$axleCount eixos';
}
