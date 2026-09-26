import 'package:flutter/material.dart';

import '../../models/truck_profile.dart';
import '../../providers/theme_controller.dart';
import '../../services/field_log.dart';
import '../../utils/meters.dart';

/// Menu principal (gaveta em tela cheia, no jeito do Waze, pedido do Pedro em
/// 26/09: o ⋮ estava lotado). Cabeçalho com o motorista e o caminhão ativo,
/// cinco itens, Configurações agrupa o que é ajuste. Nenhum item saiu: Tema,
/// Voz do guia e Ver apresentação estão dentro de Configurações.
class MenuPrincipal extends StatelessWidget {
  final String? nomeMotorista;
  final TruckProfile caminhao;
  final TemaEscolha tema;
  final VoidCallback onPerfil;
  final VoidCallback onCaminhoes;
  final VoidCallback onHistorico;
  final VoidCallback onSos;
  final VoidCallback onTema;
  final VoidCallback onVoz;
  final VoidCallback onApresentacao;
  final VoidCallback onSobre;

  const MenuPrincipal({
    super.key,
    required this.nomeMotorista,
    required this.caminhao,
    required this.tema,
    required this.onPerfil,
    required this.onCaminhoes,
    required this.onHistorico,
    required this.onSos,
    required this.onTema,
    required this.onVoz,
    required this.onApresentacao,
    required this.onSobre,
  });

  /// Fecha a gaveta e só então abre o destino (senão a tela nova abre por
  /// baixo da gaveta que está fechando).
  VoidCallback _vai(BuildContext ctx, VoidCallback f) => () {
        Navigator.pop(ctx);
        f();
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primeiroNome = (nomeMotorista ?? '').trim().split(' ').first;
    return Drawer(
      width: MediaQuery.of(context).size.width,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: IconButton.filledTonal(
                  key: const Key('menu_fechar'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset('assets/brand/icone.png', width: 72, height: 72),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(primeiroNome.isEmpty ? 'Oi, motorista!' : 'Oi, $primeiroNome!',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      key: const Key('menu_perfil'),
                      onPressed: _vai(context, onPerfil),
                      child: const Text('Ver perfil'),
                    ),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: const Key('menu_caminhao'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: _vai(context, onCaminhoes),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Icon(Icons.local_shipping, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${caminhao.name} · ${cmToMeters(caminhao.heightCm)} m · ${caminhao.axleCount} eixos',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    ]),
                  ),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 8), child: Divider(height: 1)),
            _Item(Icons.history, 'Histórico de rotas', _vai(context, onHistorico)),
            _Item(Icons.sos, 'Pedir ajuda', _vai(context, onSos), cor: Colors.red.shade400),
            _Item(Icons.local_shipping_outlined, 'Caminhões', _vai(context, onCaminhoes)),
            _Item(Icons.settings_outlined, 'Configurações', () => _configuracoes(context)),
            _Item(Icons.info_outline, 'Sobre', _vai(context, onSobre)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('No Trecho ${FieldLog.appVersion}',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  void _configuracoes(BuildContext context) {
    final nomeTema = switch (tema) {
      TemaEscolha.automatico => 'Automático',
      TemaEscolha.claro => 'Claro',
      TemaEscolha.escuro => 'Escuro',
    };
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Tema'),
            subtitle: Text(nomeTema),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              onTema();
            },
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voz do guia'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              onVoz();
            },
          ),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('Ver apresentação'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              onApresentacao();
            },
          ),
        ]),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icone;
  final String texto;
  final VoidCallback onTap;
  final Color? cor;
  const _Item(this.icone, this.texto, this.onTap, {this.cor});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        leading: Icon(icone, size: 28, color: cor),
        title: Text(texto, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        onTap: onTap,
      );
}
