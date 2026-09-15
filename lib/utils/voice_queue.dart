/// Fila mínima de fala pra navegação.
///
/// O TTS toca uma frase por vez. Quando duas colidem, a regra da nav sempre foi
/// descartar a segunda em silêncio (contada em `ttsDropped`): certo pra manobra,
/// que envelhece em 3 s e se repete no próximo degrau de distância; errado pra
/// aviso raro que não volta ("Você chegou no motorista que pediu ajuda",
/// "Pedido de ajuda encerrado"). Esses entram aqui e saem quando o TTS libera.
///
/// ponytail: 2 lugares, sem idade, sem prioridade. Se no campo aparecer fala
/// velha saindo tarde, entra TTL por item; se aparecer fila cheia, entra
/// prioridade. Invariante: uma frase enfileirada nunca é descartada por colisão.
class VoiceQueue {
  static const capacidade = 2;
  final List<String> _itens = [];

  int get length => _itens.length;
  bool get isEmpty => _itens.isEmpty;

  /// Enfileira [texto]. Repetida (já na fila) não entra; cheia derruba a mais
  /// antiga (a mais nova é a mais atual). Devolve se entrou.
  bool enfileirar(String texto) {
    if (_itens.contains(texto)) return false;
    if (_itens.length >= capacidade) _itens.removeAt(0);
    _itens.add(texto);
    return true;
  }

  /// Próxima a falar, na ordem em que entrou; null se vazia.
  String? proxima() => _itens.isEmpty ? null : _itens.removeAt(0);

  void limpar() => _itens.clear();
}
