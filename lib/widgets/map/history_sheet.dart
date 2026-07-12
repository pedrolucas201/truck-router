import 'package:flutter/material.dart';

import '../../models/route_history.dart';
import '../../services/favorites_service.dart';

class HistorySheet extends StatefulWidget {
  final List<RouteHistory> history;
  final List<RouteHistory> favorites;
  final ValueChanged<RouteHistory> onSelect;
  final ValueChanged<int> onDelete;
  final ValueChanged<RouteHistory> onFavorite;   // h já com .name
  final ValueChanged<RouteHistory> onUnfavorite;

  const HistorySheet({
    super.key,
    required this.history,
    required this.favorites,
    required this.onSelect,
    required this.onDelete,
    required this.onFavorite,
    required this.onUnfavorite,
  });

  @override
  State<HistorySheet> createState() => HistorySheetState();
}

class HistorySheetState extends State<HistorySheet> {
  late final List<RouteHistory> _items = List.of(widget.history);
  late final List<RouteHistory> _favs = List.of(widget.favorites);
  late final Set<String> _favKeys = _favs.map(FavoritesService.keyOf).toSet();

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}h'
      '${dt.minute.toString().padLeft(2, '0')}';

  String _routeText(RouteHistory h) => '${h.originLabel} → ${h.destinationLabel}';

  Future<void> _addFavorite(RouteHistory h) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Salvar rota'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nome (opcional)',
              hintText: 'ex: Casa → Obra',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    if (name == null || !mounted) return; // cancelou
    final fav = h.copyWith(name: name.isEmpty ? null : name);
    setState(() {
      _favKeys.add(FavoritesService.keyOf(fav));
      _favs.insert(0, fav);
    });
    widget.onFavorite(fav);
  }

  void _removeFavorite(RouteHistory h) {
    final k = FavoritesService.keyOf(h);
    setState(() {
      _favKeys.remove(k);
      _favs.removeWhere((e) => FavoritesService.keyOf(e) == k);
    });
    widget.onUnfavorite(h);
  }

  @override
  Widget build(BuildContext context) {
    // Recentes = histórico que NÃO está favoritado (favorita já aparece no topo).
    final recents = <(int, RouteHistory)>[
      for (var i = 0; i < _items.length; i++)
        if (!_favKeys.contains(FavoritesService.keyOf(_items[i]))) (i, _items[i]),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Rotas', style: Theme.of(context).textTheme.titleMedium),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              if (_favs.isNotEmpty) ...[
                _sectionLabel(context, 'Favoritas'),
                for (final h in _favs)
                  ListTile(
                    leading: Icon(Icons.star, size: 20, color: Colors.amber.shade700),
                    title: Text(
                      h.name?.isNotEmpty == true ? h.name! : _routeText(h),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      h.name?.isNotEmpty == true
                          ? _routeText(h)
                          : '${h.distanceText}  •  ${h.durationText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.star, size: 20, color: Colors.amber.shade700),
                      tooltip: 'Remover dos favoritos',
                      onPressed: () => _removeFavorite(h),
                    ),
                    onTap: () => widget.onSelect(h),
                  ),
              ],
              if (recents.isNotEmpty) _sectionLabel(context, 'Recentes'),
              for (final (i, h) in recents)
                ListTile(
                  leading: const Icon(Icons.route, size: 20),
                  title: Text(
                    _routeText(h),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${h.distanceText}  •  ${h.durationText}  •  ${_formatDate(h.calculatedAt)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.star_border, size: 20),
                        tooltip: 'Favoritar',
                        onPressed: () => _addFavorite(h),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          widget.onDelete(i);
                          setState(() => _items.removeAt(i));
                        },
                      ),
                    ],
                  ),
                  onTap: () => widget.onSelect(h),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 0.5),
        ),
      );
}
