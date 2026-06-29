import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/here_geocoding_service.dart';
import '../services/places_service.dart';

class AddressSearchField extends StatefulWidget {
  final String hint;
  final String? initialValue;
  final Color? indicatorColor;
  final LatLng? biasLocation;
  final ValueChanged<(String label, LatLng position)> onSelected;

  const AddressSearchField({
    super.key,
    required this.hint,
    this.initialValue,
    this.indicatorColor,
    this.biasLocation,
    required this.onSelected,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<GeocodingSuggestion> _suggestions = [];
  List<(String, LatLng)> _places = []; // lugares já usados (recente primeiro)
  bool _loading = false;
  bool _confirmed = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
      _confirmed = true;
    }
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
    PlacesService.all().then((p) {
      if (mounted) setState(() => _places = p);
    });
  }

  Future<void> _search(String query) async {
    setState(() => _confirmed = false);
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _loading = true);
    final results = await HereGeocodingService.search(
        query, bias: widget.biasLocation);
    if (mounted) {
      setState(() {
        _suggestions = results;
        _loading = false;
      });
    }
  }

  // Grava o lugar escolhido na memória local e reflete no estado do campo.
  void _remember(String label, LatLng pos) {
    PlacesService.record(label, pos);
    _places = [
      (label, pos),
      ..._places.where((p) => p.$1.toLowerCase() != label.toLowerCase()),
    ];
  }

  Future<void> _select(GeocodingSuggestion s) async {
    _controller.text = s.title;

    // Resultado de lugar nomeado já tem coords — usa direto, sem lookup.
    if (!s.needsLookup) {
      _remember(s.title, s.position!);
      setState(() { _suggestions = []; _confirmed = true; });
      _focusNode.unfocus();
      widget.onSelected((s.title, s.position!));
      return;
    }

    // Resultado de endereço — precisa de lookup para coords precisas.
    setState(() { _suggestions = []; _loading = true; _confirmed = false; });
    final position = await HereGeocodingService.lookup(s.hereId!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (position != null) {
      _remember(s.title, position);
      setState(() => _confirmed = true);
      _focusNode.unfocus();
      widget.onSelected((s.title, position));
    }
  }

  // Tocou num lugar já conhecido (recente ou match local): usa direto.
  void _selectKnown((String, LatLng) place) {
    _controller.text = place.$1;
    _remember(place.$1, place.$2);
    setState(() { _suggestions = []; _confirmed = true; });
    _focusNode.unfocus();
    widget.onSelected(place);
  }

  Future<void> _submitFirst() async {
    if (_suggestions.isNotEmpty) {
      await _select(_suggestions.first);
      return;
    }
    final query = _controller.text.trim();
    if (query.length < 3) return;
    setState(() => _loading = true);
    final results = await HereGeocodingService.search(
        query, bias: widget.biasLocation);
    if (mounted) {
      setState(() => _loading = false);
      if (results.isNotEmpty) await _select(results.first);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.5),
            ),
            prefixIcon: widget.indicatorColor != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.indicatorColor,
                      ),
                    ),
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _confirmed
                    ? const Icon(Icons.check_circle,
                        color: Color(0xFF00897B), size: 18)
                    : null,
          ),
          onChanged: _search,
          onSubmitted: (_) => _submitFirst(),
        ),
        _buildDropdown(context),
      ],
    );
  }

  Widget _buildDropdown(BuildContext context) {
    final q = _controller.text.trim().toLowerCase();
    // Lugares conhecidos: campo vazio+focado → recentes; digitando → match local.
    final List<(String, LatLng)> known = q.isEmpty
        ? (_focused ? _places.take(5).toList() : const [])
        : _places.where((p) => p.$1.toLowerCase().contains(q)).take(5).toList();
    // Geocoding sem repetir o que já apareceu como conhecido (dedup por label).
    final geo = _suggestions
        .where((s) => !known.any((k) => k.$1.toLowerCase() == s.title.toLowerCase()))
        .toList();

    if (known.isEmpty && geo.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final k in known)
            ListTile(
              dense: true,
              leading: Icon(Icons.history, size: 18, color: Colors.grey.shade500),
              title: Text(k.$1, style: const TextStyle(fontSize: 13)),
              onTap: () => _selectKnown(k),
            ),
          if (known.isNotEmpty && geo.isNotEmpty) const Divider(height: 1),
          for (final s in geo)
            ListTile(
              dense: true,
              leading: Icon(
                s.needsLookup ? Icons.location_on_outlined : Icons.place,
                size: 18,
                color: s.needsLookup ? null : Theme.of(context).colorScheme.primary,
              ),
              title: Text(s.title, style: const TextStyle(fontSize: 13)),
              onTap: () => _select(s),
            ),
        ],
      ),
    );
  }
}
