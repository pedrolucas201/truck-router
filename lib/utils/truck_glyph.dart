import '../models/truck_profile.dart';

enum TruckGlyph { bau, carreta }

/// Comprimento (cm) a partir do qual o perfil usa a carreta. Limiar calibrável;
/// o default do app (1400 cm) cai em carreta.
const int kCarretaLengthCm = 1000;

/// Escolhe o glifo do loader pelo porte do perfil. Determinístico, sem null.
TruckGlyph glyphForProfile(TruckProfile profile) =>
    profile.lengthCm >= kCarretaLengthCm ? TruckGlyph.carreta : TruckGlyph.bau;

/// Caminho do asset SVG para cada glifo.
String assetFor(TruckGlyph glyph) => switch (glyph) {
      TruckGlyph.bau => 'assets/loader/truck_bau.svg',
      TruckGlyph.carreta => 'assets/loader/truck_carreta.svg',
    };
