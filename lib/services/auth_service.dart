import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'field_log.dart';

/// Resultado de [AuthService.linkWithGoogle].
enum GoogleLinkResult {
  /// Conta Google vinculada ao uid atual: o uid não muda, curadorias ficam.
  linked,

  /// A conta Google já tinha um uid (reinstalação/troca de aparelho): o app
  /// passou a ser AQUELE uid. Perfil e overrides antigos voltam; o anônimo
  /// desta instalação fica órfão.
  recovered,

  /// Já estava vinculado. Nada a fazer.
  alreadyLinked,

  /// O motorista fechou o seletor de conta.
  canceled,

  /// Sem Play Services, sem rede, config errada (SHA-1/OAuth client) etc.
  /// Detalhe vai pro FieldLog; pro usuário é só "não deu agora".
  failed,
}

class AuthService {
  /// UM sign-in por processo. Sem isto, `ensureSignedIn()` (boot, unawaited) e
  /// os `getUid()`/`getHeaders()` lazy podiam ver `currentUser == null` ao mesmo
  /// tempo e disparar dois `signInAnonymously()` — dois usuários anônimos na
  /// mesma abertura. Suspeita (não provada) do drive 2026-09-02: uid trocando a
  /// cada cold start e 16 curadorias recusadas por uid do doc ≠ uid do token.
  static Future<void>? _signIn;

  /// Sign-in anônimo idempotente. Loga a falha (sem rede/sem auth) porque quando
  /// isto quebra, TUDO que é autenticado quebra junto (routing, restrictions e o
  /// próprio field_logs) e sem sinal ficaríamos totalmente às cegas.
  ///
  /// [from] = quem pediu ('boot' | 'lazy'). Vai no evento `auth_signin`, que só
  /// existe quando um usuário NOVO foi criado. `prev` é o último uid que ESTA
  /// instalação já teve (guardado por nós, fora do Firebase): vazio = instalação
  /// limpa, normal; preenchido = o Firebase Auth perdeu um usuário que existia
  /// — foi o que a 2.4.53 fez em 7 de 8 boots (medido no Auth em 08/09), e o
  /// plugin restaura o usuário nativo de forma síncrona no initializeApp, então
  /// não é corrida do Dart: sem este campo não há como separar reinstalação de
  /// perda no SDK.
  static Future<void> _ensureUser({String from = 'lazy'}) {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return Future.value();
    return _signIn ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final prev  = prefs.getString(_kLastUid) ?? '';
        // Instalação que já vinculou Google e acordou sem usuário: volta pro
        // uid da conta Google em vez de nascer anônimo de novo. É o que segura
        // perfil/S.O.S. no aparelho do Beto, que perde a sessão do Firebase a
        // cada abertura desde 17/09 (causa em investigação, ver `store`).
        UserCredential? cred;
        String? gmot; // por que a recuperação voltou vazia (null = nem tentou/deu certo)
        if (tentaGoogleNoLogin(from, prefs.getBool(_kGoogle) ?? false)) {
          (cred, gmot) = await _recuperarGoogle();
        }
        final via = cred == null ? 'anon' : 'google';
        cred ??= await auth.signInAnonymously();
        final uid   = cred.user?.uid ?? '';
        if (uid.isNotEmpty) await prefs.setString(_kLastUid, uid);
        FieldLog.event('auth_signin', {
          'from': from,
          'uid':  _short(uid),
          'prev': _short(prev),
          'via':  via,
          'store': bootStore,
          'gmot': ?gmot,
        });
      } catch (e, st) {
        _signIn = null; // deixa a próxima chamada tentar de novo
        FieldLog.error('auth_signin', e, st);
        rethrow;
      }
    }();
  }

  /// Garante um usuário (anônimo) autenticado. Best-effort e silencioso: chamado
  /// no startup pra que QUALQUER caminho de navegação — inclusive o Histórico,
  /// que não passa por geocoding/routing (os gatilhos do login lazy) — já tenha
  /// auth. Sem isso, writes autenticados (field_logs, restrictions) tomam
  /// permission-denied silencioso.
  static Future<void> ensureSignedIn() async {
    // Boot best-effort: o login lazy (getUid/getHeaders) tenta de novo. O log
    // já saiu de dentro do _ensureUser.
    try {
      await _ensureUser(from: 'boot');
      // Usuário restaurado pelo SDK também conta como "último visto": é ele que
      // o `prev` do próximo auth_signin acusa como perdido.
      final uid = currentUid;
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLastUid, uid);
        // Quem vinculou antes desta versão ganha a marca no 1º boot que ainda
        // tem a sessão; sem ela a recuperação acima nunca tenta.
        if (isGoogleLinked) await prefs.setBool(_kGoogle, true);
      }
    } catch (_) {}
  }

  /// Pura, pra teste. Sem a marca NUNCA: no Android o lightweight abre um
  /// seletor de contas quando não acha conta autorizada, e isso no boot de
  /// quem nunca entrou com Google seria um diálogo do nada. 'link' tem fluxo
  /// próprio (o motorista tocou no botão).
  @visibleForTesting
  static bool tentaGoogleNoLogin(String from, bool marca) => marca && from != 'link';

  /// Login Google SEM toque, só pra quem já vinculou (marca [_kGoogle]). Sem a
  /// marca ninguém chega aqui: no Android o lightweight cai num seletor de
  /// contas quando não há conta autorizada, e isso não pode aparecer no boot
  /// de quem nunca entrou com Google. Qualquer falha (offline, sem Play
  /// Services, timeout) devolve null e o boot segue anônimo como sempre:
  /// navegação nunca espera login.
  /// Devolve (credencial, motivo). O motivo vai no `auth_signin` como `gmot`:
  /// 18/09 13:35 a recuperação voltou vazia SEM erro nenhum (3 de 4 deram certo)
  /// e não havia como saber se foi conta não achada, cancelada ou timeout — o
  /// FieldLog.error de antes do login ainda nem tem auth pra gravar.
  static Future<(UserCredential?, String?)> _recuperarGoogle() async {
    try {
      await (_googleInit ??= GoogleSignIn.instance.initialize());
      final tentativa = GoogleSignIn.instance.attemptLightweightAuthentication();
      if (tentativa == null) return (null, 'sem_suporte');
      final acc = await tentativa.timeout(const Duration(seconds: 8));
      if (acc == null) return (null, 'sem_conta'); // não achou ou o seletor foi fechado
      final idToken = acc.authentication.idToken;
      if (idToken == null) return (null, 'sem_token');
      final cred = await FirebaseAuth.instance
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken))
          .timeout(const Duration(seconds: 8));
      return (cred, null);
    } on TimeoutException {
      return (null, 'timeout');
    } catch (e, st) {
      FieldLog.error('auth_google_restore', e, st);
      return (null, 'erro:${e.runtimeType}');
    }
  }

  /// Arquivos de sessão do Firebase Auth em shared_prefs, lidos ANTES do
  /// initializeApp (o SDK pode apagar o que rejeita). Vai no `auth_signin`:
  /// `sem_store` = alguém apagou o arquivo; `…:user=1` com usuário perdido =
  /// o SDK tinha o usuário em disco e não o aceitou. Instrumento do churn do
  /// Beto (18/09); sai quando a causa estiver fechada.
  static String bootStore = 'nd';

  static Future<void> snapshotStore() async {
    try {
      final base = (await getApplicationSupportDirectory()).parent.path;
      final fs = Directory('$base/shared_prefs')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('firebase.auth'))
          .map((f) {
        final user = f.readAsStringSync().contains('FIREBASE_USER') ? 1 : 0;
        return '${f.lengthSync()}b:user=$user';
      }).toList();
      bootStore = fs.isEmpty ? 'sem_store' : fs.join(',');
    } catch (e) {
      bootStore = 'erro:${e.runtimeType}';
    }
  }

  static const _kLastUid = 'auth_last_uid';
  static const _kGoogle = 'auth_google_linked';
  static String _short(String uid) =>
      uid.isEmpty ? 'none' : uid.substring(0, uid.length < 6 ? uid.length : 6);

  static Future<String> getUid() async {
    await _ensureUser();
    return FirebaseAuth.instance.currentUser!.uid;
  }

  /// Uid que já está em memória, ou null se o sign-in não completou. Síncrono e
  /// sem lançar de propósito: serve pra telemetria, que não pode esperar login
  /// nem derrubar o caminho de quem a chama.
  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// E-mail da conta Google vinculada, ou null se ainda é só anônimo.
  static String? get googleEmail {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    for (final p in u.providerData) {
      if (p.providerId == 'google.com') return p.email;
    }
    return null;
  }

  static bool get isGoogleLinked => googleEmail != null;

  static Future<void>? _googleInit;

  /// Vincula a conta Google ao usuário anônimo atual (Fase 0 do S.O.S.,
  /// docs/sos-rede-motoristas.md 2.1). Vincular em vez de trocar preserva o
  /// uid e tudo que está carimbado nele. Se a conta Google JÁ tem um uid
  /// (`credential-already-in-use`), entra nele: é o caminho de recuperação
  /// depois de reinstalar, e o motivo desta feature existir.
  ///
  /// Nunca lança. Só é chamado por toque do motorista; o fluxo anônimo do boot
  /// não passa por aqui e não depende disto.
  static Future<GoogleLinkResult> linkWithGoogle() async {
    final auth = FirebaseAuth.instance;
    try {
      await _ensureUser(from: 'link');
      if (isGoogleLinked) return GoogleLinkResult.alreadyLinked;

      // serverClientId vem do google-services.json (web OAuth client gerado ao
      // habilitar o provedor Google no console). Sem ele o authenticate() falha
      // com "serverClientId must be provided" — cai no `failed` abaixo.
      await (_googleInit ??= GoogleSignIn.instance.initialize());
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw StateError('google idToken null');
      final cred = GoogleAuthProvider.credential(idToken: idToken);

      final prev = auth.currentUser!.uid;
      GoogleLinkResult result;
      try {
        await auth.currentUser!.linkWithCredential(cred);
        result = GoogleLinkResult.linked;
      } on FirebaseAuthException catch (e) {
        switch (e.code) {
          case 'credential-already-in-use':
          case 'email-already-in-use':
            await auth.signInWithCredential(cred);
            result = GoogleLinkResult.recovered;
          case 'provider-already-linked':
            result = GoogleLinkResult.alreadyLinked;
          default:
            rethrow;
        }
      }
      final uid = auth.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLastUid, uid);
        await prefs.setBool(_kGoogle, true);
      }
      FieldLog.event('auth_link', {
        'outcome': result.name,
        'uid':  _short(uid),
        'prev': _short(prev),
      });
      return result;
    } on GoogleSignInException catch (e, st) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return GoogleLinkResult.canceled;
      }
      FieldLog.error('auth_link', e, st);
      return GoogleLinkResult.failed;
    } catch (e, st) {
      FieldLog.error('auth_link', e, st);
      return GoogleLinkResult.failed;
    }
  }

  static Future<Map<String, String>> getHeaders() async {
    await _ensureUser();
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    return {'Authorization': 'Bearer $token'};
  }
}
