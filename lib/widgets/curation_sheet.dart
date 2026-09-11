import 'package:flutter/material.dart';
import '../models/radar_point.dart';
import 'speed_plate.dart';

/// Folha de curadoria do toque num radar (nav e mapa usam a MESMA): 1 toque
/// resolve. Devolve `'speed:X'` (existe, velocidade real X), `'confirm'`
/// (existe, mantém), `'remove'` (não existe) ou null (fechou sem mexer).
///
/// Pedágio não tem placa de velocidade: a folha some com os chips e pergunta
/// só "existe aqui?". Antes ela oferecia 60/70/80/90 numa praça, e foi assim
/// que nasceu um "não existe" em Jacareí em 13/07 (pergunta sem sentido induz
/// resposta errada). O card automático da nav também não sobe em pedágio
/// (`_maybePromptCuration`): na praça o motorista está trocando de faixa.
Future<String?> showCurationSheet(BuildContext context, RadarPoint radar) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (_) => CurationSheet(radar: radar),
    );

class CurationSheet extends StatelessWidget {
  final RadarPoint radar;
  const CurationSheet({super.key, required this.radar});

  @override
  Widget build(BuildContext context) {
    final r = radar;
    final isPedagio = r.type.toLowerCase().contains('pedagio');
    final title = isPedagio
        ? (r.name == null ? 'Pedágio' : 'Pedágio ${r.name}')
        : r.speedKmh > 0
            ? 'Radar ${r.speedKmh} km/h'
            : (r.type.isEmpty ? 'Radar' : r.type);
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(isPedagio ? Icons.toll : Icons.camera_alt),
          title: Text(title),
          subtitle: Text(isPedagio
              ? 'Existe aqui?'
              : 'Existe aqui? Qual a velocidade real?'),
        ),
        const Divider(height: 1),
        if (!isPedagio)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final s in [60, 70, 80, 90])
                  SpeedPlate(
                      kmh: s, onTap: () => Navigator.pop(context, 'speed:$s')),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(isPedagio ? 'Existe' : 'Existe (manter velocidade)'),
          onTap: () => Navigator.pop(context, 'confirm'),
        ),
        ListTile(
          leading: const Icon(Icons.cancel, color: Colors.red),
          title: const Text('Não existe aqui'),
          onTap: () => Navigator.pop(context, 'remove'),
        ),
      ]),
    );
  }
}
