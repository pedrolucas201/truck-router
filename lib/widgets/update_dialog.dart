import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../services/update_service.dart';

/// Diálogo de atualização in-app. Mostra as novidades, baixa a APK do GCS via
/// ota_update com barra de progresso e dispara o instalador do sistema.
/// Se info.force, não dá pra fechar (versão abaixo do mínimo suportado).
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
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
  double? _progress; // null = ainda não começou; 0-100 = baixando
  bool _installing = false;
  String? _error;

  bool get _busy => _progress != null && !_installing && _error == null;

  void _start() {
    setState(() {
      _progress = 0;
      _error = null;
      _installing = false;
    });
    try {
      OtaUpdate()
          .execute(widget.info.url, destinationFilename: 'truck-router.apk')
          .listen(
        (OtaEvent event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              setState(() => _progress = double.tryParse(event.value ?? '') ?? _progress);
              break;
            case OtaStatus.INSTALLING:
              // O instalador do sistema assumiu — o app pode ser substituído a
              // qualquer momento daqui pra frente.
              setState(() => _installing = true);
              break;
            case OtaStatus.INSTALLATION_DONE:
              // Instalado com sucesso — fecha o diálogo (o app já é o novo ou
              // será na próxima abertura).
              Navigator.of(context).maybePop();
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() => _error =
                  'Permita "instalar apps desconhecidos" para o Rota Caminhão e tente de novo.');
              break;
            case OtaStatus.CANCELED:
              // Usuário cancelou — volta pro estado inicial (Depois/Atualizar).
              setState(() => _progress = null);
              break;
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
            case OtaStatus.ALREADY_RUNNING_ERROR:
            case OtaStatus.INSTALLATION_ERROR:
              setState(() => _error =
                  'Não consegui baixar a atualização. Verifique a internet e tente de novo.');
              break;
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _error =
                'Não consegui baixar a atualização. Verifique a internet e tente de novo.');
          }
        },
      );
    } catch (_) {
      setState(() => _error =
          'Não consegui iniciar a atualização. Tente de novo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return PopScope(
      // Bloqueia o "voltar" só durante download ativo (e sempre no force).
      canPop: !info.force && !_busy,
      child: AlertDialog(
        title: Text('Atualização disponível${info.version.isNotEmpty ? ' (${info.version})' : ''}'),
        content: _content(),
        actions: _actions(),
      ),
    );
  }

  Widget _content() {
    if (_error != null) {
      return Text(_error!);
    }
    if (_installing) {
      return const Text('Baixado. Abrindo o instalador…');
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
    final notes = widget.info.notes;
    return Text(notes.isNotEmpty ? notes : 'Uma nova versão do app está disponível.');
  }

  List<Widget> _actions() {
    if (_busy) return const []; // baixando: sem botões
    if (_installing) return const [];

    if (_error != null) {
      return [
        if (!widget.info.force)
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        FilledButton(onPressed: _start, child: const Text('Tentar de novo')),
      ];
    }

    return [
      if (!widget.info.force)
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Depois')),
      FilledButton(onPressed: _start, child: const Text('Atualizar')),
    ];
  }
}
