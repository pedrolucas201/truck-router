import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/sos_request.dart';
import '../widgets/sos/sos_sheets.dart';
import 'auth_service.dart';
import 'field_log.dart';
import 'som.dart';

/// Push do S.O.S. (fatia 2). Duas metades:
///
/// 1. **Presença**: `presence/{uid}` = token FCM + posição com 2 casas
///    (~1 km) + hora. O backend lê quem está a menos de 20 km e manda uma
///    notificação pronta, que o Play Services exibe sem o app vivo (MIUI mata
///    o processo; mensagem de dados não serve). Só quem vinculou o Google
///    grava presença: anônimo não consegue ler o `sos`, então a notificação
///    abriria uma ficha vazia.
/// 2. **Toque**: a notificação traz `sosId`; abrir = ficha do pedido. Em
///    primeiro plano o sistema NÃO mostra notificação (doc do plugin), então
///    `onMessage` abre a ficha direto — menos na navegação, que já anuncia
///    pelo stream (voz + banner).
class SosPush {
  SosPush._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  /// "Ir até lá" da ficha: quem está na tela decide o que é ir. Mapa = traçar
  /// rota até o pedido; navegação = parada antes do destino. A ficha é a mesma
  /// venha de onde vier (menu, marcador, notificação), por isso o gancho é
  /// global e não parâmetro. ponytail: um slot; a tela de cima registra e
  /// devolve o anterior ao sair.
  static void Function(SosRequest s)? irAteLa;
  static String? _pendente; // sosId tocado antes da UI existir
  static bool _uiPronta = false;

  static Future<void> init() async {
    try {
      final fm = FirebaseMessaging.instance;
      final inicial = await fm.getInitialMessage();
      if (inicial != null) _abrir(inicial, 'terminated');
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _abrir(m, 'background'));
      FirebaseMessaging.onMessage.listen(_emPrimeiroPlano);
      fm.onTokenRefresh.listen((_) => gravarPresenca());
      await gravarPresenca();
    } catch (e, st) {
      FieldLog.error('sos_push_init', e, st);
    }
  }

  static Future<void> _emPrimeiroPlano(RemoteMessage m) async {
    // Navegando: o stream já falou e mostrou o banner; ficha em cima do mapa
    // dirigindo não. Fora da nav, abre a ficha.
    if (await FlutterForegroundTask.isRunningService) return;
    // Com o app aberto o sistema não mostra a notificação (nem toca o som do
    // canal): a buzina vem daqui, junto com a ficha.
    unawaited(Som.buzina());
    _abrir(m, 'foreground');
  }

  static void _abrir(RemoteMessage m, String origem) {
    final id = m.data['sosId'] as String?;
    if (id == null || id.isEmpty) return;
    FieldLog.event('sos_push_open', {'id': id, 'from': origem});
    _pendente = id;
    _tentar();
  }

  /// MapScreen avisa quando montou (depois do splash): aí a ficha pode subir.
  static void uiPronta() {
    _uiPronta = true;
    _tentar();
  }

  static void _tentar() {
    final id = _pendente;
    final ctx = navigatorKey.currentContext;
    if (id == null || !_uiPronta || ctx == null) return;
    _pendente = null;
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => SosFichaSheet(sosId: id),
    );
  }

  /// Grava/atualiza a presença. [pos] = posição atual (nav); sem ela usa o
  /// último fix conhecido (instantâneo, não liga o GPS). Falha é silenciosa:
  /// presença é melhor-esforço, nunca trava nada.
  static Future<void> gravarPresenca({LatLng? pos}) async {
    if (!AuthService.isGoogleLinked) return;
    try {
      var p = pos;
      if (p == null) {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return;
        p = LatLng(last.latitude, last.longitude);
      }
      final fm = FirebaseMessaging.instance;
      // Android 13+: diálogo uma vez; antes disso, no-op.
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token == null) return;
      final uid = await AuthService.getUid();
      await FirebaseFirestore.instance.collection('presence').doc(uid).set({
        'token': token,
        'lat': _duasCasas(p.latitude),
        'lng': _duasCasas(p.longitude),
        'at': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      FieldLog.error('presence_write', e, st);
    }
  }

  static double _duasCasas(double v) => (v * 100).round() / 100;
}
