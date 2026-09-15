import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Pedido de ajuda na estrada (doc `sos/{id}`). Perfil vem copiado no doc
/// (leitor não lê `profiles`, que é privado). Telefone NUNCA está aqui: fica
/// em `sos/{id}/contatos/{uid}`, escrito pelo backend no aceite.
enum SosTipo {
  ferramenta('Ferramenta', 'ferramenta'),
  pneu('Pneu', 'pneu'),
  combustivel('Combustível', 'combustível'),
  mecanica('Mecânica', 'problema mecânico'),
  reboque('Reboque', 'reboque'),
  saude('Saúde', 'problema de saúde'),
  outro('Outro', 'ajuda');

  final String label;
  final String fala; // como a voz diz
  const SosTipo(this.label, this.fala);

  static SosTipo parse(String? s) =>
      SosTipo.values.firstWhere((t) => t.name == s, orElse: () => SosTipo.outro);
}

class SosRequest {
  final String id;
  final String uid;
  final String nome;
  final String caminhao;
  final String cor;
  final SosTipo tipo;
  final String texto;
  final double lat;
  final double lng;
  final String status; // aberto | atendendo | resolvido | expirado
  final DateTime criadoEm;
  final DateTime expireAt;
  final String? ajudanteUid;
  final String? ajudanteNome;

  const SosRequest({
    required this.id,
    required this.uid,
    required this.nome,
    required this.caminhao,
    required this.cor,
    required this.tipo,
    required this.texto,
    required this.lat,
    required this.lng,
    required this.status,
    required this.criadoEm,
    required this.expireAt,
    this.ajudanteUid,
    this.ajudanteNome,
  });

  LatLng get position => LatLng(lat, lng);
  bool get aberto => status == 'aberto';
  bool get atendendo => status == 'atendendo';
  bool get ativo => (aberto || atendendo) && expireAt.isAfter(DateTime.now());

  /// "Scania R450 branco" / "Scania R450" / "" — sem vírgula solta.
  String get caminhaoTexto =>
      [caminhao, cor.toLowerCase()].where((s) => s.isNotEmpty).join(' ');

  factory SosRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SosRequest(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      nome: d['nome'] as String? ?? '',
      caminhao: d['caminhao'] as String? ?? '',
      cor: d['cor'] as String? ?? '',
      tipo: SosTipo.parse(d['tipo'] as String?),
      texto: d['texto'] as String? ?? '',
      lat: (d['lat'] as num).toDouble(),
      lng: (d['lng'] as num).toDouble(),
      status: d['status'] as String? ?? 'aberto',
      criadoEm: (d['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expireAt: (d['expireAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ajudanteUid: d['ajudanteUid'] as String?,
      ajudanteNome: d['ajudanteNome'] as String?,
    );
  }
}

/// Frase falada UMA vez por S.O.S. quando entra no raio. Curta: o motorista
/// está dirigindo. "Motorista pedindo ajuda a 8 quilômetros. Pneu."
String sosSpeech(SosRequest s, double distKm) {
  final km = distKm < 1 ? 'menos de 1 quilômetro' : '${distKm.round()} quilômetros';
  return 'Motorista pedindo ajuda a $km. ${s.tipo.fala}.';
}

/// "8 km" / "800 m".
String sosDistText(double distM) =>
    distM < 1000 ? '${distM.round()} m' : '${(distM / 1000).round()} km';
