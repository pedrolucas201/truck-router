// Síntese de instrução de manobra em pt-BR a partir de `action` + `direction`.
//
// Existe porque o truck routing da HERE às vezes devolve `instruction` VAZIO —
// aí o app falava/mostrava só a distância ("Em 200 metros.") sem a manobra.
// Como `action` e `direction` vêm preenchidos, dá pra reconstruir a frase
// localmente, sem depender da HERE e sem rede.

/// Frase só da manobra (sem distância). Ex: ('turn','right') -> 'vire à direita'.
/// Retorna '' para ações sem voz (continue/keep reto) ou desconhecidas, pra não
/// anunciar algo errado.
String maneuverPhrase(String action, String? direction) {
  final side = switch (direction) {
    'left'        => 'à esquerda',
    'right'       => 'à direita',
    'sharpLeft'   => 'acentuadamente à esquerda',
    'sharpRight'  => 'acentuadamente à direita',
    'slightLeft'  => 'levemente à esquerda',
    'slightRight' => 'levemente à direita',
    _             => null,
  };
  return switch (action) {
    'turn'           => side != null ? 'vire $side' : 'vire',
    'roundaboutExit' => 'na rotatória, pegue a saída${side != null ? ' $side' : ''}',
    'keepLeft'       => 'mantenha-se à esquerda',
    'keepRight'      => 'mantenha-se à direita',
    'exit'           => 'pegue a saída${side != null ? ' $side' : ''}',
    'ramp'           => 'pegue a rampa${side != null ? ' $side' : ''}',
    'uTurn'          => 'faça o retorno',
    'continue'       => 'siga em frente',
    _                => '',
  };
}

/// Texto final da manobra: usa a `instruction` da HERE quando vier preenchida;
/// senão sintetiza de action+direction. Usado por TTS e pela barra visual.
///
/// A síntese é capitalizada na 1ª letra pra ficar IDÊNTICA às instruções da HERE
/// (que vêm capitalizadas) — sem ela, "vire à direita" minúsculo destoava na UI.
String resolveManeuverText(String instruction, String action, String? direction) {
  final t = instruction.trim();
  if (t.isNotEmpty) return t;
  final phrase = maneuverPhrase(action, direction);
  if (phrase.isEmpty) return phrase;
  return '${phrase[0].toUpperCase()}${phrase.substring(1)}';
}
