import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/sos_request.dart';
import '../../screens/driver_profile_screen.dart';
import '../../services/auth_service.dart';
import '../../services/driver_profile_service.dart';
import '../../services/field_log.dart';
import '../../services/sos_push.dart';
import '../../services/sos_service.dart';
import '../../utils/phone_mask.dart';

/// Frase pro motorista por chave de recusa. Uma por falha, sem sistema.
String sosFalhaTexto(SosException e) => switch (e.falha) {
      SosFalha.perfil => 'Preencha nome e telefone no seu perfil pra pedir ajuda.',
      SosFalha.google => 'Entre com o Google no seu perfil pra pedir ajuda.',
      SosFalha.contaNova =>
        'Conta nova: o pedido de ajuda libera 24 h depois de entrar com o Google.',
      SosFalha.jaAberto => 'Você já tem um pedido aberto.',
      SosFalha.expirado => 'Esse pedido já foi atendido ou expirou.',
      SosFalha.semContato => 'Quem pediu não deixou telefone.',
      SosFalha.rede => 'Sem conexão agora. Tente de novo.',
    };

/// Gate local antes de abrir: nome + telefone no perfil. O backend checa de
/// novo; aqui é só pra não mandar o motorista numa viagem de erro.
Future<bool> sosPerfilOk(BuildContext context) async {
  final p = await DriverProfileService.loadLocal();
  final ok = p != null && p.name.isNotEmpty && p.phone.isNotEmpty && AuthService.isGoogleLinked;
  if (ok || !context.mounted) return ok;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('Pra pedir ajuda, entre com o Google e preencha nome e telefone.'),
  ));
  await Navigator.push(
      context, MaterialPageRoute(builder: (_) => const DriverProfileScreen()));
  return false;
}

/// Abrir um S.O.S.: tipo (chips) + texto curto. Devolve (tipo, texto) ou null.
class SosAbrirSheet extends StatefulWidget {
  const SosAbrirSheet({super.key});

  @override
  State<SosAbrirSheet> createState() => _SosAbrirSheetState();
}

class _SosAbrirSheetState extends State<SosAbrirSheet> {
  SosTipo? _tipo;
  final _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.sos, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 10),
            Text('Pedir ajuda', style: Theme.of(context).textTheme.titleLarge),
          ]),
          const SizedBox(height: 4),
          Text('Motoristas num raio de 50 km vão ver seu pedido.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in SosTipo.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _tipo == t,
                  onSelected: (_) => setState(() => _tipo = t),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _texto,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'O que você precisa?',
              hintText: 'Ex: chave 15, estepe furado',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: _tipo == null
                  ? null
                  : () => Navigator.pop(context, (_tipo!, _texto.text.trim())),
              icon: const Icon(Icons.sos),
              label: const Text('Pedir ajuda agora'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ficha de um S.O.S. Dois papéis: quem passa (vê distância, "Vou ajudar",
/// depois telefone + WhatsApp) e o dono (vê quem aceitou, renova, resolve).
/// Placa NÃO aparece (item 7 do Márcio em aberto).
class SosFichaSheet extends StatefulWidget {
  final String sosId;
  final double? distM; // null = dono ou sem posição
  const SosFichaSheet({super.key, required this.sosId, this.distM});

  @override
  State<SosFichaSheet> createState() => _SosFichaSheetState();
}

class _SosFichaSheetState extends State<SosFichaSheet> {
  bool _busy = false;

  Future<void> _whatsapp(String telefone, String texto) async {
    final url = Uri.parse('https://wa.me/55$telefone?text=${Uri.encodeComponent(texto)}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      FieldLog.error('sos_whatsapp', e, st);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on SosException catch (e) {
      _snack(sosFalhaTexto(e));
    } catch (e, st) {
      FieldLog.error('sos_ficha', e, st);
      _snack('Não deu agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = AuthService.currentUid;
    return StreamBuilder<SosRequest?>(
      stream: SosService.streamUm(widget.sosId),
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final dono = s.uid == myUid;
        final souAjudante = s.ajudanteUid == myUid;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.sos, color: Colors.red.shade700, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(dono ? 'Seu pedido de ajuda' : s.nome,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (widget.distM != null)
                  Text(sosDistText(widget.distM!),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
              ]),
              const SizedBox(height: 8),
              if (!dono && s.caminhaoTexto.isNotEmpty)
                Text(s.caminhaoTexto, style: const TextStyle(fontSize: 15)),
              Text('${s.tipo.label}${s.texto.isNotEmpty ? ' · ${s.texto}' : ''}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_statusTexto(s),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              if (!dono) ...[
                const SizedBox(height: 10),
                Text('Ajude só se se sentir seguro. Prefira combinar num posto ou local iluminado.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
              const SizedBox(height: 16),
              if (s.atendendo && (dono || souAjudante))
                _Contato(sosId: s.id, dono: dono, onWhatsapp: _whatsapp),
              const SizedBox(height: 8),
              if (dono) _botoesDono(s) else _botoesPassante(s, souAjudante),
            ],
          ),
        );
      },
    );
  }

  String _statusTexto(SosRequest s) {
    if (s.status == 'resolvido') return 'Resolvido';
    if (!s.ativo) return 'Expirado';
    final min = s.expireAt.difference(DateTime.now()).inMinutes;
    final exp = min >= 60 ? 'expira em ${(min / 60).floor()} h ${min % 60} min' : 'expira em $min min';
    if (s.atendendo) return '${s.ajudanteNome ?? 'Alguém'} vai ajudar · $exp';
    return 'Aberto · $exp';
  }

  Widget _botoesDono(SosRequest s) {
    if (!s.ativo) return const SizedBox.shrink();
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(() => SosService.renovar(s.id)),
          icon: const Icon(Icons.timer),
          label: const Text('Renovar 2 h'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await SosService.resolver(s.id, teveAjuda: s.atendendo);
                    if (mounted) Navigator.pop(context);
                  }),
          icon: const Icon(Icons.check),
          label: const Text('Resolvido'),
        ),
      ),
    ]);
  }

  Widget _botoesPassante(SosRequest s, bool souAjudante) {
    if (souAjudante && s.atendendo) {
      final ir = SosPush.irAteLa;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ir != null)
          FilledButton.icon(
            onPressed: () {
              FieldLog.event('sos_go', {'id': s.id});
              Navigator.pop(context);
              ir(s);
            },
            icon: const Icon(Icons.navigation),
            label: const Text('Ir até lá'),
          ),
        if (ir != null) const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(() => SosService.desistir(s.id)),
          icon: const Icon(Icons.undo),
          label: const Text('Não vou conseguir ajudar'),
        ),
      ]);
    }
    if (!s.aberto || !s.ativo) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
        onPressed: _busy
            ? null
            : () => _run(() async {
                  final ok = await sosPerfilOk(context);
                  if (!ok) return;
                  await SosService.aceitar(s.id,
                      distKm: widget.distM == null ? null : widget.distM! / 1000);
                }),
        icon: const Icon(Icons.handshake),
        label: const Text('Vou ajudar'),
      ),
    );
  }
}

class _Contato extends StatelessWidget {
  final String sosId;
  final bool dono;
  final Future<void> Function(String telefone, String texto) onWhatsapp;
  const _Contato({required this.sosId, required this.dono, required this.onWhatsapp});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, String>?>(
      stream: SosService.streamContato(sosId),
      builder: (context, snap) {
        final c = snap.data;
        if (c == null || c['telefone']!.isEmpty) return const SizedBox.shrink();
        final tel = c['telefone']!;
        final nome = c['nome'] ?? '';
        return Card(
          color: Colors.green.shade50,
          child: ListTile(
            leading: const Icon(Icons.phone, color: Colors.green),
            title: Text(nome.isEmpty ? 'Contato' : nome),
            subtitle: Text(PhoneMaskFormatter.mask(tel)),
            trailing: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
              onPressed: () => onWhatsapp(
                  tel,
                  dono
                      ? 'Oi $nome, sou eu que pedi ajuda no No Trecho.'
                      : 'Oi $nome, vi seu pedido de ajuda no No Trecho. Estou indo.'),
              child: const Text('WhatsApp'),
            ),
          ),
        );
      },
    );
  }
}
