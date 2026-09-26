import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bridge_restriction.dart';
import '../models/radar_point.dart';
import '../providers/truck_profile_provider.dart';
import '../services/field_log.dart';
import '../services/location_asked.dart';
import '../services/physical_restriction_service.dart';
import '../services/radar_service.dart';
import '../services/sistema.dart';
import '../utils/meters.dart';
import '../widgets/onboarding/cena_onboarding.dart';
import '../widgets/onboarding/onboarding_logic.dart';
import '../widgets/onboarding/radar_varredura.dart';
import '../widgets/onboarding/trecho.dart';
import 'map_screen.dart';

/// O que o onboarding pergunta ao sistema. Interface pra o teste de widget não
/// bater em plugin; o app usa [PermissoesReais].
abstract class PermissoesApi {
  Future<LocationPermission> localizacao();
  Future<LocationPermission> pedirLocalizacao();
  /// Posição atual (ou a última conhecida). Null = não deu.
  Future<({double lat, double lng})?> posicao();
  Future<bool> notificacaoOk();
  Future<void> pedirNotificacao();
  Future<void> abrirAjustes();
  Future<bool> ehXiaomi();
  Future<bool> abrirInicioAutomatico();
}

class PermissoesReais implements PermissoesApi {
  const PermissoesReais();
  @override
  Future<LocationPermission> localizacao() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> pedirLocalizacao() => Geolocator.requestPermission();
  @override
  Future<({double lat, double lng})?> posicao() async {
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)));
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      try {
        final p = await Geolocator.getLastKnownPosition();
        return p == null ? null : (lat: p.latitude, lng: p.longitude);
      } catch (_) {
        return null;
      }
    }
  }
  @override
  Future<bool> notificacaoOk() async =>
      await FlutterForegroundTask.checkNotificationPermission() == NotificationPermission.granted;
  @override
  Future<void> pedirNotificacao() => FlutterForegroundTask.requestNotificationPermission();
  @override
  Future<void> abrirAjustes() => Geolocator.openAppSettings();
  @override
  Future<bool> ehXiaomi() => Sistema.ehXiaomi();
  @override
  Future<bool> abrirInicioAutomatico() => Sistema.abrirInicioAutomatico();
}

/// Onboarding "Monta o seu caminhão": chegada, garagem, onde você está, seu
/// trecho (o "aha" com os dados offline em volta dele), ajuda na estrada, bora.
/// Spec: docs/superpowers/specs/2026-09-25-onboarding-monta-caminhao-design.md.
/// Nada trava: toda permissão tem "Pular" e o "Começar" libera sempre.
/// Sem voz: o Pedro prefere o onboarding sempre mudo (25/09).
class OnboardingScreen extends StatefulWidget {
  final PermissoesApi permissoes;
  final VoidCallback? aoConcluir; // testes: evita abrir o MapScreen
  const OnboardingScreen({super.key, this.permissoes = const PermissoesReais(), this.aoConcluir});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final _ctrl = PageController();
  final _sw = Stopwatch()..start();
  int _pagina = 0;

  // Garagem
  TipoCaminhao? _tipo;
  bool _oMeu = false; // "O meu" marcado: confirmar não grava
  bool _temOMeu = false;
  bool _ajustando = false;
  final _form = GlobalKey<FormState>();
  final _altura = TextEditingController();
  final _comprimento = TextEditingController();
  final _peso = TextEditingController();
  final _eixos = TextEditingController();
  bool _garagemPronta = false;

  // Seu trecho
  Future<(List<RadarPoint>, List<BridgeRestriction>)>? _dados;
  ResumoTrecho? _resumo;
  String? _cidade; // escolhida à mão (sem localização)
  bool _procurando = false;
  String? _avisoLocal;

  // Permissões
  LocationPermission _loc = LocationPermission.denied;
  bool _notif = false;
  bool _xiaomi = false;
  // Início automático da MIUI: o Android não deixa LER essa chave, só abrir a
  // tela. Então o estado é a palavra do motorista ("Já liguei"), guardada.
  bool _autostartAberto = false;
  bool _autostartOk = false;
  static const _kAutostartOk = 'autostart_confirmado';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FieldLog.event('onboarding_step', {'i': 0});
    unawaited(_lerPermissoes());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_garagemPronta) return;
    _garagemPronta = true;
    final prov = context.read<TruckProfileProvider>();
    _temOMeu = abreComOMeu(editado: prov.editado);
    _oMeu = _temOMeu;
    _preencheForm(Medidas(
      alturaCm: prov.profile.heightCm, comprimentoCm: prov.profile.lengthCm,
      pesoKg: prov.profile.weightKg, eixos: prov.profile.axleCount,
    ));
  }

  void _preencheForm(Medidas m) {
    _altura.text = cmToMeters(m.alturaCm);
    _comprimento.text = cmToMeters(m.comprimentoCm);
    _peso.text = m.pesoKg.toString();
    _eixos.text = m.eixos.toString();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou dos Ajustes: o estado da localização e da notificação muda lá.
    if (state == AppLifecycleState.resumed) unawaited(_lerPermissoes());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    for (final c in [_altura, _comprimento, _peso, _eixos]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _lerPermissoes() async {
    final api = widget.permissoes;
    try {
      final r = await Future.wait<Object>([api.localizacao(), api.notificacaoOk(), api.ehXiaomi()]);
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _loc = r[0] as LocationPermission;
        _notif = r[1] as bool;
        _xiaomi = r[2] as bool;
        _autostartOk = prefs.getBool(_kAutostartOk) ?? false;
      });
    } catch (_) {/* permissão ilegível = segue como pendente */}
  }

  // ── Navegação ──────────────────────────────────────────────────────────────

  void _irPara(int i) {
    if (i == kPagGaragem) _carregaDados();
    _ctrl.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _aoMudarPagina(int i) {
    setState(() => _pagina = i);
    FieldLog.event('onboarding_step', {'i': i});
  }

  void _pular() {
    final destino = pularDestino(_pagina);
    if (destino == null) return;
    FieldLog.event('onboarding_skip', {'from': _pagina});
    _irPara(destino);
  }

  Future<void> _concluir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    FieldLog.event('onboarding_done', {'ms': _sw.elapsedMilliseconds});
    if (!mounted) return;
    if (widget.aoConcluir != null) return widget.aoConcluir!();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MapScreen()));
  }

  // ── Garagem ────────────────────────────────────────────────────────────────

  void _escolhe(TipoCaminhao? t) {
    HapticFeedback.selectionClick();
    setState(() {
      _tipo = t;
      _oMeu = t == null;
      if (t != null) _preencheForm(Medidas.doTipo(t));
      if (t == null) {
        final p = context.read<TruckProfileProvider>().profile;
        _preencheForm(Medidas(alturaCm: p.heightCm, comprimentoCm: p.lengthCm, pesoKg: p.weightKg, eixos: p.axleCount));
      }
    });
  }

  String? get _rotulo {
    if (_oMeu) {
      final p = context.read<TruckProfileProvider>().profile;
      return 'O meu · ${p.axleCount} eixos';
    }
    final t = _tipo;
    return t == null ? null : '${t.nome} · ${t.eixos} eixos';
  }

  /// Grava só se mudou do caminhão ativo: "O meu" sem ajuste não escreve nada
  /// (nem no espelho da conta).
  Future<void> _confirmaGaragem() async {
    if (_ajustando && !(_form.currentState?.validate() ?? false)) return;
    final provider = context.read<TruckProfileProvider>();
    final atual = provider.profile;
    final alturaCm = metersToCm(_altura.text)!;
    final compCm = metersToCm(_comprimento.text)!;
    final peso = int.parse(_peso.text);
    final eixos = int.parse(_eixos.text);
    final mudou = caminhaoMudou(
      alturaCm: alturaCm, comprimentoCm: compCm, pesoKg: peso, eixos: eixos,
      alturaAtualCm: atual.heightCm, comprimentoAtualCm: atual.lengthCm,
      pesoAtualKg: atual.weightKg, eixosAtual: atual.axleCount,
    );
    FieldLog.event('onboarding_truck', {'tipo': _oMeu ? 'meu' : _tipo?.name ?? '-', 'changed': mudou, 'ajustou': _ajustando});
    if (mudou) {
      await provider.saveProfile(atual.copyWith(
          heightCm: alturaCm, lengthCm: compCm, weightKg: peso, axleCount: eixos));
    }
    _irPara(kPagLocal);
  }

  // ── Seu trecho ─────────────────────────────────────────────────────────────

  /// Os dois assets offline. Carrega ao entrar na garagem: o caminhão está
  /// parado e o motorista escolhendo, então o parse não briga com animação.
  // ponytail: parse do CSV de radar (2,3 MB) na isolate principal, ~100-300 ms
  // estimados; mover pra compute() se o --profile no Redmi mostrar engasgo.
  void _carregaDados() {
    _dados ??= () async {
      final r = await Future.wait<Object>([RadarService.load(), PhysicalRestrictionService.load()]);
      return (r[0] as List<RadarPoint>, r[1] as List<BridgeRestriction>);
    }();
  }

  Future<void> _mostrarMeuTrecho() async {
    setState(() {
      _procurando = true;
      _avisoLocal = null;
    });
    var perm = _loc;
    if (estadoLocalizacao(perm) != PermissaoEstado.concedida) {
      // Carimba ANTES de pedir: é a mesma marca do boot do mapa, então ele não
      // gasta a segunda chance (a segunda negação no Android é permanente).
      await markLocationAsked();
      perm = await widget.permissoes.pedirLocalizacao();
      FieldLog.event('onboarding_perm', {'kind': 'loc', 'result': perm.name});
      if (mounted) setState(() => _loc = perm);
    }
    if (estadoLocalizacao(perm) != PermissaoEstado.concedida) {
      if (!mounted) return;
      setState(() {
        _procurando = false;
        _avisoLocal = 'Sem a localização, escolha uma cidade.';
      });
      return _escolherCidade();
    }
    final pos = await widget.permissoes.posicao();
    if (pos == null) {
      if (!mounted) return;
      setState(() {
        _procurando = false;
        _avisoLocal = 'Não achei a sua posição agora. Escolha uma cidade.';
      });
      return _escolherCidade();
    }
    await _calcula(pos.lat, pos.lng, cidade: null);
  }

  Future<void> _escolherCidade() async {
    final c = await showModalBottomSheet<(String, double, double)>(
      context: context,
      backgroundColor: kFundo,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in kCidades)
              ListTile(
                title: Text(c.$1, style: const TextStyle(color: Colors.white, fontSize: 17)),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (c == null) return;
    await _calcula(c.$2, c.$3, cidade: c.$1);
  }

  Future<void> _calcula(double lat, double lng, {required String? cidade}) async {
    setState(() => _procurando = true);
    _carregaDados();
    try {
      final (radares, restricoes) = await _dados!;
      if (!mounted) return;
      final altura = context.read<TruckProfileProvider>().profile.heightCm;
      final r = calcularTrecho(lat: lat, lng: lng, alturaCm: altura, radares: radares, restricoes: restricoes);
      FieldLog.event('onboarding_aha', {
        'raio_km': r.raioKm.round(), 'radares': faixa(r.radares), 'viadutos': faixa(r.viadutos),
        'caso': r.caso.name, 'cidade_manual': cidade != null,
      });
      setState(() {
        _resumo = r;
        _cidade = cidade;
        _procurando = false;
      });
      _irPara(kPagTrecho);
    } catch (e, st) {
      FieldLog.error('onboarding_aha', e, st);
      if (!mounted) return;
      setState(() => _procurando = false);
      _irPara(kPagAjuda);
    }
  }

  // ── Ajuda e permissões finais ──────────────────────────────────────────────

  Future<void> _ativarAjuda() async {
    if (!_notif) {
      await widget.permissoes.pedirNotificacao();
      final ok = await widget.permissoes.notificacaoOk();
      FieldLog.event('onboarding_perm', {'kind': 'notif', 'result': ok});
      if (mounted) setState(() => _notif = ok);
    }
    _irPara(kPagBora);
  }

  Future<void> _confirmarAutostart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutostartOk, true);
    FieldLog.event('onboarding_perm', {'kind': 'autostart', 'result': 'confirmado'});
    if (mounted) setState(() => _autostartOk = true);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Visual único da marca, independente do tema do sistema.
    final tema = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kNeon, brightness: Brightness.dark, surface: kFundo),
    );
    final varre = mostraVarredura(_pagina);
    return Theme(
      data: tema,
      child: PopScope(
        canPop: _pagina == 0,
        onPopInvokedWithResult: (pop, _) {
          if (!pop && _pagina > 0) _irPara(_pagina == kPagAjuda && _resumo == null ? kPagLocal : _pagina - 1);
        },
        child: Scaffold(
          backgroundColor: kFundo,
          body: SafeArea(
            child: Column(
              children: [
                _topo(),
                Expanded(
                  // A cena é UMA só, atrás das páginas: o mundo não corta ao
                  // trocar de tela. Nas páginas 2 e 3 entra o radar de varredura.
                  child: Stack(children: [
                    Positioned.fill(
                      child: Column(children: [
                        Expanded(
                          flex: 11,
                          child: Stack(fit: StackFit.expand, children: [
                            CenaOnboarding(cena: cenaDaPagina(_pagina), visivel: !varre,
                                rotulo: _pagina == kPagGaragem ? _rotulo : null),
                            RadarVarredura(resumo: _resumo, visivel: varre),
                          ]),
                        ),
                        const Expanded(flex: 9, child: SizedBox()),
                      ]),
                    ),
                    PageView(
                      controller: _ctrl,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: _aoMudarPagina,
                      children: [
                        _pagina0(),
                        _paginaGaragem(),
                        _paginaLocal(),
                        _paginaTrecho(),
                        _paginaAjuda(),
                        _paginaBora(),
                      ],
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topo() {
    final pular = pularDestino(_pagina) != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Row(children: [
              for (var i = 0; i < kTotalPaginas; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _pagina ? kNeon : Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
          ),
          if (pular)
            TextButton(
              key: const Key('onb_pular'),
              onPressed: _pular,
              child: const Text('Pular', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  /// Molde das páginas: a parte de cima fica transparente (cena atrás), o
  /// texto e os botões embaixo.
  Widget _molde({required List<Widget> corpo, required Widget botoes}) => Column(
        children: [
          const Expanded(flex: 11, child: SizedBox()),
          Expanded(
            flex: 9,
            child: Container(
              color: kFundo,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: corpo))),
                  const SizedBox(height: 8),
                  botoes,
                ],
              ),
            ),
          ),
        ],
      );

  /// Botão principal em largura cheia (alvo grande pra dedo na cabine) e o
  /// secundário embaixo, centralizado.
  Widget _botoes(String principal, VoidCallback? acao, {String? secundario, VoidCallback? acaoSec, Key? chave, bool ocupado = false}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: chave ?? const Key('onb_proxima'),
            onPressed: ocupado ? null : acao,
            style: FilledButton.styleFrom(
              backgroundColor: kNeon, foregroundColor: const Color(0xFF06140A),
              disabledBackgroundColor: kNeon.withValues(alpha: .35),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: ocupado
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF06140A)))
                : Text(principal, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (secundario != null)
            TextButton(
              key: const Key('onb_secundario'),
              onPressed: acaoSec,
              child: Text(secundario, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ),
        ],
      );

  Widget _pagina0() => _molde(
        corpo: const [
          _Kicker('No Trecho'),
          _Titulo('Oi! Sou seu parceiro no trecho.'),
          _Texto('Grátis de verdade, sem cadastro. Bora montar o seu caminhão?'),
        ],
        botoes: _botoes('Bora', () => _irPara(kPagGaragem)),
      );

  Widget _paginaGaragem() {
    final escolheu = _oMeu || _tipo != null;
    return _molde(
      corpo: [
        const _Kicker('Seu caminhão'),
        const _Titulo('Com que caminhão você roda?'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_temOMeu) _cartaoTipo('O meu', 'atual', selecionado: _oMeu, onTap: () => _escolhe(null), chave: const Key('onb_tipo_meu')),
            for (final t in TipoCaminhao.values)
              _cartaoTipo(t.nome, '${t.eixos} eixos',
                  selecionado: !_oMeu && _tipo == t, onTap: () => _escolhe(t), chave: Key('onb_tipo_${t.name}')),
          ],
        ),
        const SizedBox(height: 6),
        if (!_ajustando)
          TextButton.icon(
            key: const Key('onb_ajustar'),
            onPressed: escolheu ? () => setState(() => _ajustando = true) : null,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(escolheu
                ? 'Ajustar medidas (${_altura.text} m · ${_eixos.text} eixos)'
                : 'Escolha um tipo pra ver as medidas'),
          )
        else
          Form(
            key: _form,
            child: Column(children: [
              const SizedBox(height: 8),
              _campo(_altura, 'Altura (m)', 'Ex: 4,40', metros: true, max: 700),
              const SizedBox(height: 10),
              _campo(_comprimento, 'Comprimento (m)', 'Ex: 18,60', metros: true, max: 3000),
              const SizedBox(height: 10),
              _campo(_peso, 'Peso bruto (kg)', 'Ex: 41500', max: 100000),
              const SizedBox(height: 10),
              _campo(_eixos, 'Número de eixos', 'Ex: 5', min: 2, max: 9),
            ]),
          ),
      ],
      botoes: _botoes('É esse', escolheu ? _confirmaGaragem : null, chave: const Key('onb_e_esse')),
    );
  }

  Widget _cartaoTipo(String nome, String sub, {required bool selecionado, required VoidCallback onTap, Key? chave}) =>
      InkWell(
        key: chave,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selecionado ? kNeon.withValues(alpha: .16) : Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selecionado ? kNeon : Colors.white12, width: selecionado ? 2 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nome, style: TextStyle(color: selecionado ? kNeon : Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ]),
        ),
      );

  Widget _campo(TextEditingController c, String label, String hint,
      {bool metros = false, int min = 1, int max = 999999}) {
    return TextFormField(
      controller: c,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
      keyboardType: TextInputType.numberWithOptions(decimal: metros),
      inputFormatters: [
        metros ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')) : FilteringTextInputFormatter.digitsOnly
      ],
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
        final n = metros ? metersToCm(v) : int.tryParse(v);
        if (n == null || n < min) return metros ? 'Valor mínimo: ${cmToMeters(min)} m' : 'Valor mínimo: $min';
        if (n > max) return metros ? 'Valor máximo: ${cmToMeters(max)} m' : 'Valor máximo: $max';
        return null;
      },
    );
  }

  Widget _paginaLocal() => _molde(
        corpo: [
          const _Kicker('Seu trecho'),
          const _Titulo('Deixa eu ver onde você está.'),
          const _Texto('Mostro os radares e as passagens baixas perto de você, pro seu caminhão. Nada sai do seu celular.'),
          if (_avisoLocal != null) ...[
            const SizedBox(height: 10),
            Text(_avisoLocal!, style: const TextStyle(color: Color(0xFFFFB300), fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ],
        botoes: _botoes('Mostrar meu trecho', _mostrarMeuTrecho,
            secundario: 'Escolher cidade', acaoSec: _procurando ? null : _escolherCidade,
            chave: const Key('onb_meu_trecho'), ocupado: _procurando),
      );

  Widget _paginaTrecho() {
    final r = _resumo;
    return _molde(
      corpo: [
        _Kicker(_cidade == null ? 'Perto de você' : 'Perto de $_cidade'),
        _Titulo(r?.titulo ?? ''),
        _Texto(r?.texto ?? ''),
        const SizedBox(height: 10),
        const Row(children: [
          _Legenda(cor: kNeon, texto: 'radar'),
          SizedBox(width: 16),
          _Legenda(cor: Color(0xFFFF3B3B), texto: 'passagem baixa', triangulo: true),
        ]),
      ],
      botoes: _botoes('Próxima', () => _irPara(kPagAjuda)),
    );
  }

  Widget _paginaAjuda() => _molde(
        corpo: const [
          _Kicker('S.O.S.'),
          _Titulo('Deu problema? Quem está perto recebe.'),
          _Texto('E você recebe o pedido de quem precisa. Pra isso, o app precisa poder te avisar.'),
        ],
        botoes: _notif
            ? _botoes('Próxima', () => _irPara(kPagBora))
            : _botoes('Ativar ajuda', _ativarAjuda, chave: const Key('onb_ativar_ajuda')),
      );

  Widget _paginaBora() {
    final soDuranteUso = _loc == LocationPermission.whileInUse;
    return _molde(
      corpo: [
        const _Kicker('Pronto'),
        const _Titulo('Bora pro trecho?'),
        const _Texto('Rota, radar e pedágio no limite do seu caminhão.'),
        const SizedBox(height: 12),
        if (soDuranteUso)
          _CartaoPermissao(
            icone: Icons.my_location,
            titulo: 'Voz com a tela apagada',
            porque: 'Com a localização "o tempo todo", o app fala radar e pedágio mesmo com a tela apagada.',
            estado: PermissaoEstado.pendente,
            rotuloEstado: 'Opcional',
            acao: ('Permitir sempre', widget.permissoes.abrirAjustes),
          ),
        if (_xiaomi)
          _CartaoPermissao(
            icone: Icons.power_settings_new,
            titulo: 'Início automático (Xiaomi)',
            porque: _autostartOk
                ? 'Você confirmou que ligou "No Trecho" na lista. O app não consegue conferir isso sozinho.'
                : 'No Xiaomi essa chave fica desligada de fábrica e o app some em segundo plano. Ligue "No Trecho" na lista e volte.',
            estado: _autostartOk ? PermissaoEstado.concedida : PermissaoEstado.pendente,
            rotuloEstado: _autostartOk ? 'Marcada por você' : 'Manual',
            acao: _autostartOk
                ? null
                : _autostartAberto
                    ? ('Já liguei', _confirmarAutostart)
                    : ('Abrir', () async {
                        final ok = await widget.permissoes.abrirInicioAutomatico();
                        FieldLog.event('onboarding_perm', {'kind': 'autostart', 'result': ok});
                        if (mounted) setState(() => _autostartAberto = true);
                      }),
          ),
      ],
      botoes: _botoes('Começar', _concluir, chave: const Key('onb_comecar')),
    );
  }
}

class _Kicker extends StatelessWidget {
  final String t;
  const _Kicker(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: kNeon, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 2)),
      );
}

class _Titulo extends StatelessWidget {
  final String t;
  const _Titulo(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(color: Colors.white, fontSize: 28, height: 1.12, fontWeight: FontWeight.w800)),
      );
}

class _Texto extends StatelessWidget {
  final String t;
  const _Texto(this.t);
  @override
  Widget build(BuildContext context) =>
      Text(t, style: const TextStyle(color: Color(0xFFC9D6E2), fontSize: 17, height: 1.4));
}

class _Legenda extends StatelessWidget {
  final Color cor;
  final String texto;
  final bool triangulo;
  const _Legenda({required this.cor, required this.texto, this.triangulo = false});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(triangulo ? Icons.change_history : Icons.circle, size: 12, color: cor),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ]);
}

class _CartaoPermissao extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String porque;
  final PermissaoEstado estado;
  final String? rotuloEstado;
  final (String, Future<void> Function())? acao;
  const _CartaoPermissao({
    required this.icone, required this.titulo, required this.porque, required this.estado,
    this.rotuloEstado, this.acao,
  });

  @override
  Widget build(BuildContext context) {
    final ok = estado == PermissaoEstado.concedida;
    final rotulo = rotuloEstado ?? (ok ? 'Concedida' : estado == PermissaoEstado.negadaDeVez ? 'Bloqueada' : 'Pendente');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ok ? kNeon.withValues(alpha: .6) : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icone, color: ok ? kNeon : Colors.white70),
            const SizedBox(width: 10),
            Expanded(child: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ok ? kNeon.withValues(alpha: .18) : Colors.white10,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(rotulo, style: TextStyle(color: ok ? kNeon : Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(porque, style: const TextStyle(color: Color(0xFFC9D6E2), fontSize: 14, height: 1.35)),
          if (acao != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => acao!.$2(),
                style: OutlinedButton.styleFrom(foregroundColor: kNeon, side: const BorderSide(color: kNeon)),
                child: Text(acao!.$1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
