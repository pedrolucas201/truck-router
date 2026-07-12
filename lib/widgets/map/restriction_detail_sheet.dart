import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user_restriction.dart';
import '../../repositories/restriction_repository.dart';

class RestrictionDetailSheet extends StatefulWidget {
  final UserRestriction restriction;
  const RestrictionDetailSheet({super.key, required this.restriction});

  @override
  State<RestrictionDetailSheet> createState() => RestrictionDetailSheetState();
}

class RestrictionDetailSheetState extends State<RestrictionDetailSheet> {
  bool    _confirming = false;
  bool    _reporting  = false;
  String? _cachedVote; // "confirm" | "report" | null

  static String _voteKey(String id) => 'restriction_vote_$id';

  @override
  void initState() {
    super.initState();
    final id = widget.restriction.id;
    if (id != null) {
      SharedPreferences.getInstance().then((prefs) {
        if (mounted) setState(() => _cachedVote = prefs.getString(_voteKey(id)));
      });
    }
  }

  Future<void> _saveVote(String action) async {
    final id = widget.restriction.id!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voteKey(id), action);
    if (mounted) setState(() => _cachedVote = action);
  }

  String _formatDate(DateTime dt) {
    final d   = dt.day.toString().padLeft(2, '0');
    final m   = dt.month.toString().padLeft(2, '0');
    final h   = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} ${h}h$min';
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    try {
      await context.read<RestrictionRepository>().confirm(widget.restriction.id!);
      await _saveVote('confirm');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmação registrada!'), duration: Duration(seconds: 2)),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _report() async {
    setState(() => _reporting = true);
    try {
      await context.read<RestrictionRepository>().report(widget.restriction.id!);
      await _saveVote('report');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reporte enviado. Obrigado!'), duration: Duration(seconds: 2)),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _reporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restriction;
    final iconData = switch (r.type) {
      'maxheight' => Icons.height,
      'maxweight' => Icons.monitor_weight,
      _           => Icons.swap_horiz,
    };
    final color = switch (r.type) {
      'maxheight' => Colors.red.shade700,
      'maxweight' => Colors.brown.shade600,
      _           => Colors.deepOrange.shade600,
    };
    final busy = _confirming || _reporting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: color, size: 20),
              const SizedBox(width: 8),
              Text('Restrição marcada manualmente',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const Spacer(),
              if (r.isVerified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.verified, size: 13, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text('Verificado', style: TextStyle(fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.w600)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.fullLabel,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(children: [
            Text('Adicionada em ${_formatDate(r.createdAt)}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(width: 12),
            Icon(Icons.thumb_up_outlined, size: 12, color: Colors.grey.shade500),
            const SizedBox(width: 3),
            Text('${r.confirmedBy} ${r.confirmedBy == 1 ? 'confirmação' : 'confirmações'}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ]),
          const Divider(height: 24),
          if (r.id != null) ...[
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _confirm,
                  icon: _confirming
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(_cachedVote == 'confirm' ? Icons.check : Icons.thumb_up, size: 16),
                  label: Text(_cachedVote == 'confirm' ? 'Confirmado' : 'Confirmar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cachedVote == 'confirm' ? Colors.green.shade800 : Colors.green.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _report,
                  icon: _reporting
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade700))
                      : Icon(_cachedVote == 'report' ? Icons.flag : Icons.flag_outlined, size: 16),
                  label: Text(_cachedVote == 'report' ? 'Reportada' : 'Incorreta'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(
                      color: _cachedVote == 'report' ? Colors.orange.shade700 : Colors.orange.shade400,
                      width: _cachedVote == 'report' ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Remover restrição', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }
}
