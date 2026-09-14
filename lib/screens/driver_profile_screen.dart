import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/driver_profile.dart';
import '../services/auth_service.dart';
import '../services/driver_profile_service.dart';

/// "Meu perfil": quem é o motorista (Fase 0 do S.O.S.). Conta Google em cima
/// porque é ela que segura o perfil numa reinstalação; os campos abaixo.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name  = TextEditingController();
  final _truck = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _phone = TextEditingController();

  bool _loading = true;
  bool _busy = false; // login ou save em andamento

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var p = await DriverProfileService.loadLocal();
    // Aparelho limpo com Google já vinculado (SDK restaurou o usuário): o
    // espelho é a única cópia.
    p ??= AuthService.isGoogleLinked
        ? await DriverProfileService.fetchRemote()
        : null;
    if (!mounted) return;
    if (p != null) _fill(p);
    setState(() => _loading = false);
  }

  void _fill(DriverProfile p) {
    _name.text  = p.name;
    _truck.text = p.truck;
    _color.text = p.color;
    _plate.text = p.plate;
    _phone.text = p.phone;
  }

  @override
  void dispose() {
    for (final c in [_name, _truck, _color, _plate, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    final r = await AuthService.linkWithGoogle();
    if (!mounted) return;
    switch (r) {
      case GoogleLinkResult.linked:
        _snack('Conta conectada');
      case GoogleLinkResult.recovered:
        // Uid antigo voltou: o perfil dele manda sobre o que está na tela.
        final p = await DriverProfileService.fetchRemote();
        if (p != null) _fill(p);
        _snack('Bem-vindo de volta, seu perfil foi recuperado');
      case GoogleLinkResult.alreadyLinked:
        break;
      case GoogleLinkResult.canceled:
        break;
      case GoogleLinkResult.failed:
        _snack('Não deu pra entrar com o Google agora. Tente de novo mais tarde.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await DriverProfileService.save(DriverProfile(
      name:  _name.text.trim(),
      truck: _truck.text.trim(),
      color: _color.text.trim(),
      plate: DriverProfile.normalizePlate(_plate.text),
      phone: DriverProfile.normalizePhone(_phone.text),
    ));
    if (!mounted) return;
    _snack('Perfil salvo');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GoogleCard(busy: _busy, onTap: _google),
                    const SizedBox(height: 20),
                    _field(_name, 'Nome', 'Como os outros motoristas vão te chamar',
                        cap: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Campo obrigatório'
                            : null),
                    const SizedBox(height: 12),
                    _field(_truck, 'Caminhão', 'Ex: Scania R450',
                        cap: TextCapitalization.words),
                    const SizedBox(height: 12),
                    _field(_color, 'Cor', 'Ex: Branco',
                        cap: TextCapitalization.words),
                    const SizedBox(height: 12),
                    _field(_plate, 'Placa', 'Ex: ABC1D23',
                        cap: TextCapitalization.characters,
                        formatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9-]')),
                          LengthLimitingTextInputFormatter(8),
                        ],
                        validator: (v) => DriverProfile.isValidPlate(
                                DriverProfile.normalizePlate(v ?? ''))
                            ? null
                            : 'Placa inválida'),
                    const SizedBox(height: 12),
                    _field(_phone, 'Telefone (WhatsApp)', 'Ex: 11 99999-8888',
                        keyboard: TextInputType.phone,
                        formatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9 ()-]')),
                          LengthLimitingTextInputFormatter(16),
                        ],
                        validator: (v) => DriverProfile.isValidPhone(
                                DriverProfile.normalizePhone(v ?? ''))
                            ? null
                            : 'Telefone inválido (DDD + número)'),
                    const SizedBox(height: 8),
                    Text(
                      'Placa e telefone aparecem só pra quem estiver perto de '
                      'você quando você pedir ajuda na estrada.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    TextCapitalization cap = TextCapitalization.none,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      textCapitalization: cap,
      keyboardType: keyboard,
      inputFormatters: formatters,
      validator: validator,
    );
  }
}

class _GoogleCard extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _GoogleCard({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final email = AuthService.googleEmail;
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: email != null
            ? Row(children: [
                Icon(Icons.verified_user, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Conta conectada',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(email,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Entre com o Google pra não perder seu perfil se trocar '
                    'de celular ou reinstalar o app.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onTap,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: const Text('Entrar com o Google'),
                  ),
                ],
              ),
      ),
    );
  }
}
