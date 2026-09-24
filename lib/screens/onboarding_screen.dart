import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/truck_profile_provider.dart';
import '../services/field_log.dart';
import '../services/location_asked.dart';
import '../services/sistema.dart';
import '../utils/meters.dart';
import '../widgets/onboarding/cena_onboarding.dart';
import '../widgets/onboarding/onboarding_logic.dart';
import 'map_screen.dart';

/// O que a tela de permissões pergunta ao sistema. Interface pra o teste de
/// widget não bater em plugin; o app usa [PermissoesReais].
abstract class PermissoesApi {
  Future<LocationPermission> localizacao();
  Future<LocationPermission> pedirLocalizacao();
  Future<bool> notificacaoOk();
  Future<void> pedirNotificacao();
  Future<bool> bateriaIsenta();
  Future<void> pedirBateria();
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
  Future<bool> notificacaoOk() async =>
      await FlutterForegroundTask.checkNotificationPermission() == NotificationPermission.granted;
  @override
  Future<void> pedirNotificacao() => FlutterForegroundTask.requestNotificationPermission();
  @override
  Future<bool> bateriaIsenta() => FlutterForegroundTask.isIgnoringBatteryOptimizations;
  @override
  Future<void> pedirBateria() => FlutterForegroundTask.requestIgnoreBatteryOptimization();
  @override
  Future<void> abrirAjustes() => Geolocator.openAppSettings();
  @override
  Future<bool> ehXiaomi() => Sistema.ehXiaomi();
  @override
  Future<bool> abrirInicioAutomatico() => Sistema.abrirInicioAutomatico();
}

/// Onboarding: 5 telas de apresentação, "Seu caminhão", permissões.
/// Spec: docs/superpowers/specs/2026-09-24-onboarding-design.md.
/// Permissão negada nunca segura: "Começar" libera sempre.
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

  // Página 6
  final _form = GlobalKey<FormState>();
  final _altura = TextEditingController();
  final _comprimento = TextEditingController();
  final _peso = TextEditingController();
  final _eixos = TextEditingController();
  bool _formPreenchido = false;

  // Página 7
  LocationPermission _loc = LocationPermission.denied;
  bool _notif = false;
  bool _bateria = false;
  bool _xiaomi = false;

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
    if (_formPreenchido) return;
    _formPreenchido = true;
    final p = context.read<TruckProfileProvider>().profile;
    _altura.text = cmToMeters(p.heightCm);
    _comprimento.text = cmToMeters(p.lengthCm);
    _peso.text = p.weightKg.toString();
    _eixos.text = p.axleCount.toString();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou dos Ajustes: os cartões têm que refletir o que ele mexeu lá.
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
    final r = await Future.wait<Object>([
      api.localizacao(), api.notificacaoOk(), api.bateriaIsenta(), api.ehXiaomi(),
    ]).catchError((_) => <Object>[LocationPermission.denied, false, false, false]);
    if (!mounted) return;
    setState(() {
      _loc = r[0] as LocationPermission;
      _notif = r[1] as bool;
      _bateria = r[2] as bool;
      _xiaomi = r[3] as bool;
    });
  }

  void _irPara(int i) {
    _ctrl.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Future<void> _proxima() async {
    if (_pagina == kPaginaCaminhao && !await _salvarCaminhao()) return;
    if (_pagina == kPaginaPermissoes) return _concluir();
    _irPara(_pagina + 1);
  }

  void _pular() {
    final destino = pularDestino(_pagina);
    if (destino == null) return;
    FieldLog.event('onboarding_skip', {'from': _pagina});
    _irPara(destino);
  }

  /// Grava só se mudou do caminhão ativo: passar direto não escreve nada
  /// (nem no espelho da conta).
  Future<bool> _salvarCaminhao() async {
    if (!(_form.currentState?.validate() ?? false)) return false;
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
    FieldLog.event('onboarding_truck', {'changed': mudou});
    if (mudou) {
      await provider.saveProfile(atual.copyWith(
          heightCm: alturaCm, lengthCm: compCm, weightKg: peso, axleCount: eixos));
    }
    return true;
  }

  Future<void> _concluir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    FieldLog.event('onboarding_done', {'ms': _sw.elapsedMilliseconds});
    if (!mounted) return;
    if (widget.aoConcluir != null) return widget.aoConcluir!();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MapScreen()));
  }

  // ── Permissões ─────────────────────────────────────────────────────────────

  Future<void> _pedirLocalizacao() async {
    // Carimba ANTES de pedir: é a mesma marca do boot do mapa, então ele não
    // gasta a segunda chance (a segunda negação no Android é permanente).
    await markLocationAsked();
    final r = await widget.permissoes.pedirLocalizacao();
    FieldLog.event('onboarding_perm', {'kind': 'loc', 'result': r.name});
    if (mounted) setState(() => _loc = r);
  }

  Future<void> _pedirNotificacao() async {
    await widget.permissoes.pedirNotificacao();
    final ok = await widget.permissoes.notificacaoOk();
    FieldLog.event('onboarding_perm', {'kind': 'notif', 'result': ok});
    if (mounted) setState(() => _notif = ok);
  }

  Future<void> _pedirBateria() async {
    await widget.permissoes.pedirBateria();
    final ok = await widget.permissoes.bateriaIsenta();
    FieldLog.event('onboarding_perm', {'kind': 'bateria', 'result': ok});
    if (mounted) setState(() => _bateria = ok);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Visual único da marca, independente do tema do sistema.
    final tema = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kNeon, brightness: Brightness.dark, surface: kFundo),
    );
    return Theme(
      data: tema,
      child: Scaffold(
        backgroundColor: kFundo,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _ctrl,
                  physics: const ClampingScrollPhysics(),
                  onPageChanged: (i) {
                    setState(() => _pagina = i);
                    FieldLog.event('onboarding_step', {'i': i});
                    if (i == kPaginaPermissoes) unawaited(_lerPermissoes());
                  },
                  children: [
                    for (var i = 0; i < kTelasOnboarding.length; i++)
                      _Apresentacao(tela: kTelasOnboarding[i], ativa: _pagina == i),
                    _paginaCaminhao(),
                    _paginaPermissoes(),
                  ],
                ),
              ),
              _rodape(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rodape() {
    final ultima = _pagina == kPaginaPermissoes;
    final pular = pularDestino(_pagina) != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < kTotalPaginas; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _pagina ? 22 : 7, height: 7,
                  decoration: BoxDecoration(
                    color: i == _pagina ? kNeon : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (pular)
                TextButton(
                  key: const Key('onb_pular'),
                  onPressed: _pular,
                  child: const Text('Pular', style: TextStyle(color: Colors.white70)),
                ),
              const Spacer(),
              FilledButton(
                key: const Key('onb_proxima'),
                onPressed: _proxima,
                style: FilledButton.styleFrom(
                  backgroundColor: kNeon, foregroundColor: const Color(0xFF06140A),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(ultima ? 'Começar' : 'Próxima',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paginaCaminhao() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Kicker('Seu caminhão'),
              const _Titulo('Com que caminhão você roda?'),
              const _Texto('É isso que decide ponte, balança e o valor do pedágio. Dá pra mudar depois em "Caminhões".'),
              const SizedBox(height: 20),
              _campo(_altura, 'Altura (m)', 'Ex: 4,20', metros: true, max: 700),
              const SizedBox(height: 12),
              _campo(_comprimento, 'Comprimento (m)', 'Ex: 14,00', metros: true, max: 3000),
              const SizedBox(height: 12),
              _campo(_peso, 'Peso bruto (kg)', 'Ex: 25000', max: 100000),
              const SizedBox(height: 12),
              _campo(_eixos, 'Número de eixos', 'Ex: 5', min: 2, max: 9),
            ],
          ),
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

  Widget _paginaPermissoes() {
    final loc = estadoLocalizacao(_loc);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Kicker('Permissões'),
          const _Titulo('Pra avisar com a tela apagada.'),
          const _Texto('O app fala radar e pedágio com o celular no bolso ou no suporte. Pra isso o Android pede três coisas.'),
          const SizedBox(height: 16),
          _CartaoPermissao(
            icone: Icons.my_location,
            titulo: 'Localização',
            porque: 'Sem ela não tem rota nem alerta. "O tempo todo" mantém a voz viva com a tela apagada.',
            estado: loc,
            acao: switch (loc) {
              PermissaoEstado.pendente => ('Permitir', _pedirLocalizacao),
              PermissaoEstado.negadaDeVez => ('Abrir Ajustes', widget.permissoes.abrirAjustes),
              PermissaoEstado.concedida when _loc != LocationPermission.always =>
                ('Permitir sempre', widget.permissoes.abrirAjustes),
              _ => null,
            },
          ),
          _CartaoPermissao(
            icone: Icons.notifications_active,
            titulo: 'Notificação',
            porque: 'É ela que segura a navegação viva em segundo plano e traz o pedido de ajuda de outro motorista.',
            estado: _notif ? PermissaoEstado.concedida : PermissaoEstado.pendente,
            acao: _notif ? null : ('Permitir', _pedirNotificacao),
          ),
          _CartaoPermissao(
            icone: Icons.battery_saver,
            titulo: 'Bateria sem restrição',
            porque: 'Sem isso o celular mata o app no meio da viagem pra economizar bateria.',
            estado: _bateria ? PermissaoEstado.concedida : PermissaoEstado.pendente,
            acao: _bateria ? null : ('Permitir', _pedirBateria),
          ),
          if (_xiaomi)
            _CartaoPermissao(
              icone: Icons.power_settings_new,
              titulo: 'Início automático (Xiaomi)',
              porque: 'No Xiaomi essa chave fica desligada de fábrica e o app some em segundo plano. Ligue "No Trecho" na lista.',
              estado: PermissaoEstado.pendente,
              rotuloEstado: 'Manual',
              acao: ('Abrir', () async {
                final ok = await widget.permissoes.abrirInicioAutomatico();
                FieldLog.event('onboarding_perm', {'kind': 'autostart', 'result': ok});
              }),
            ),
          const SizedBox(height: 8),
          const _Texto('Se preferir, dá pra liberar depois: o mapa avisa o que ficou faltando.'),
        ],
      ),
    );
  }
}

class _Apresentacao extends StatelessWidget {
  final TelaOnboarding tela;
  final bool ativa;
  const _Apresentacao({required this.tela, required this.ativa});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(flex: 11, child: CenaOnboarding(tela: tela, ativa: ativa)),
        Expanded(
          flex: 9,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: ativa ? 1 : 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_Kicker(tela.kicker), _Titulo(tela.titulo), _Texto(tela.texto)],
              ),
            ),
          ),
        ),
      ],
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
            style: const TextStyle(color: Colors.white, fontSize: 30, height: 1.12, fontWeight: FontWeight.w800)),
      );
}

class _Texto extends StatelessWidget {
  final String t;
  const _Texto(this.t);
  @override
  Widget build(BuildContext context) =>
      Text(t, style: const TextStyle(color: Color(0xFFC9D6E2), fontSize: 17, height: 1.4));
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
      padding: const EdgeInsets.all(16),
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
            Expanded(child: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ok ? kNeon.withValues(alpha: .18) : Colors.white10,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(rotulo, style: TextStyle(color: ok ? kNeon : Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(porque, style: const TextStyle(color: Color(0xFFC9D6E2), fontSize: 14, height: 1.35)),
          if (acao != null) ...[
            const SizedBox(height: 10),
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
