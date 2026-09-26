import 'package:geolocator/geolocator.dart';

import '../../models/truck_profile.dart';

/// Lógica pura do onboarding "Monta o seu caminhão" (testável sem widget).
/// Spec: docs/superpowers/specs/2026-09-25-onboarding-monta-caminhao-design.md.

/// Cena ao vivo atrás das páginas (ver `cena_onboarding.dart`).
enum Cena { abertura, garagem, sos, fechamento }

// ── Páginas ──────────────────────────────────────────────────────────────────
const kPagChegada = 0;
const kPagGaragem = 1;
const kPagLocal = 2;
const kPagTrecho = 3;
const kPagAjuda = 4;
const kPagBora = 5;
const kTotalPaginas = 6;

/// Cena de fundo de cada página. Nas páginas 2 e 3 a cena some e entra o
/// radar de varredura.
Cena cenaDaPagina(int p) => switch (p) {
      kPagChegada => Cena.abertura,
      kPagGaragem || kPagLocal || kPagTrecho => Cena.garagem,
      kPagAjuda => Cena.sos,
      _ => Cena.fechamento,
    };

bool mostraVarredura(int p) => p == kPagLocal || p == kPagTrecho;

/// "Pular" existe da garagem até a ajuda. Pular a localização pula também o
/// "seu trecho" (não há onde mostrar). Null = página sem "Pular".
int? pularDestino(int p) => switch (p) {
      kPagGaragem => kPagLocal,
      kPagLocal || kPagTrecho => kPagAjuda,
      kPagAjuda => kPagBora,
      _ => null,
    };

// ── Tipos de caminhão ────────────────────────────────────────────────────────

/// Tipos da garagem. Pesos derivados dos limites por eixo da Lei da Balança
/// (direcional 6 t, simples de rodado duplo 10 t, tandem duplo 17 t, tandem
/// triplo 25,5 t) e dos PBTC de combinação (bitrem 57 t, rodotrem 74 t com AET).
/// Comprimentos no teto legal de cada configuração (rodotrem: sem AET de 30 m).
enum TipoCaminhao {
  toco('Toco', eixos: 2, pesoKg: 16000, comprimentoCm: 1000),
  truck('Truck', eixos: 3, pesoKg: 23000, comprimentoCm: 1400),
  carreta('Carreta', eixos: 5, pesoKg: 41500, comprimentoCm: 1860),
  bitrem('Bitrem', eixos: 7, pesoKg: 57000, comprimentoCm: 1980),
  rodotrem('Rodotrem', eixos: 9, pesoKg: 74000, comprimentoCm: 2500);

  final String nome;
  final int eixos;
  final int pesoKg;
  final int comprimentoCm;
  const TipoCaminhao(this.nome, {required this.eixos, required this.pesoKg, required this.comprimentoCm});

  int get alturaCm => kAlturaPadraoCm;
}

/// Medidas que a garagem grava. `null` em [tipo] = "O meu" (o caminhão que o
/// aparelho já tem, restaurado ou editado): confirmar não grava nada.
class Medidas {
  final int alturaCm, comprimentoCm, pesoKg, eixos;
  const Medidas({required this.alturaCm, required this.comprimentoCm, required this.pesoKg, required this.eixos});
  factory Medidas.doTipo(TipoCaminhao t) =>
      Medidas(alturaCm: t.alturaCm, comprimentoCm: t.comprimentoCm, pesoKg: t.pesoKg, eixos: t.eixos);
}

/// O caminhão mudou em relação ao ativo? Decide se a garagem grava algo:
/// passar direto não escreve (nem no espelho da conta).
bool caminhaoMudou({
  required int alturaCm,
  required int comprimentoCm,
  required int pesoKg,
  required int eixos,
  required int alturaAtualCm,
  required int comprimentoAtualCm,
  required int pesoAtualKg,
  required int eixosAtual,
}) =>
    alturaCm != alturaAtualCm ||
    comprimentoCm != comprimentoAtualCm ||
    pesoKg != pesoAtualKg ||
    eixos != eixosAtual;

/// Tarifa básica ILUSTRATIVA de uma praça (R$ por eixo). Nas concessões,
/// caminhão paga a tarifa básica × número de eixos; o valor real de cada praça
/// vem da HERE na rota. ponytail: número de exemplo, não é de praça nenhuma.
const kTarifaExemploPorEixo = 9.50;

/// "5 eixos · R$ 47,50" pro selo da garagem.
String pedagioExemplo(int eixos) =>
    '$eixos eixos · R\$ ${(eixos * kTarifaExemploPorEixo).toStringAsFixed(2).replaceAll('.', ',')}';

/// Nome do caminhão depois da garagem: o de fábrica ("Padrão") vira o nome do
/// tipo escolhido; qualquer outro nome é do motorista e fica.
String nomeDoCaminhao({required String atual, TipoCaminhao? tipo}) =>
    tipo != null && atual == 'Padrão' ? tipo.nome : atual;

/// A garagem abre com "O meu" marcado quando o aparelho já tem um caminhão de
/// verdade (editado aqui ou restaurado do espelho). Instalação limpa abre sem
/// seleção: o motorista escolhe o tipo.
bool abreComOMeu({required bool editado}) => editado;

// ── Permissões ───────────────────────────────────────────────────────────────

enum PermissaoEstado { concedida, pendente, negadaDeVez }

/// Estado do cartão de localização a partir do que o sistema respondeu.
/// `whileInUse` conta como concedida: o passo "sempre" é bônus (abre Ajustes).
PermissaoEstado estadoLocalizacao(LocationPermission p) => switch (p) {
      LocationPermission.always || LocationPermission.whileInUse => PermissaoEstado.concedida,
      LocationPermission.deniedForever => PermissaoEstado.negadaDeVez,
      _ => PermissaoEstado.pendente,
    };

// ── Cidades pra quem nega a localização ─────────────────────────────────────

/// Capitais e polos de carga. Quem nega a localização escolhe uma e vê o
/// trecho em volta dela (mesmo cálculo).
const kCidades = <(String, double, double)>[
  ('São Paulo', -23.5505, -46.6333),
  ('Campinas', -22.9056, -47.0608),
  ('Rio de Janeiro', -22.9068, -43.1729),
  ('Belo Horizonte', -19.9167, -43.9345),
  ('Curitiba', -25.4284, -49.2733),
  ('Porto Alegre', -30.0346, -51.2177),
  ('Goiânia', -16.6869, -49.2648),
  ('Brasília', -15.7939, -47.8828),
  ('Cuiabá', -15.6014, -56.0979),
  ('Campo Grande', -20.4697, -54.6201),
  ('Uberlândia', -18.9186, -48.2772),
  ('Ribeirão Preto', -21.1775, -47.8103),
  ('Salvador', -12.9777, -38.5016),
  ('Recife', -8.0476, -34.8770),
  ('Fortaleza', -3.7319, -38.5267),
  ('Belém', -1.4558, -48.4902),
  ('Manaus', -3.1190, -60.0217),
];
