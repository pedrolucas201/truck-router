import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/poi.dart';

/// Balanças (postos de pesagem) do DNIT, do asset offline.
///
/// O app já avisava balança na rota — badge de próximo evento, ícone no mapa,
/// filtro por proximidade —, só que em cima de **três pontos inventados** que
/// viviam em `lib/data/pois.dart` marcados como "hardcoded para teste". Eles não
/// ficaram no teste: chegavam ao motorista pelo mapa e eram anunciados até 20 km
/// à frente. Passar direto por balança dá multa, então dado chutado aqui é do
/// tipo que custa caro — e três pontos não cobriam quase nada do país.
///
/// Agora vêm do dataset `pesagem` do DNIT (mesmo portal do PNCV que alimenta os
/// radares), gerados por `tools/balancas_dnit_gerar.py`.
class ScaleService {
  static List<Poi>? _cache;

  /// O que já está em memória — o mapa monta marcadores de forma síncrona.
  /// Vazio antes do [load], e isso é aceitável: um frame sem balança é melhor
  /// que segurar o mapa esperando I/O.
  static List<Poi> get all => _cache ?? const [];

  static Future<List<Poi>> load() async {
    if (_cache != null) return _cache!;
    _cache = parseCsv(await rootBundle.loadString('assets/balancas.csv'));
    return _cache!;
  }

  /// `longitude,latitude,nome,descricao,status,sentido`.
  ///
  /// `status` e `sentido` entram no CSV como metadado de auditoria e NÃO filtram
  /// nada aqui: "Paralisada" é estado do equipamento, não garantia de que não há
  /// fiscalização no local — o mesmo raciocínio que impediu de silenciar radar
  /// oficialmente desativado. Balança some do mapa só quando sai da fonte.
  @visibleForTesting
  static List<Poi> parseCsv(String csv) {
    final out = <Poi>[];
    for (final line in csv.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final c = l.split(',');
      if (c.length < 4) continue;
      final lng = double.tryParse(c[0]);
      final lat = double.tryParse(c[1]);
      if (lng == null || lat == null) continue; // header ou linha inválida
      out.add(Poi(
        name: c[2],
        category: PoiCategory.scale,
        position: LatLng(lat, lng),
        description: c[3],
      ));
    }
    return out;
  }
}
