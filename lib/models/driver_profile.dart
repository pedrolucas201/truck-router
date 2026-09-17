/// Perfil do MOTORISTA — a pessoa, não o caminhão.
///
/// Nasce na Fase 0 do S.O.S. (docs/sos-rede-motoristas.md, 2.2): é o que o
/// outro motorista vê quando alguém pede ajuda. O telefone é dado pessoal,
/// entra com consentimento na tela e NUNCA vai pro doc do S.O.S. (fica em
/// `sos/{id}/contatos/{uid}`, escrito pelo backend no aceite).
///
/// Modelo, cor e placa saíram daqui em 2.4.74: identidade de caminhão mora em
/// [TruckProfile], um por caminhão, porque quem roda mais de um anunciava o
/// veículo errado na ficha do S.O.S. A migração do campo antigo está em
/// `DriverProfileService.legadoIdentidade`.
class DriverProfile {
  final String name;
  final String phone; // só dígitos, com DDD: "11999998888"

  const DriverProfile({
    required this.name,
    this.phone = '',
  });

  Map<String, dynamic> toJson() => {
        'name':  name,
        'phone': phone,
      };

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
        name:  (j['name']  as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
      );

  /// "(11) 99999-8888" → "11999998888".
  static String normalizePhone(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9]'), '');

  /// DDD + 8 ou 9 dígitos. Vazio é válido: campo opcional.
  static bool isValidPhone(String digits) =>
      digits.isEmpty || RegExp(r'^[1-9][0-9]{9,10}$').hasMatch(digits);
}
