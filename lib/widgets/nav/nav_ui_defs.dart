import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/radar_point.dart';

enum AudioLevel { completo, essencial, silencioso }

enum ZoomLevel { recuado, medio, aproximado }

// Teto de velocidade de caminhão em rodovia (CTB): o app é SÓ pra caminhão, então
// nunca mostra/avisa acima disso, mesmo quando a placa/HERE traz o limite de CARRO
// (ex: 110 na Dom Pedro). ponytail: knob de calibração — se alguma classe de via
// pedir teto menor, dá pra parametrizar por tipo de via depois.
const int kTruckCapKmh = 90;

// Radar MÓVEL (ponto de fiscalização com radar portátil): mesma família visual
// do radar, cor e glifo próprios pra não passar por câmera fixa.
const Color kMovelColor = Color(0xFF512DA8); // deepPurple.shade700
const IconData kMovelIcon = Icons.local_police;

// Limite de caminhão NA ÁREA DE UM RADAR = a velocidade POSTADA no radar (a
// "velocidade permitida" que o Gilberto cura), capada no teto de caminhão. NÃO
// usa mais o limite do trecho da HERE: ele crava valores errados (40 numa via de
// 90) e fazia o flash piscar em velocidade legal do lado de um radar de 90
// (report Gilberto 2026-07-09, com print). Ainda protege contra placa de carro
// (110 → cap 90, report 2026-07-03). null quando o radar não tem velocidade
// postada (aí o chamador mostra "Radar" e usa o teto).
// [officialTruckLimit] (opcional) = limite de caminhão de fonte OFICIAL
// (ANTT/DNIT, campo truckLimitOff do RadarPoint). Regra: só ABAIXA, nunca sobe —
// mesma assimetria (errar pra menos = multa). Ausente => comportamento antigo intacto.
int? truckRadarLimit(int radarSpeedKmh, {int? officialTruckLimit}) {
  int? limit = radarSpeedKmh <= 0 ? null : min(radarSpeedKmh, kTruckCapKmh);
  if (officialTruckLimit != null && officialTruckLimit > 0) {
    final off = min(officialTruckLimit, kTruckCapKmh);
    limit = limit == null ? off : min(limit, off);
  }
  return limit;
}

/// O número de radar que o motorista OBEDECE — o mesmo em ícone, balão, chip,
/// velocímetro e voz. Antes cada consumidor escolhia: a barra usava o limite de
/// caminhão e o ícone/voz a placa crua (110/100/120 de carro) — 1.414 radares
/// do asset com dois números na mesma tela (print do Gilberto na Castelo,
/// 2026-09-02). Curadoria continua mostrando a placa crua de propósito.
extension RadarTruckKmh on RadarPoint {
  int? get truckKmh =>
      truckRadarLimit(speedKmh, officialTruckLimit: truckLimitOff);
}
