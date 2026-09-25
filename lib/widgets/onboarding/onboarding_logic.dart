import 'package:geolocator/geolocator.dart';

/// Lógica pura do onboarding (testável sem widget).

/// Cena desenhada de cada tela de apresentação (ver `cena_onboarding.dart`).
enum Cena { abertura, rota, radar, pedagio, sos, fechamento }

/// Uma tela de apresentação: cena + copy.
class TelaOnboarding {
  final String kicker;
  final String titulo;
  final String texto;
  final Cena cena;
  const TelaOnboarding(this.kicker, this.titulo, this.texto, this.cena);
}

/// Copy aprovada com o Pedro em 24/09/2026 (spec 2026-09-24-onboarding-design);
/// telas 1-3 revisadas pelo Beto em 25/09 (kicker "GPS" pra não repetir
/// "trecho", frases mais curtas e "sem multas" no radar).
const kTelasOnboarding = [
  TelaOnboarding('GPS', 'Feito pra quem vive no trecho.',
      'Rota, radar e pedágios pensados para o seu pesado.', Cena.abertura),
  TelaOnboarding('Rota', 'A rota que cabe no seu caminhão.',
      'Altura, peso e eixos definem o seu caminho.', Cena.rota),
  TelaOnboarding('Radar', 'Radar no seu sentido, no limite de pesado.',
      'Sem multas, mais dinheiro no seu bolso.', Cena.radar),
  TelaOnboarding('Pedágio', 'Pedágio já com o valor do seu eixo.',
      'Antes de sair, você sabe quanto vai gastar.', Cena.pedagio),
  TelaOnboarding('S.O.S.', 'Pediu ajuda? Quem está perto recebe.',
      'Buzina, voz e a distância até você.', Cena.sos),
  // Fechamento (copy do Pedro, 25/09): o socorrido vai embora, o nosso
  // arranca ao amanhecer com o alien acenando.
  TelaOnboarding('Bora', 'Bora pro trecho?',
      'Cadastra o caminhão e o resto é com a gente.', Cena.fechamento),
];

const kPaginaCaminhao = 6;   // índice da tela "Seu caminhão"
const kPaginaPermissoes = 7; // índice da tela de permissões
const kTotalPaginas = 8;

/// "Pular" só existe na apresentação e leva direto pro cadastro do caminhão.
/// Null = página sem "Pular".
int? pularDestino(int pagina) => pagina < kPaginaCaminhao ? kPaginaCaminhao : null;

enum PermissaoEstado { concedida, pendente, negadaDeVez }

/// Estado do cartão de localização a partir do que o sistema respondeu.
/// `whileInUse` conta como concedida: o passo "sempre" é bônus (abre Ajustes).
PermissaoEstado estadoLocalizacao(LocationPermission p) => switch (p) {
      LocationPermission.always || LocationPermission.whileInUse => PermissaoEstado.concedida,
      LocationPermission.deniedForever => PermissaoEstado.negadaDeVez,
      _ => PermissaoEstado.pendente,
    };

/// O caminhão mudou em relação ao ativo? Decide se a página 6 grava algo:
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
