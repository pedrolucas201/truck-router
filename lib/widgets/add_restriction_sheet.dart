import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/user_restriction.dart';

class AddRestrictionSheet extends StatefulWidget {
  final LatLng position;
  final String saveLabel;

  const AddRestrictionSheet({
    super.key,
    required this.position,
    this.saveLabel = 'Marcar e recalcular',
  });

  @override
  State<AddRestrictionSheet> createState() => _AddRestrictionSheetState();
}

class _AddRestrictionSheetState extends State<AddRestrictionSheet> {
  String _type = 'maxheight';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _unit => _type == 'maxweight' ? 't' : 'm';

  void _save() {
    final raw = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (raw == null || raw <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido')),
      );
      return;
    }
    Navigator.pop(
      context,
      UserRestriction(
        lat: widget.position.latitude,
        lng: widget.position.longitude,
        type: _type,
        value: raw,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Marcar restrição', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('Tipo de restrição',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              RestrictionTypeChip(
                label: 'Altura',
                icon: Icons.height,
                selected: _type == 'maxheight',
                onTap: () => setState(() => _type = 'maxheight'),
              ),
              RestrictionTypeChip(
                label: 'Peso',
                icon: Icons.monitor_weight,
                selected: _type == 'maxweight',
                onTap: () => setState(() => _type = 'maxweight'),
              ),
              RestrictionTypeChip(
                label: 'Largura',
                icon: Icons.swap_horiz,
                selected: _type == 'maxwidth',
                onTap: () => setState(() => _type = 'maxwidth'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _type == 'maxheight'
                ? 'Altura máxima permitida'
                : _type == 'maxweight'
                    ? 'Peso máximo permitido'
                    : 'Largura máxima permitida',
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: _type == 'maxweight' ? 'ex: 20' : 'ex: 4.2',
              suffixText: _unit,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add_location_alt),
              label: Text(widget.saveLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class RestrictionTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const RestrictionTypeChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary.withAlpha(30) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? primary : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? primary : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? primary : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
