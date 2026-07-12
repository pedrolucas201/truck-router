import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/user_restriction.dart';

Future<BitmapDescriptor> buildPoiIcon(Color color, IconData iconData) async {
  const size = 26.0;
  const iconSize = 13.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    const Offset(size / 2, size / 2),
    size / 2,
    Paint()..color = color,
  );
  canvas.drawCircle(
    const Offset(size / 2, size / 2),
    size / 2 - 2,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  final tp = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: iconSize,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: Colors.white,
      ),
    )
    ..layout();
  tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}

Future<BitmapDescriptor> buildRadarIcon(
    int speedKmh, {bool isLombada = false, bool isPedagio = false}) async {
  const size = 20.0;
  final bgColor = isPedagio
      ? Colors.blue.shade700
      : isLombada
          ? Colors.orange.shade700
          : Colors.red.shade700;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    const Offset(size / 2, size / 2),
    size / 2,
    Paint()..color = bgColor,
  );
  canvas.drawCircle(
    const Offset(size / 2, size / 2),
    size / 2 - 1.5,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  // Só lido no branch else (isPedagio || speedKmh == 0); no caso de texto
  // (speedKmh > 0) nunca é usado.
  final iconData = isPedagio ? Icons.toll : Icons.camera_alt;

  if (!isPedagio && speedKmh > 0) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: speedKmh.toString(),
        style: TextStyle(
          fontSize: speedKmh >= 100 ? 6.0 : 7.5,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
  } else {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 10,
          fontFamily: iconData.fontFamily,
          color: Colors.white,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
  }
  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}

Future<BitmapDescriptor> buildRouteLabelIcon(
    String text, Color bgColor, IconData icon) async {
  const h = 34.0;
  const iconPx = 13.0;
  const fontPx = 11.5;
  const padH = 9.0;
  const gap = 4.0;

  final iconTp = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: iconPx,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    )
    ..layout();

  final textTp = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: fontPx,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    )
    ..layout();

  final w = padH + iconTp.width + gap + textTp.width + padH;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final rRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, w, h),
    const Radius.circular(h / 2),
  );
  canvas.drawRRect(rRect, Paint()..color = bgColor);
  canvas.drawRRect(
    rRect,
    Paint()
      ..color = Colors.white.withAlpha(180)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  iconTp.paint(canvas, Offset(padH, (h - iconTp.height) / 2));
  textTp.paint(canvas, Offset(padH + iconTp.width + gap, (h - textTp.height) / 2));

  final picture = recorder.endRecording();
  final img = await picture.toImage(w.ceil(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}

Future<BitmapDescriptor> buildRestrictionIcon(UserRestriction r) async {
  const iconH = 20.0;
  final bgColor = switch (r.type) {
    'maxheight' => Colors.red.shade700,
    'maxweight' => Colors.brown.shade600,
    'dirtroad'  => Colors.green.shade700,
    'truck_ban' => Colors.red.shade900,
    _           => Colors.deepOrange.shade600,
  };
  final text = switch (r.type) {
    'maxheight' => '${r.value.toStringAsFixed(1)}m',
    'maxweight' => '${r.value.toStringAsFixed(0)}t',
    'dirtroad'  => 'Terra',
    'truck_ban' => 'Proib.',
    _           => '${r.value.toStringAsFixed(1)}m',
  };
  final tp = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: text,
      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
    )
    ..layout();
  final iconW = (tp.width + 14).ceilToDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rrect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, iconW, iconH),
    const Radius.circular(4),
  );
  canvas.drawRRect(rrect, Paint()..color = bgColor);
  if (r.isVerified) {
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.amber.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
  tp.paint(canvas, Offset(7, (iconH - tp.height) / 2));
  final picture = recorder.endRecording();
  final img = await picture.toImage(iconW.toInt(), iconH.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}
