import 'package:flutter/material.dart';
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

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl   = TextEditingController(text: p?.name   ?? '');
    _heightCtrl = TextEditingController(text: (p?.heightCm ?? 420).toString());
    _widthCtrl  = TextEditingController(text: (p?.widthCm  ?? 260).toString());
    _lengthCtrl = TextEditingController(text: (p?.lengthCm ?? 1400).toString());
    _weightCtrl = TextEditingController(text: (p?.weightKg ?? 25000).toString());
    _axleCtrl   = TextEditingController(text: (p?.axleCount ?? 2).toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _widthCtrl.dispose();
    _lengthCtrl.dispose();
    _weightCtrl.dispose();
    _axleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = TruckProfile(
      id:        widget.existing?.id ??
                 DateTime.now().millisecondsSinceEpoch.toString(),
      name:      _nameCtrl.text.trim(),
      heightCm:  int.parse(_heightCtrl.text),
      widthCm:   int.parse(_widthCtrl.text),
      lengthCm:  int.parse(_lengthCtrl.text),
      weightKg:  int.parse(_weightCtrl.text),
      axleCount: int.parse(_axleCtrl.text),
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
                label: 'Altura (cm)',
                hint: 'Ex: 420',
                max: 700,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _lengthCtrl,
                label: 'Comprimento (cm)',
                hint: 'Ex: 1400',
                max: 3000,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _widthCtrl,
                label: 'Largura (cm)',
                hint: 'Ex: 260',
                max: 400,
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
      keyboardType: isText ? TextInputType.text : TextInputType.number,
      textCapitalization:
          isText ? TextCapitalization.words : TextCapitalization.none,
      inputFormatters:
          isText ? [] : [FilteringTextInputFormatter.digitsOnly],
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
        if (isText) return null;
        final n = int.tryParse(v);
        if (n == null || n < min) return 'Valor mínimo: $min';
        if (n > max) return 'Valor máximo: $max';
        return null;
      },
    );
  }
}
