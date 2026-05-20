import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/here_geocoding_service.dart';

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
  List<GeocodingSuggestion> _suggestions = [];
  bool _loading = false;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
      _confirmed = true;
    }
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

  Future<void> _select(GeocodingSuggestion s) async {
    _controller.text = s.title;

    // Resultado de lugar nomeado já tem coords — usa direto, sem lookup.
    if (!s.needsLookup) {
      setState(() { _suggestions = []; _confirmed = true; });
      widget.onSelected((s.title, s.position!));
      return;
    }

    // Resultado de endereço — precisa de lookup para coords precisas.
    setState(() { _suggestions = []; _loading = true; _confirmed = false; });
    final position = await HereGeocodingService.lookup(s.hereId!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (position != null) {
      setState(() => _confirmed = true);
      widget.onSelected((s.title, position));
    }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
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
        if (_suggestions.isNotEmpty)
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    s.needsLookup
                        ? Icons.location_on_outlined
                        : Icons.place,
                    size: 18,
                    color: s.needsLookup
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(s.title, style: const TextStyle(fontSize: 13)),
                  onTap: () => _select(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
