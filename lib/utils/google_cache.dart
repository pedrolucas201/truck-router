/// Google Maps Platform, Service Specific Terms 6.3.1 (texto lido em
/// 2026-09-09): lat/lng da Geocoding API podem ficar em cache por até 30 dias
/// consecutivos e depois TÊM de ser apagados. O rótulo gravado junto é o texto
/// que o motorista digitou (dado dele), nunca o formatted_address da Google.
/// A 6.3.2 (sem prazo) exige que o cache não substitua uma chamada nova, e
/// recentes/histórico existem exatamente pra isso — por isso vale a 6.3.1.
library;

const kGoogleCacheTtl = Duration(days: 30);

/// `at` = quando a Google entregou a coordenada (não quando foi reutilizada).
bool googleCacheExpired(DateTime at, DateTime now) =>
    now.difference(at) > kGoogleCacheTtl;
