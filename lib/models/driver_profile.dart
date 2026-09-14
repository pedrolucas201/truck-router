/// Perfil do MOTORISTA (não do caminhão: isso é `TruckProfile`). Nasce na
/// Fase 0 do S.O.S. (docs/sos-rede-motoristas.md, 2.2): é o que o outro
/// motorista vê quando alguém pede ajuda. Placa e telefone são dado pessoal e
/// entram com consentimento na tela; o telefone NUNCA vai pro doc do S.O.S.
class DriverProfile {
  final String name;
  final String truck; // texto livre: "Scania R450"
  final String color;
  final String plate; // normalizada: "ABC1D23"
  final String phone; // só dígitos, com DDD: "11999998888"

  const DriverProfile({
    required this.name,
    this.truck = '',
    this.color = '',
    this.plate = '',
    this.phone = '',
  });

  Map<String, dynamic> toJson() => {
        'name':  name,
        'truck': truck,
        'color': color,
        'plate': plate,
        'phone': phone,
      };

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
        name:  (j['name']  as String?) ?? '',
        truck: (j['truck'] as String?) ?? '',
        color: (j['color'] as String?) ?? '',
        plate: (j['plate'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
      );

  /// "abc-1d23" → "ABC1D23". Não valida; ver [isValidPlate].
  static String normalizePlate(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Mercosul (AAA1A11) ou antiga (AAA1111). Vazio é válido: campo opcional.
  static bool isValidPlate(String normalized) =>
      normalized.isEmpty ||
      RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$').hasMatch(normalized);

  /// "(11) 99999-8888" → "11999998888".
  static String normalizePhone(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9]'), '');

  /// DDD + 8 ou 9 dígitos. Vazio é válido: campo opcional.
  static bool isValidPhone(String digits) =>
      digits.isEmpty || RegExp(r'^[1-9][0-9]{9,10}$').hasMatch(digits);
}
