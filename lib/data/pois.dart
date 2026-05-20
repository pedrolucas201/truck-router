import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/poi.dart';

// POIs hardcoded para teste — mix de compatíveis e incompatíveis com o perfil default
// (420cm alt / 1400cm comp / 25.000kg) para validar o filtro visual.
const List<Poi> kHardcodedPois = [
  // ── Postos de Combustível ──────────────────────────────────────────────────
  Poi(
    name: 'Posto TRR Dutra',
    category: PoiCategory.fuel,
    position: LatLng(-23.2973, -45.9657),
    description: 'BR-116 km 210 — Jacareí/SP',
    maxHeightCm: 550,
    hasDiesel: true,
  ),
  Poi(
    // maxHeightCm 380 < 420 default → incompatível para demonstrar filtro
    name: 'Posto Petrobras Itajaí',
    category: PoiCategory.fuel,
    position: LatLng(-26.9101, -48.6639),
    description: 'BR-101 km 180 — Itajaí/SC · teto baixo (3,80m)',
    maxHeightCm: 380,
    hasDiesel: true,
  ),
  Poi(
    name: 'Posto BR Vibra Congonhas',
    category: PoiCategory.fuel,
    position: LatLng(-20.4983, -43.8575),
    description: 'BR-040 km 650 — Congonhas/MG',
    maxHeightCm: 500,
    hasDiesel: true,
  ),

  // ── Balanças DNIT ──────────────────────────────────────────────────────────
  Poi(
    name: 'Balança DNIT Guarulhos',
    category: PoiCategory.scale,
    position: LatLng(-23.4543, -46.5333),
    description: 'BR-116 km 140 — Guarulhos/SP',
  ),
  Poi(
    name: 'Balança DNIT Uberlândia',
    category: PoiCategory.scale,
    position: LatLng(-18.9183, -48.2768),
    description: 'BR-050 km 320 — Uberlândia/MG',
  ),
  Poi(
    name: 'Balança DNIT Florianópolis',
    category: PoiCategory.scale,
    position: LatLng(-27.5946, -48.5477),
    description: 'BR-101 km 430 — Florianópolis/SC',
  ),

  // ── Áreas de Descanso ─────────────────────────────────────────────────────
  Poi(
    name: 'Área de Repouso Dutra',
    category: PoiCategory.restArea,
    position: LatLng(-23.1794, -45.8837),
    description: 'BR-116 km 170 — São José dos Campos/SP',
    maxLengthCm: 2000,
  ),
  Poi(
    // maxLengthCm 1200 < 1400 default → incompatível para demonstrar filtro
    name: 'Área de Repouso Barbacena',
    category: PoiCategory.restArea,
    position: LatLng(-21.2264, -43.7736),
    description: 'BR-040 km 700 — Barbacena/MG · vagas até 12m',
    maxLengthCm: 1200,
  ),
  Poi(
    name: 'Área de Repouso Ribeirão Preto',
    category: PoiCategory.restArea,
    position: LatLng(-21.1783, -47.8064),
    description: 'BR-050 km 280 — Ribeirão Preto/SP',
    maxLengthCm: 1800,
  ),
];
