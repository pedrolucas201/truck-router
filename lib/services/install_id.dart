import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identidade do APARELHO: 32 hex gerados uma vez e guardados em prefs.
///
/// Existe porque o uid do Firebase **não** identifica o motorista. A sessão do
/// Auth se perde em alguns aparelhos e nasce um uid novo a cada abertura (ver
/// `project_auth_uid_churn`), e voto/confirmação são contados por identidade
/// com piso de 3: o mesmo motorista com uid novo vira três votantes e sozinho
/// atravessa o piso — exatamente a má-fé que o piso foi escrito pra barrar.
/// Prefs sobrevivem ao churn; foi medido em 17/09.
///
/// **Não substitui o uid como chave de escrita.** O uid vem do token verificado
/// no servidor e continua sendo quem autentica; este id só COLAPSA votos do
/// mesmo aparelho na hora de contar. Como ele só reduz a contagem, um valor
/// forjado não infla nada: o pior que um cliente mal-intencionado consegue é
/// mandar um id diferente por voto, que é o comportamento de hoje.
///
/// Também não é "a pessoa": dois celulares votam duas vezes, e o Auto Backup
/// pode clonar o id pro aparelho novo (aí SUBconta, que é o lado seguro — sem
/// maioria ninguém manda e o radar fica como está). É um proxy estritamente
/// melhor que o uid, não um proxy correto.
class InstallId {
  InstallId._();

  static const _key = 'install_id';

  /// Só pro caso de as prefs falharem: mantém o id estável DENTRO da sessão em
  /// vez de gerar um novo a cada voto.
  static String? _emergencia;

  /// Nunca lança e nunca devolve vazio.
  ///
  /// Sem cache de propósito: `SharedPreferences.getInstance()` já é singleton e
  /// `getString` é lookup em memória, então o cache não comprava nada e
  /// escondia um caso — prefs limpas depois da primeira leitura devolviam o id
  /// antigo sem regravá-lo.
  static Future<String> get() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final atual = prefs.getString(_key);
      if (atual != null && valido(atual)) return atual;
      final novo = gerar();
      await prefs.setString(_key, novo);
      return novo;
    } catch (_) {
      return _emergencia ??= gerar();
    }
  }

  /// 32 hex do `Random.secure`. Sem pacote `uuid` no projeto — é o mesmo
  /// gerador que o token de sessão do Autocomplete já usa.
  @visibleForTesting
  static String gerar() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// O servidor recusa o que não casar com isto e cai no uid. Validar dos dois
  /// lados evita gravar lixo de uma versão futura que mude o formato.
  @visibleForTesting
  static bool valido(String v) => RegExp(r'^[0-9a-f]{32}$').hasMatch(v);
}
