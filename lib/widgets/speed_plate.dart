import 'package:flutter/material.dart';

/// Placa de limite de velocidade (padrão R-19 brasileiro): círculo branco, anel
/// vermelho grosso, número preto grande + "km/h". Usada nos chips de curadoria
/// de radar (o passo em que o motorista escolhe a velocidade real). Pedido do
/// Gilberto (2026-07-09): a plaquinha de trânsito é o que ele lê num relance.
///
/// Só aqui — no mapa e no bottom bar o número segue no formato antigo (decisão
/// do Pedro na mesma data).
class SpeedPlate extends StatelessWidget {
  /// null = placa EM BRANCO (toque pra digitar a velocidade).
  final int? kmh;
  final double size;
  final VoidCallback? onTap;

  const SpeedPlate({super.key, required this.kmh, this.size = 54, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ring = size * 0.09;
    final plate = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.red.shade700, width: ring),
      ),
      alignment: Alignment.center,
      // FittedBox: o '···' da placa em branco estourava o círculo por 3,7px, e
      // agora que dá pra DIGITAR a velocidade, 3 dígitos (110/120) estourariam
      // também. Encolhe pra caber em vez de vazar.
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ring * 1.5),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kmh?.toString() ?? '···',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: size * 0.37,
                      fontWeight: FontWeight.w800,
                      height: 1.0)),
              Text('km/h',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: size * 0.15,
                      fontWeight: FontWeight.w600,
                      height: 1.0)),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return plate;
    // Círculo → borda circular no ripple.
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: plate,
    );
  }
}

/// Linha de plaquinhas pra escolher a velocidade: os presets de rodovia + uma
/// placa EM BRANCO pra digitar qualquer valor.
///
/// A placa em branco é pedido de campo do Gilberto (2026-07-13): ele passou por um
/// radar de 40 dentro da cidade e o mínimo que dava pra escolher era 60. O
/// trade-off "só 60/70/80/90" cobria rodovia e foi REPROVADO na cidade.
///
/// Um componente só porque os dois fluxos precisam disso: marcar radar novo
/// (AddRadarSheet) e corrigir a velocidade de um existente (curadoria, na nav).
/// Consertar num lugar só deixaria metade do problema em pé.
class SpeedPlatePicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onChanged;
  final double size;

  static const presets = [60, 70, 80, 90];

  const SpeedPlatePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.size = 54,
  });

  bool get _isCustom => selected != null && !presets.contains(selected);

  Future<void> _digitar(BuildContext context) async {
    final ctrl = TextEditingController(
        text: _isCustom ? selected!.toString() : '');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Velocidade do radar'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            suffixText: 'km/h',
            hintText: 'Ex: 40',
          ),
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    // Faixa sã de placa brasileira. Lixo digitado não vira radar na base crowd.
    if (v != null && v >= 10 && v <= 120) onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final s in presets)
          Opacity(
            opacity: selected == null || selected == s ? 1.0 : 0.4,
            child: SpeedPlate(kmh: s, size: size, onTap: () => onChanged(s)),
          ),
        // Em branco enquanto nada foi digitado; assim que o motorista digita, a
        // própria placa passa a mostrar o valor (40, 110, o que for).
        Opacity(
          opacity: selected == null || _isCustom ? 1.0 : 0.4,
          child: SpeedPlate(
            kmh: _isCustom ? selected : null,
            size: size,
            onTap: () => _digitar(context),
          ),
        ),
      ],
    );
  }
}
