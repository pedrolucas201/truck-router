import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/radar_point.dart';
import 'add_restriction_sheet.dart'; // reusa RestrictionTypeChip
import 'speed_plate.dart'; // mesmas plaquinhas R-19 da curadoria (pedido Gilberto 12/07)

/// Sheet pra adicionar um radar (crowd-source). Espelha o AddRestrictionSheet,
/// mas com tipo de radar + velocidade. Retorna um RadarPoint (source 'user').
class AddRadarSheet extends StatefulWidget {
  final LatLng position;
  const AddRadarSheet({super.key, required this.position});

  @override
  State<AddRadarSheet> createState() => _AddRadarSheetState();
}

class _AddRadarSheetState extends State<AddRadarSheet> {
  String _type = 'Radar Fixo';
  int? _speed; // km/h escolhido nas plaquinhas (null = ainda não escolheu)

  bool get _needsSpeed => _type != 'Lombada';

  void _save() {
    int speed = 0;
    if (_needsSpeed) {
      if (_speed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escolha a velocidade (km/h)')),
        );
        return;
      }
      speed = _speed!;
    }
    Navigator.pop(
      context,
      RadarPoint(
        lat: widget.position.latitude,
        lng: widget.position.longitude,
        type: _type,
        speedKmh: speed,
        source: 'user',
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
          Text('Marcar radar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('Tipo',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              RestrictionTypeChip(
                label: 'Radar fixo',
                icon: Icons.camera_alt,
                selected: _type == 'Radar Fixo',
                onTap: () => setState(() => _type = 'Radar Fixo'),
              ),
              RestrictionTypeChip(
                label: 'Lombada',
                icon: Icons.speed,
                selected: _type == 'Lombada',
                onTap: () => setState(() => _type = 'Lombada'),
              ),
            ],
          ),
          if (_needsSpeed) ...[
            const SizedBox(height: 16),
            Text('Velocidade',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // Plaquinhas R-19, mesmas da curadoria. Não selecionada = esmaecida.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final s in [60, 70, 80, 90])
                  Opacity(
                    opacity: _speed == null || _speed == s ? 1.0 : 0.4,
                    child: SpeedPlate(
                        kmh: s, onTap: () => setState(() => _speed = s)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Marcar radar'),
            ),
          ),
        ],
      ),
    );
  }
}
