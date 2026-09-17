import 'package:flutter/material.dart';
import '../utils/meters.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/truck_profile.dart';
import '../providers/truck_profile_provider.dart';

class TruckProfileScreen extends StatelessWidget {
  const TruckProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meus Caminhões')),
      body: Consumer<TruckProfileProvider>(
        builder: (context, provider, _) {
          final profiles = provider.profiles;
          if (profiles.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: profiles.length,
            separatorBuilder: (context, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = profiles[i];
              return _ProfileCard(
                profile: p,
                isActive: p.id == provider.activeId,
                canDelete: profiles.length > 1,
                onTap: () async {
                  await provider.setActive(p.id);
                  if (context.mounted) Navigator.pop(context);
                },
                onEdit: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ProfileFormScreen(existing: p),
                  ),
                ),
                onDelete: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Excluir perfil'),
                      content: Text('Excluir "${p.name}"?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Excluir',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await provider.deleteProfile(p.id);
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const _ProfileFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Novo caminhão'),
      ),
    );
  }
}

// ── Card do perfil ────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final TruckProfile profile;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.canDelete,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: isActive ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping,
                size: 28,
                color: isActive ? primary : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isActive ? primary : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Ativo',
                              style: TextStyle(
                                fontSize: 11,
                                color: primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.summaryText,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_outlined,
                    size: 20, color: Colors.grey.shade600),
                onPressed: onEdit,
                tooltip: 'Editar',
              ),
              if (canDelete)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Colors.grey.shade400),
                  onPressed: onDelete,
                  tooltip: 'Excluir',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Formulário (criar / editar) ───────────────────────────────────────────────

class _ProfileFormScreen extends StatefulWidget {
  final TruckProfile? existing;
  const _ProfileFormScreen({this.existing});

  @override
  State<_ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<_ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _lengthCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _axleCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _plateCtrl;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl   = TextEditingController(text: p?.name   ?? '');
    _heightCtrl = TextEditingController(text: cmToMeters(p?.heightCm ?? 420));
    _widthCtrl  = TextEditingController(text: cmToMeters(p?.widthCm  ?? 260));
    _lengthCtrl = TextEditingController(text: cmToMeters(p?.lengthCm ?? 1400));
    _weightCtrl = TextEditingController(text: (p?.weightKg ?? 25000).toString());
    _axleCtrl   = TextEditingController(text: (p?.axleCount ?? 2).toString());
    _modelCtrl  = TextEditingController(text: p?.model ?? '');
    _colorCtrl  = TextEditingController(text: p?.color ?? '');
    _plateCtrl  = TextEditingController(text: p?.plate ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _widthCtrl.dispose();
    _lengthCtrl.dispose();
    _weightCtrl.dispose();
    _axleCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = TruckProfile(
      id:        widget.existing?.id ??
                 DateTime.now().millisecondsSinceEpoch.toString(),
      name:      _nameCtrl.text.trim(),
      heightCm:  metersToCm(_heightCtrl.text)!,
      widthCm:   metersToCm(_widthCtrl.text)!,
      lengthCm:  metersToCm(_lengthCtrl.text)!,
      weightKg:  int.parse(_weightCtrl.text),
      axleCount: int.parse(_axleCtrl.text),
      model:     _modelCtrl.text.trim(),
      color:     _colorCtrl.text.trim(),
      plate:     TruckProfile.normalizePlate(_plateCtrl.text),
    );
    final provider = context.read<TruckProfileProvider>();
    await provider.saveProfile(profile);
    if (!_isEditing && context.mounted) {
      await provider.setActive(profile.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar caminhão' : 'Novo caminhão'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field(
                ctrl: _nameCtrl,
                label: 'Nome do perfil',
                hint: 'Ex: Bitrem 9 eixos',
                isText: true,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _heightCtrl,
                label: 'Altura (m)',
                hint: 'Ex: 4,20',
                max: 700,
                meters: true,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _lengthCtrl,
                label: 'Comprimento (m)',
                hint: 'Ex: 14,00',
                max: 3000,
                meters: true,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _widthCtrl,
                label: 'Largura (m)',
                hint: 'Ex: 2,60',
                max: 400,
                meters: true,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _weightCtrl,
                label: 'Peso bruto (kg)',
                hint: 'Ex: 25000',
                max: 100000,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _axleCtrl,
                label: 'Número de eixos',
                hint: 'Ex: 2',
                min: 2,
                max: 9,
              ),
              const SizedBox(height: 28),
              // Identidade visual: é por caminhão, não por motorista, porque é
              // ela que vai na ficha do S.O.S. — e quem roda dois caminhões
              // anunciava o errado quando isso morava no perfil da pessoa.
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pra te acharem na estrada',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Aparece pra quem estiver perto quando você pedir S.O.S. '
                  'Opcional.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _modelCtrl,
                label: 'Modelo',
                hint: 'Ex: Scania R450',
                isText: true,
                opcional: true,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _colorCtrl,
                label: 'Cor',
                hint: 'Ex: Branco',
                isText: true,
                opcional: true,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _plateCtrl,
                label: 'Placa',
                hint: 'Ex: ABC1D23',
                isText: true,
                opcional: true,
                cap: TextCapitalization.characters,
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                validaTexto: (v) =>
                    TruckProfile.isValidPlate(TruckProfile.normalizePlate(v))
                        ? null
                        : 'Placa inválida',
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(
                      _isEditing ? 'Salvar alterações' : 'Criar perfil'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    bool isText = false,
    bool meters = false, // texto em metros, limites (min/max) em cm
    bool opcional = false,
    TextCapitalization? cap,
    List<TextInputFormatter>? formatters,
    String? Function(String)? validaTexto,
    int min = 1,
    int max = 999999,
  }) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      keyboardType: isText
          ? TextInputType.text
          : TextInputType.numberWithOptions(decimal: meters),
      textCapitalization: cap ??
          (isText ? TextCapitalization.words : TextCapitalization.none),
      inputFormatters: formatters ??
          (isText
              ? []
              : meters
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
                  : [FilteringTextInputFormatter.digitsOnly]),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return opcional ? null : 'Campo obrigatório';
        }
        if (isText) return validaTexto?.call(v);
        final n = meters ? metersToCm(v) : int.tryParse(v);
        if (n == null || n < min) {
          return meters ? 'Valor mínimo: ${cmToMeters(min)} m' : 'Valor mínimo: $min';
        }
        if (n > max) {
          return meters ? 'Valor máximo: ${cmToMeters(max)} m' : 'Valor máximo: $max';
        }
        return null;
      },
    );
  }
}
