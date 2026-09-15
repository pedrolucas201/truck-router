import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../services/field_log.dart';
import '../services/update_service.dart';

/// Card direto na abertura (Pedro, 15/09: "mostra o card direto"; a placa
/// amarela que o Beto pediu ficou estranha na tela e saiu). O que mudou →
/// Atualizar → barra de download (sha256 conferido pelo plugin) → instalador
/// do sistema. `force` = abaixo do mínimo suportado, não fecha.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  FieldLog.event('update_prompt', {'build': info.build});
  return showDialog(
    context: context,
    barrierDismissible: !info.force,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = não começou; 0-100 = baixando
  bool _installing = false;
  String? _error;

  bool get _busy => _progress != null && !_installing && _error == null;

  static const _erroRede =
      'Não consegui baixar a atualização. Confira a internet e tente de novo.';
  // Chave de assinatura trocou em 10/09/2026: quem ainda tem um build antigo
  // (chave de debug) toma erro de instalação por cima. Não dá pra distinguir
  // do resto pelo plugin, então a saída vale pra todos.
  static const _erroInstalar =
      'Não instalou. Desinstale o No Trecho e instale de novo pelo link do grupo.';

  void _start() {
    setState(() {
      _progress = 0;
      _error = null;
      _installing = false;
    });
    FieldLog.event('update_start', {'build': widget.info.build});
    try {
      OtaUpdate()
          .execute(
            widget.info.url,
            destinationFilename: 'no-trecho.apk',
            sha256checksum: widget.info.sha256.isEmpty
                ? null
                : widget.info.sha256,
          )
          .listen((OtaEvent e) {
            if (!mounted) return;
            switch (e.status) {
              case OtaStatus.DOWNLOADING:
                setState(
                  () => _progress = double.tryParse(e.value ?? '') ?? _progress,
                );
              case OtaStatus.INSTALLING:
                setState(() => _installing = true);
              case OtaStatus.INSTALLATION_DONE:
                FieldLog.event('update_done', {'build': widget.info.build});
                Navigator.of(context).maybePop();
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _falha(
                  'permissao',
                  'Permita "instalar apps desconhecidos" pro No Trecho e tente de novo.',
                );
              case OtaStatus.CANCELED:
                setState(() => _progress = null);
              case OtaStatus.CHECKSUM_ERROR:
                _falha(
                  'checksum',
                  _erroRede,
                ); // download corrompido: baixa de novo
              case OtaStatus.INSTALLATION_ERROR:
                _falha('instalar', _erroInstalar);
              case OtaStatus.DOWNLOAD_ERROR:
              case OtaStatus.INTERNAL_ERROR:
              case OtaStatus.ALREADY_RUNNING_ERROR:
                _falha(e.status.name, _erroRede);
            }
          }, onError: (Object err) => _falha('stream', _erroRede));
    } catch (_) {
      _falha('execute', 'Não consegui iniciar a atualização. Tente de novo.');
    }
  }

  void _falha(String why, String msg) {
    if (!mounted) return;
    FieldLog.event('update_fail', {'why': why, 'build': widget.info.build});
    setState(() => _error = msg);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return PopScope(
      canPop: !info.force && !_busy,
      child: AlertDialog(
        icon: const Icon(
          Icons.warning_rounded,
          color: Color(0xFFFFC107),
          size: 40,
        ),
        title: Text(
          'Nova atualização${info.version.isNotEmpty ? ' v${info.version}' : ''}',
        ),
        content: _content(),
        actions: _actions(),
      ),
    );
  }

  Widget _content() {
    if (_error != null) return Text(_error!);
    if (_installing) {
      return const Text('Baixou. Abrindo o instalador… toque em Instalar.');
    }
    if (_progress != null) {
      final pct = _progress!.clamp(0, 100).toInt();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Baixando… $pct%'),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress! / 100),
        ],
      );
    }
    final notes = widget.info.notes.trim();
    return Text(
      notes.isNotEmpty ? 'O que mudou:\n$notes' : 'Tem uma versão nova do app.',
    );
  }

  List<Widget> _actions() {
    if (_busy || _installing) return const [];
    if (_error != null) {
      return [
        if (!widget.info.force)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        FilledButton(onPressed: _start, child: const Text('Tentar de novo')),
      ];
    }
    return [
      if (!widget.info.force)
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Depois'),
        ),
      FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.download_rounded),
        label: const Text('Atualizar'),
      ),
    ];
  }
}
