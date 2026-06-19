import 'dart:math';

import 'package:flutter/foundation.dart';
import '../models/truck_profile.dart';

enum TruckGlyph { bau, carreta }

const int kCarretaLengthCm = 1000;

TruckGlyph glyphForProfile(TruckProfile profile) =>
    profile.lengthCm >= kCarretaLengthCm ? TruckGlyph.carreta : TruckGlyph.bau;

String assetFor(TruckGlyph glyph) => switch (glyph) {
      TruckGlyph.bau => 'assets/loader/truck_bau.svg',
      TruckGlyph.carreta => 'assets/loader/truck_carreta.svg',
    };

const List<String> kLoaderAssets = [
  'assets/loader/truck_bau.svg',
  'assets/loader/truck_carreta.svg',
  'assets/loader/bus.svg',
  'assets/loader/minibus.svg',
  'assets/loader/tractor.svg',
];

String? _lastLoaderAsset;

String randomLoaderAsset() {
  final pool = _lastLoaderAsset == null
      ? kLoaderAssets
      : kLoaderAssets.where((a) => a != _lastLoaderAsset).toList();
  final asset = pool[Random().nextInt(pool.length)];
  _lastLoaderAsset = asset;
  return asset;
}

@visibleForTesting
void resetLoaderHistory() => _lastLoaderAsset = null;
