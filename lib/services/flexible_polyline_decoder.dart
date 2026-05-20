import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// HERE Flexible Polyline decoder.
// Uses pure arithmetic (no bitwise ops) to avoid dart2js unsigned-32 behavior
// where ~x returns the unsigned representation instead of the signed complement.
class FlexiblePolylineDecoder {
  static const String _table =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static List<LatLng> decode(String encoded) {
    int i = 0;

    int readUnsigned() {
      int result = 0;
      int multiplier = 1;
      while (i < encoded.length) {
        final b = _table.indexOf(encoded[i++]);
        result += (b % 32) * multiplier; // arithmetic: avoids << and |
        multiplier *= 32;
        if (b < 32) break; // no continuation bit
      }
      return result;
    }

    int readSigned() {
      final v = readUnsigned();
      final half = v ~/ 2; // arithmetic: avoids >>
      return v.isOdd ? -(half + 1) : half; // zigzag decode: avoids ~
    }

    readUnsigned(); // version — ignored
    final header = readUnsigned();
    final precision = header % 16;       // header & 0x0F
    final thirdDim = (header ~/ 16) % 8; // (header >> 4) & 0x07
    final divisor = pow(10, precision).toInt();

    final points = <LatLng>[];
    int lastLat = 0;
    int lastLng = 0;

    while (i < encoded.length) {
      lastLat += readSigned();
      lastLng += readSigned();
      if (thirdDim != 0) readSigned(); // consume altitude if present
      points.add(LatLng(lastLat / divisor, lastLng / divisor));
    }

    return points;
  }
}
