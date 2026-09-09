import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/field_log.dart';
import '../services/here_geocoding_service.dart';
import '../services/places_service.dart';

class AddressSearchField extends StatefulWidget {
  final String hint;
  final String? initialValue;
  final Color? indicatorColor;
  final LatLng? biasLocation;
  // Separa o histórico por campo (ex: 'origin' vs 'destination') — partida e
  // destino têm memórias diferentes.
  final String historyRole;
  // `google` = coordenada da Google: quem guardar tem que marcar a entrada
  // pra ela expirar em 30 dias (utils/google_cache.dart). O label já vem
  // como o texto digitado, nunca o formatted_address.
  final ValueChanged<(String label, LatLng position, bool google)> onSelected;

  const AddressSearchField({
    super.key,
    required this.hint,
    this.initialValue,
    this.indicatorColor,
    this.biasLocation,
    this.historyRole = 'destination',
    required this.onSelected,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<GeocodingSuggestion> _suggestions = [];
  List<(String, LatLng, bool)> _places = []; // lugares já usados (recente primeiro); $3 = Google
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
    PlacesService.all(widget.historyRole).then((p) {
      if (mounted) setState(() => _places = p);
    });
  }

  // Sem debounce cada TECLA disparava as 3 fontes de geocoding em paralelo:
  // digitar "rua guaianases, 1448" custava ~54 chamadas pra um endereço só.
  // Também é o que segura o Nominatim dentro da política de 1 req/s dele — o
  // debounce só dispara na PAUSA, então digitação contínua não gera chamada
  // nenhuma. Ver HereGeocodingService.houseNumberOf.
  Timer? _debounce;

  void _onChanged(String query) {
    _debounce?.cancel();
    // Limpar campo e marca de confirmado é imediato: esperar 400 ms deixaria o
    // check verde aceso sobre um texto que ele já apagou.
    setState(() => _confirmed = false);
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
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
  // `fresh` = a coordenada acabou de vir da Google (prazo novo); recente
  // re-escolhido não renova — o record preserva marca e data originais.
  void _remember(String label, LatLng pos, {bool google = false, bool fresh = true}) {
    PlacesService.record(widget.historyRole, label, pos, google: google && fresh);
    _places = [
      (label, pos, google),
      ..._places.where((p) => p.$1.toLowerCase() != label.toLowerCase()),
    ];
  }

  Future<void> _select(GeocodingSuggestion s) async {
    // Rótulo gravado/propagado: pra Google é o texto DIGITADO (dado do
    // motorista) — o formatted_address dela não pode ser guardado (o termo
    // 6.3.1 só cobre lat/lng). O campo em si ainda mostra o endereço dela.
    final label = s.fromGoogle ? _controller.text.trim() : s.title;
    // Fecha o par com o geocode_search: qual posição/fonte o motorista tocou.
    // src vazio = caminho do CEP.
    FieldLog.event('geocode_pick', {
      'i':   _suggestions.indexOf(s),
      'src': s.source,
      'km':  s.distanceM == null ? '' : (s.distanceM! / 1000).round(),
    });
    _controller.text = s.title;

    // Resultado de lugar nomeado já tem coords — usa direto, sem lookup.
    if (!s.needsLookup) {
      _remember(label, s.position!, google: s.fromGoogle);
      setState(() { _suggestions = []; _confirmed = true; });
      _focusNode.unfocus();
      widget.onSelected((label, s.position!, s.fromGoogle));
      return;
    }

    // Resultado de endereço — precisa de lookup para coords precisas.
    setState(() { _suggestions = []; _loading = true; _confirmed = false; });
    final position = await HereGeocodingService.lookup(s.hereId!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (position != null) {
      _remember(s.title, position); // lookup é sempre HERE, nunca Google
      setState(() => _confirmed = true);
      _focusNode.unfocus();
      widget.onSelected((s.title, position, false));
    }
  }

  // Tocou num lugar já conhecido (recente ou match local): usa direto.
  void _selectKnown((String, LatLng, bool) place) {
    FieldLog.event('geocode_pick', {'i': -1, 'src': 'history'});
    _controller.text = place.$1;
    _remember(place.$1, place.$2, google: place.$3, fresh: false);
    setState(() { _suggestions = []; _confirmed = true; });
    _focusNode.unfocus();
    widget.onSelected(place);
  }

  Future<void> _submitFirst() async {
    _debounce?.cancel(); // ele já decidiu; busca atrasada só sobrescreveria a lista
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
    _debounce?.cancel();
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
          onChanged: _onChanged,
          onSubmitted: (_) => _submitFirst(),
        ),
        _buildDropdown(context),
      ],
    );
  }

  Widget _buildDropdown(BuildContext context) {
    // Já confirmado: o texto do campo é o próprio lugar selecionado e daria
    // match em si mesmo na lista de conhecidos. Nada a sugerir.
    if (_confirmed) return const SizedBox.shrink();
    final q = _controller.text.trim().toLowerCase();
    // Lugares conhecidos: campo vazio+focado → recentes; digitando → match local.
    final List<(String, LatLng, bool)> known = q.isEmpty
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
