# Truck Router v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement three independent features: (1) novos tipos de restrição + alertas de polícia efêmeros, (2) cache no proxy de roteamento Go, (3) compartilhar rota pelo WhatsApp.

**Architecture:** Fase 1 é Flutter+Firestore. Fase 2 é Go backend only (proxy já existe, só adiciona cache). Fase 3 é Flutter only. Cada fase é um PR independente.

**Tech Stack:** Flutter 3.10.7 / Dart, Go 1.25, Firestore, Cloud Run (GCP projeto maps-route-495614), chi router, share_plus (já no pubspec), app_links (já no pubspec).

**Pré-condição importante:** O proxy de roteamento já existe (`GET /route/here` no backend). A chave HERE já está no Secret Manager. O que Fase 2 adiciona é apenas cache em memória.

---

## Mapa de arquivos

**Fase 1 — cria:**
- `lib/models/police_alert.dart`
- `lib/services/police_alert_service.dart`

**Fase 1 — modifica:**
- `lib/models/user_restriction.dart` — `fullLabel` para `truck_ban`
- `lib/models/bridge_restriction.dart` — `label`, `conflictsWith` para `truck_ban`
- `lib/widgets/add_restriction_sheet.dart` — chip truck_ban
- `lib/screens/map_screen.dart` — isVerified bottom sheet + police pins + share button
- `lib/screens/navigation_screen.dart` — banner proximidade polícia

**Fase 2 — cria:**
- `backend/internal/cache/cache.go`

**Fase 2 — modifica:**
- `backend/internal/handlers/proxy.go` — `forwardWithCache` + `fetchBody`
- `backend/internal/handlers/route.go` — `RouteHandlers` struct com cache
- `backend/cmd/server/main.go` — instancia `RouteHandlers`

**Fase 3 — modifica:**
- `lib/utils/geo_uri_parser.dart` — suporte `maps.google.com?saddr=&daddr=`
- `lib/screens/map_screen.dart` — share button + deep link com origem
- `android/app/src/main/AndroidManifest.xml` — intent filter `maps.google.com`

---

## FASE 1 — Restrições + Alertas de polícia

---

### Task 1: tipo truck_ban nas restrições permanentes

**Files:**
- Modify: `lib/models/user_restriction.dart`
- Modify: `lib/models/bridge_restriction.dart`
- Modify: `lib/widgets/add_restriction_sheet.dart`
- Test: `test/models/restriction_test.dart`

- [ ] **Step 1: Escrever testes**

```dart
// test/models/restriction_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/user_restriction.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/models/truck_profile.dart';

void main() {
  group('truck_ban type', () {
    test('UserRestriction.fullLabel retorna texto correto para truck_ban', () {
      final r = UserRestriction(
        lat: 0, lng: 0, type: 'truck_ban', value: 0,
        createdAt: DateTime.now(),
      );
      expect(r.fullLabel, 'Proibido caminhões');
    });

    test('BridgeRestriction.label retorna texto correto para truck_ban', () {
      const r = BridgeRestriction(lat: 0, lng: 0, type: 'truck_ban', value: 0);
      expect(r.label, 'Proibido caminhões');
    });

    test('BridgeRestriction.conflictsWith retorna true para truck_ban', () {
      const r = BridgeRestriction(lat: 0, lng: 0, type: 'truck_ban', value: 0);
      const truck = TruckProfile(heightCm: 420, lengthCm: 1400, widthCm: 260, weightKg: 25000);
      expect(r.conflictsWith(truck), isTrue);
    });
  });
}
```

- [ ] **Step 2: Rodar e verificar que falha**

```
cd truck_router
flutter test test/models/restriction_test.dart
```
Esperado: FAIL — truck_ban não reconhecido nos switch cases.

- [ ] **Step 3: Atualizar `user_restriction.dart`**

No `fullLabel` getter, adicionar caso antes do `_`:
```dart
'truck_ban' => 'Proibido caminhões',
```

- [ ] **Step 4: Atualizar `bridge_restriction.dart`**

No `label` getter, adicionar caso:
```dart
'truck_ban' => 'Proibido caminhões',
```

No `conflictsWith` getter, adicionar caso:
```dart
'truck_ban' => true,
```

- [ ] **Step 5: Adicionar chip no `add_restriction_sheet.dart`**

Em `_AddRestrictionSheetState`:

Adicionar ao getter `_needsValue`:
```dart
bool get _needsValue => _type != 'dirtroad' && _type != 'truck_ban';
```

Adicionar chip após o chip de `dirtroad` dentro do `Wrap`:
```dart
RestrictionTypeChip(
  label: 'Proibido caminhão',
  icon: Icons.no_crash,
  selected: _type == 'truck_ban',
  onTap: () => setState(() => _type = 'truck_ban'),
),
```

- [ ] **Step 6: Atualizar `_buildRestrictionIcon` em `map_screen.dart`**

No `bgColor` switch, adicionar antes do `_`:
```dart
'truck_ban' => Colors.red.shade900,
```

No `text` switch, adicionar antes do `_`:
```dart
'truck_ban' => 'Proib.',
```

- [ ] **Step 7: Rodar testes e lint**

```
flutter test test/models/restriction_test.dart
flutter analyze
```
Esperado: PASS, zero issues.

- [ ] **Step 8: Commit**

```bash
git add lib/models/user_restriction.dart lib/models/bridge_restriction.dart \
        lib/widgets/add_restriction_sheet.dart lib/screens/map_screen.dart \
        test/models/restriction_test.dart
git commit -m "feat(restrictions): adiciona tipo truck_ban"
```

---

### Task 2: "Verificado" no bottom sheet de detalhes

**Files:**
- Modify: `lib/screens/map_screen.dart` (classe `_RestrictionDetailSheet`)

> O pin já tem borda dourada quando `isVerified`. Esta task adiciona o label textual no sheet.

- [ ] **Step 1: Localizar `_RestrictionDetailSheet` em `map_screen.dart`**

Buscar a classe `_RestrictionDetailSheet`. Encontrar onde exibe o `fullLabel` da restrição.

- [ ] **Step 2: Adicionar badge "Verificado"**

Dentro do build do sheet, logo abaixo do título da restrição, adicionar:
```dart
if (widget.restriction.isVerified)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified, size: 14, color: Colors.amber.shade700),
        const SizedBox(width: 4),
        Text(
          'Verificado pela comunidade',
          style: TextStyle(fontSize: 12, color: Colors.amber.shade700),
        ),
      ],
    ),
  ),
```

- [ ] **Step 3: Lint**

```
flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/map_screen.dart
git commit -m "feat(restrictions): exibe badge Verificado no sheet de detalhes"
```

---

### Task 3: modelo + serviço de alertas de polícia

**Files:**
- Create: `lib/models/police_alert.dart`
- Create: `lib/services/police_alert_service.dart`
- Test: `test/services/police_alert_service_test.dart`

- [ ] **Step 1: Criar `lib/models/police_alert.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum PoliceAlertType { radar, police, blitz }

class PoliceAlert {
  final String? id;
  final PoliceAlertType type;
  final double lat;
  final double lng;
  final String uid;
  final DateTime createdAt;
  final DateTime expireAt;
  final int confirmations;
  final int notThereCount;

  const PoliceAlert({
    this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.uid,
    required this.createdAt,
    required this.expireAt,
    this.confirmations = 0,
    this.notThereCount = 0,
  });

  LatLng get position => LatLng(lat, lng);

  Duration get timeRemaining {
    final r = expireAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  String get timeRemainingText {
    final m = timeRemaining.inMinutes;
    if (m <= 0) return 'Expirando';
    return '${m}min restantes';
  }

  factory PoliceAlert.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PoliceAlert(
      id: doc.id,
      type: PoliceAlertType.values.firstWhere(
        (e) => e.name == (d['type'] as String? ?? 'police'),
        orElse: () => PoliceAlertType.police,
      ),
      lat: (d['lat'] as num).toDouble(),
      lng: (d['lng'] as num).toDouble(),
      uid: d['uid'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      expireAt: (d['expireAt'] as Timestamp).toDate(),
      confirmations: (d['confirmations'] as num?)?.toInt() ?? 0,
      notThereCount: (d['notThereCount'] as num?)?.toInt() ?? 0,
    );
  }
}
```

- [ ] **Step 2: Escrever testes do modelo**

```dart
// test/services/police_alert_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/police_alert.dart';

void main() {
  group('PoliceAlert.timeRemainingText', () {
    test('retorna minutos quando há tempo restante', () {
      final alert = PoliceAlert(
        type: PoliceAlertType.radar,
        lat: 0, lng: 0, uid: 'u1',
        createdAt: DateTime.now(),
        expireAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      expect(alert.timeRemainingText, '15min restantes');
    });

    test('retorna Expirando quando tempo zerado', () {
      final alert = PoliceAlert(
        type: PoliceAlertType.police,
        lat: 0, lng: 0, uid: 'u1',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        expireAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(alert.timeRemainingText, 'Expirando');
    });
  });
}
```

- [ ] **Step 3: Rodar testes**

```
flutter test test/services/police_alert_service_test.dart
```
Esperado: PASS.

- [ ] **Step 4: Criar `lib/services/police_alert_service.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/police_alert.dart';

class PoliceAlertService {
  static final _col = FirebaseFirestore.instance.collection('police_alerts');

  static Stream<List<PoliceAlert>> streamInBounds(
    double minLat, double maxLat, double minLng, double maxLng,
  ) {
    final now = Timestamp.now();
    return _col
        .where('lat', isGreaterThanOrEqualTo: minLat)
        .where('lat', isLessThanOrEqualTo: maxLat)
        .where('expireAt', isGreaterThan: now)
        .snapshots()
        .map((snap) => snap.docs
            .map(PoliceAlert.fromFirestore)
            .where((a) => a.lng >= minLng && a.lng <= maxLng)
            .toList());
  }

  static Future<void> report({
    required PoliceAlertType type,
    required double lat,
    required double lng,
    required String uid,
  }) async {
    final now = DateTime.now();
    await _col.add({
      'type': type.name,
      'lat': lat,
      'lng': lng,
      'uid': uid,
      'createdAt': Timestamp.fromDate(now),
      'expireAt': Timestamp.fromDate(now.add(const Duration(minutes: 30))),
      'confirmations': 0,
      'notThereCount': 0,
    });
  }

  static Future<void> confirm(String id) async {
    final ref = _col.doc(id);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap['expireAt'] as Timestamp).toDate();
      tx.update(ref, {
        'confirmations': FieldValue.increment(1),
        'expireAt': Timestamp.fromDate(
          current.add(const Duration(minutes: 15)),
        ),
      });
    });
  }

  static Future<void> notThere(String id) async {
    final ref = _col.doc(id);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final count = (snap['notThereCount'] as num).toInt() + 1;
      if (count >= 3) {
        tx.update(ref, {
          'notThereCount': count,
          'expireAt': Timestamp.now(),
        });
      } else {
        tx.update(ref, {'notThereCount': count});
      }
    });
  }
}
```

- [ ] **Step 5: Lint**

```
flutter analyze
```

- [ ] **Step 6: Commit**

```bash
git add lib/models/police_alert.dart lib/services/police_alert_service.dart \
        test/services/police_alert_service_test.dart
git commit -m "feat(police): modelo PoliceAlert e PoliceAlertService"
```

---

### Task 4: pins de polícia no mapa

**Files:**
- Modify: `lib/screens/map_screen.dart`

- [ ] **Step 1: Adicionar state + stream no `_MapScreenState`**

Adicionar campos após `_userRestrictions`:
```dart
List<PoliceAlert> _policeAlerts = [];
StreamSubscription<List<PoliceAlert>>? _policeAlertSub;
```

Adicionar import no topo:
```dart
import '../models/police_alert.dart';
import '../services/police_alert_service.dart';
```

- [ ] **Step 2: Iniciar stream em `_onCameraMove`**

Dentro de `onCameraMove` (ou criar método `_refreshPoliceAlerts`), chamar quando o mapa mover:
```dart
void _refreshPoliceAlerts(LatLngBounds bounds) {
  _policeAlertSub?.cancel();
  _policeAlertSub = PoliceAlertService.streamInBounds(
    bounds.southwest.latitude,
    bounds.northeast.latitude,
    bounds.southwest.longitude,
    bounds.northeast.longitude,
  ).listen((alerts) {
    if (mounted) setState(() => _policeAlerts = alerts);
  });
}
```

Chamar `_refreshPoliceAlerts` no callback `onCameraIdle` do `GoogleMap`:
```dart
onCameraIdle: () async {
  final bounds = await _mapController?.getVisibleRegion();
  if (bounds != null) _refreshPoliceAlerts(bounds);
},
```

Cancelar em `dispose()`:
```dart
_policeAlertSub?.cancel();
```

- [ ] **Step 3: Adicionar pins no método `_buildMarkers`**

Dentro do método que constrói os `markers`, após o loop de `_userRestrictions`:
```dart
for (final alert in _policeAlerts) {
  final color = switch (alert.type) {
    PoliceAlertType.radar  => Colors.orange.shade700,
    PoliceAlertType.police => Colors.blue.shade700,
    PoliceAlertType.blitz  => Colors.red.shade700,
  };
  markers.add(Marker(
    markerId: MarkerId('police_${alert.id}'),
    position: alert.position,
    icon: BitmapDescriptor.defaultMarkerWithHue(
      switch (alert.type) {
        PoliceAlertType.radar  => BitmapDescriptor.hueOrange,
        PoliceAlertType.police => BitmapDescriptor.hueBlue,
        PoliceAlertType.blitz  => BitmapDescriptor.hueRed,
      },
    ),
    infoWindow: InfoWindow(
      title: switch (alert.type) {
        PoliceAlertType.radar  => 'Radar',
        PoliceAlertType.police => 'Polícia',
        PoliceAlertType.blitz  => 'Blitz',
      },
      snippet: alert.timeRemainingText,
    ),
    onTap: () => _showPoliceAlertSheet(alert),
  ));
}
```

- [ ] **Step 4: Criar `_showPoliceAlertSheet`**

```dart
Future<void> _showPoliceAlertSheet(PoliceAlert alert) async {
  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PoliceAlertSheet(alert: alert),
  );
}
```

- [ ] **Step 5: Criar widget `_PoliceAlertSheet` no final de `map_screen.dart`**

```dart
class _PoliceAlertSheet extends StatelessWidget {
  final PoliceAlert alert;
  const _PoliceAlertSheet({required this.alert});

  String get _typeLabel => switch (alert.type) {
    PoliceAlertType.radar  => 'Radar',
    PoliceAlertType.police => 'Polícia',
    PoliceAlertType.blitz  => 'Blitz / Fiscalização',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_typeLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(alert.timeRemainingText,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (alert.id != null) {
                      await PoliceAlertService.notThere(alert.id!);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Não está mais lá'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    if (alert.id != null) {
                      await PoliceAlertService.confirm(alert.id!);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Adicionar botão de reporte no mapa**

Na área do mapa (dentro do `Stack`), adicionar um FAB ou botão discreto para reportar polícia:

```dart
// Dentro do Stack, acima do mapa, posicionado no canto inferior direito
Positioned(
  bottom: 16,
  right: 16,
  child: FloatingActionButton.small(
    heroTag: 'report_police',
    onPressed: _showReportPoliceSheet,
    tooltip: 'Reportar polícia',
    child: const Icon(Icons.local_police_outlined),
  ),
),
```

- [ ] **Step 7: Criar `_showReportPoliceSheet`**

```dart
Future<void> _showReportPoliceSheet() async {
  final uid = await AuthService.getUid();
  if (!mounted) return;
  final type = await showModalBottomSheet<PoliceAlertType>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _ReportPoliceSheet(),
  );
  if (type == null) return;
  await PoliceAlertService.report(
    type: type,
    lat: _cameraTarget.latitude,
    lng: _cameraTarget.longitude,
    uid: uid,
  );
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alerta reportado'), duration: Duration(seconds: 2)),
    );
  }
}
```

- [ ] **Step 8: Criar `_ReportPoliceSheet`**

```dart
class _ReportPoliceSheet extends StatelessWidget {
  const _ReportPoliceSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('O que você viu?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          for (final type in PoliceAlertType.values)
            ListTile(
              leading: Icon(switch (type) {
                PoliceAlertType.radar  => Icons.speed,
                PoliceAlertType.police => Icons.local_police,
                PoliceAlertType.blitz  => Icons.assignment_late,
              }),
              title: Text(switch (type) {
                PoliceAlertType.radar  => 'Radar de velocidade',
                PoliceAlertType.police => 'Polícia na via',
                PoliceAlertType.blitz  => 'Blitz / Fiscalização',
              }),
              onTap: () => Navigator.pop(context, type),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 9: Lint**

```
flutter analyze
```

- [ ] **Step 10: Commit**

```bash
git add lib/screens/map_screen.dart
git commit -m "feat(police): pins e sheet de reporte no mapa"
```

---

### Task 5: banner de proximidade na navegação

**Files:**
- Modify: `lib/screens/navigation_screen.dart`

- [ ] **Step 1: Localizar onde começa `NavigationScreen`**

Buscar `class NavigationScreen` e `class _NavigationScreenState`. Verificar se tem campo para posição atual (`_snappedPos` ou similar).

- [ ] **Step 2: Adicionar state de alertas próximos**

Em `_NavigationScreenState`, adicionar:
```dart
PoliceAlert? _nearestPoliceAlert;
```

Import no topo:
```dart
import '../models/police_alert.dart';
import '../services/police_alert_service.dart';
```

- [ ] **Step 3: Verificar proximidade durante navegação**

No método `_onPositionUpdate` (ou equivalente que recebe a posição GPS), adicionar:
```dart
void _checkPoliceAlerts(LatLng position) {
  const radiusMeters = 500.0;
  const lat = 0.0045; // ~500m em graus lat
  const lng = 0.0050; // ~500m em graus lng na latitude do Brasil
  PoliceAlertService.streamInBounds(
    position.latitude - lat, position.latitude + lat,
    position.longitude - lng, position.longitude + lng,
  ).first.then((alerts) {
    if (!mounted) return;
    // filtra pelo mais próximo dentro de 500m
    PoliceAlert? nearest;
    double bestDist = radiusMeters;
    for (final a in alerts) {
      final d = RadarService.haversine(
        position.latitude, position.longitude, a.lat, a.lng);
      if (d < bestDist) { bestDist = d; nearest = a; }
    }
    if (nearest?.id != _nearestPoliceAlert?.id) {
      setState(() => _nearestPoliceAlert = nearest);
    }
  });
}
```

Chamar `_checkPoliceAlerts(snappedPos)` dentro de `_onPositionUpdate` após calcular `snappedPos`.

- [ ] **Step 4: Adicionar banner no build da NavigationScreen**

Dentro do Stack do `NavigationScreen`, antes dos widgets de instrução de manobra, adicionar:
```dart
if (_nearestPoliceAlert != null)
  Positioned(
    top: 0, left: 0, right: 0,
    child: Material(
      color: switch (_nearestPoliceAlert!.type) {
        PoliceAlertType.radar  => Colors.orange.shade700,
        PoliceAlertType.police => Colors.blue.shade700,
        PoliceAlertType.blitz  => Colors.red.shade700,
      },
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.local_police, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switch (_nearestPoliceAlert!.type) {
                    PoliceAlertType.radar  => 'Radar à frente',
                    PoliceAlertType.police => 'Polícia à frente',
                    PoliceAlertType.blitz  => 'Blitz à frente',
                  },
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                _nearestPoliceAlert!.timeRemainingText,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
```

- [ ] **Step 5: Lint**

```
flutter analyze
```

- [ ] **Step 6: Commit**

```bash
git add lib/screens/navigation_screen.dart
git commit -m "feat(police): banner de proximidade na tela de navegação"
```

---

### Task 6: configurar TTL nativo no Firestore (passo manual)

> Esta task não tem código — é configuração no Firebase Console.

- [ ] **Step 1: Acessar Firebase Console**

Ir para https://console.firebase.google.com → projeto `truck-router1` → Firestore Database → Índices → TTL policies.

- [ ] **Step 2: Criar política TTL**

- Collection group: `police_alerts`
- Field: `expireAt`
- Clicar em "Create"

Firestore passará a apagar documentos com `expireAt` no passado automaticamente (pode demorar até 24h para início). Não afeta a query do Flutter que já filtra `where expireAt > now`.

- [ ] **Step 3: Criar índice composto necessário**

A query usa `lat >=`, `lat <=`, `expireAt >` — o Firestore vai pedir um índice composto.  
Quando o app rodar pela primeira vez e a query for executada, o Firestore retornará um link no log para criar o índice automaticamente. Clicar no link ou criar manualmente:

- Collection: `police_alerts`
- Fields: `lat ASC`, `expireAt ASC`

- [ ] **Step 4: Anotar como concluído**

Não tem commit — é infraestrutura.

---

## FASE 2 — Cache no proxy de roteamento

> O proxy já existe (`GET /route/here` → HERE API). Esta fase adiciona cache em memória com TTL de 2 horas. Zero mudanças no Flutter.

---

### Task 7: pacote de cache em memória

**Files:**
- Create: `backend/internal/cache/cache.go`
- Test: `backend/internal/cache/cache_test.go`

- [ ] **Step 1: Escrever teste**

```go
// backend/internal/cache/cache_test.go
package cache_test

import (
	"testing"
	"time"

	"github.com/pedrolucas201/truck-router/backend/internal/cache"
)

func TestCacheHitAndMiss(t *testing.T) {
	c := cache.New(100 * time.Millisecond)
	
	_, _, _, ok := c.Get("key1")
	if ok {
		t.Fatal("expected miss on empty cache")
	}
	
	c.Set("key1", []byte("body"), 200, "application/json")
	body, status, ct, ok := c.Get("key1")
	if !ok {
		t.Fatal("expected hit after Set")
	}
	if string(body) != "body" || status != 200 || ct != "application/json" {
		t.Fatalf("unexpected values: %s %d %s", body, status, ct)
	}
}

func TestCacheTTLExpiry(t *testing.T) {
	c := cache.New(50 * time.Millisecond)
	c.Set("key1", []byte("body"), 200, "text/plain")
	
	time.Sleep(100 * time.Millisecond)
	
	_, _, _, ok := c.Get("key1")
	if ok {
		t.Fatal("expected miss after TTL expiry")
	}
}
```

- [ ] **Step 2: Rodar e verificar falha**

```
cd backend
go test ./internal/cache/...
```
Esperado: erro de compilação (package não existe ainda).

- [ ] **Step 3: Criar `backend/internal/cache/cache.go`**

```go
package cache

import (
	"sync"
	"time"
)

type entry struct {
	value   []byte
	status  int
	ct      string
	expires time.Time
}

// Cache é uma estrutura em memória com TTL por entrada.
// Thread-safe. Não compartilhado entre instâncias do Cloud Run — aceitável para o volume atual.
type Cache struct {
	mu  sync.RWMutex
	m   map[string]entry
	ttl time.Duration
}

func New(ttl time.Duration) *Cache {
	c := &Cache{m: make(map[string]entry), ttl: ttl}
	go c.evict()
	return c
}

func (c *Cache) Get(key string) (body []byte, status int, ct string, ok bool) {
	c.mu.RLock()
	e, found := c.m[key]
	c.mu.RUnlock()
	if !found || time.Now().After(e.expires) {
		return nil, 0, "", false
	}
	return e.value, e.status, e.ct, true
}

func (c *Cache) Set(key string, body []byte, status int, ct string) {
	c.mu.Lock()
	c.m[key] = entry{value: body, status: status, ct: ct, expires: time.Now().Add(c.ttl)}
	c.mu.Unlock()
}

func (c *Cache) evict() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		now := time.Now()
		c.mu.Lock()
		for k, e := range c.m {
			if now.After(e.expires) {
				delete(c.m, k)
			}
		}
		c.mu.Unlock()
	}
}
```

- [ ] **Step 4: Rodar testes**

```
cd backend
go test ./internal/cache/...
```
Esperado: PASS.

- [ ] **Step 5: Commit**

```bash
cd backend
git add internal/cache/cache.go internal/cache/cache_test.go
git commit -m "feat(cache): pacote de cache em memória com TTL"
```

---

### Task 8: integrar cache nos handlers de roteamento

**Files:**
- Modify: `backend/internal/handlers/proxy.go`
- Modify: `backend/internal/handlers/route.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Adicionar `fetchBody` e `forwardWithCache` em `proxy.go`**

Adicionar após as funções existentes em `proxy.go`:

```go
import (
	// adicionar ao import existente:
	"io"
	"net/url"
	"crypto/sha256"
	"encoding/hex"
	
	"github.com/pedrolucas201/truck-router/backend/internal/cache"
)

// fetchBody faz GET em targetURL e retorna body + status + content-type.
func fetchBody(targetURL, rawQuery string) ([]byte, int, string, error) {
	req, err := http.NewRequest(http.MethodGet, targetURL+"?"+rawQuery, nil)
	if err != nil {
		return nil, 0, "", err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, 0, "", err
	}
	return body, resp.StatusCode, resp.Header.Get("Content-Type"), nil
}

// routeCacheKey gera chave SHA256 do raw query sem a API key.
func routeCacheKey(rawQuery string) string {
	q, _ := url.ParseQuery(rawQuery)
	q.Del("apikey")
	q.Del("key")
	sum := sha256.Sum256([]byte(q.Encode()))
	return hex.EncodeToString(sum[:])
}

// forwardCached verifica cache antes de fazer request. Salva no cache se status 200.
func forwardCached(w http.ResponseWriter, c *cache.Cache, key, targetURL, rawQuery string) {
	if body, status, ct, ok := c.Get(key); ok {
		w.Header().Set("Content-Type", ct)
		w.Header().Set("X-Cache", "HIT")
		w.WriteHeader(status)
		w.Write(body)
		return
	}
	body, status, ct, err := fetchBody(targetURL, rawQuery)
	if err != nil {
		log.Printf("forwardCached %s: %v", targetURL, err)
		http.Error(w, "internal error", http.StatusBadGateway)
		return
	}
	if status == http.StatusOK {
		c.Set(key, body, status, ct)
	}
	w.Header().Set("Content-Type", ct)
	w.Header().Set("X-Cache", "MISS")
	w.WriteHeader(status)
	w.Write(body)
}
```

- [ ] **Step 2: Refatorar `route.go` para usar `RouteHandlers` com cache**

Substituir o conteúdo de `route.go` por:

```go
package handlers

import (
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/pedrolucas201/truck-router/backend/internal/cache"
)

type RouteHandlers struct {
	cache *cache.Cache
}

func NewRouteHandlers() *RouteHandlers {
	return &RouteHandlers{cache: cache.New(2 * time.Hour)}
}

// HereRoute: GET /route/here — proxy para router.hereapi.com/v8/routes com cache 2h.
func (h *RouteHandlers) HereRoute(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	key := routeCacheKey(r.URL.RawQuery)
	forwardCached(w, h.cache, key, "https://router.hereapi.com/v8/routes", q)
}

// TomTomRoute: GET /route/tomtom/{locs} — proxy para TomTom com cache 2h.
func (h *RouteHandlers) TomTomRoute(w http.ResponseWriter, r *http.Request) {
	locs := chi.URLParam(r, "*")
	q := appendKey(r.URL.RawQuery, "key", os.Getenv("TOMTOM_API_KEY"))
	key := routeCacheKey(r.URL.RawQuery + locs)
	forwardCached(w, h.cache, key, "https://api.tomtom.com/routing/1/calculateRoute/"+locs+"/json", q)
}
```

- [ ] **Step 3: Atualizar `main.go` para usar `RouteHandlers`**

Substituir as linhas:
```go
// Routing proxy
r.Get("/route/here", handlers.HereRoute)
r.Get("/route/tomtom/*", handlers.TomTomRoute)
```

Por:
```go
// Routing proxy com cache
rh := handlers.NewRouteHandlers()
r.Get("/route/here", rh.HereRoute)
r.Get("/route/tomtom/*", rh.TomTomRoute)
```

- [ ] **Step 4: Compilar**

```
cd backend
go build ./...
```
Esperado: compilação sem erros.

- [ ] **Step 5: Commit**

```bash
git add internal/handlers/proxy.go internal/handlers/route.go cmd/server/main.go
git commit -m "feat(cache): adiciona cache 2h nos endpoints de roteamento HERE e TomTom"
```

---

### Task 9: deploy do backend

- [ ] **Step 1: Rodar `/backend` (skill)**

Usar o skill `/backend` para subir a nova versão no Cloud Run.

- [ ] **Step 2: Verificar header `X-Cache`**

Fazer duas chamadas seguidas ao endpoint `/route/here` com os mesmos parâmetros. A segunda deve retornar `X-Cache: HIT`.

```bash
# Exemplo manual via curl (substituir com parâmetros reais)
curl -s -D - "https://truck-router-backend-707407458764.southamerica-east1.run.app/route/here?transportMode=truck&origin=-23.5,-46.6&destination=-23.6,-46.7&return=polyline" | grep X-Cache
```

---

## FASE 3 — Compartilhar rota

---

### Task 10: estender `geo_uri_parser.dart` para maps.google.com

**Files:**
- Modify: `lib/utils/geo_uri_parser.dart`
- Test: `test/utils/geo_uri_parser_test.dart`

- [ ] **Step 1: Escrever testes**

```dart
// test/utils/geo_uri_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/geo_uri_parser.dart';

void main() {
  group('parseGeoUri — geo: scheme', () {
    test('parseia geo:lat,lng básico', () {
      final uri = Uri.parse('geo:-23.5505,-46.6333');
      final result = parseGeoUri(uri);
      expect(result, isNotNull);
      expect(result!.destination.latitude, closeTo(-23.5505, 0.0001));
    });
  });

  group('parseMapsUri — maps.google.com', () {
    test('parseia saddr e daddr', () {
      final uri = Uri.parse(
        'https://maps.google.com/maps?saddr=-23.5,-46.6&daddr=-23.6,-46.7',
      );
      final result = parseMapsUri(uri);
      expect(result, isNotNull);
      expect(result!.origin, isNotNull);
      expect(result.origin!.latitude, closeTo(-23.5, 0.0001));
      expect(result.destination.latitude, closeTo(-23.6, 0.0001));
    });

    test('parseia só daddr (sem origem)', () {
      final uri = Uri.parse(
        'https://maps.google.com/maps?daddr=-23.6,-46.7',
      );
      final result = parseMapsUri(uri);
      expect(result, isNotNull);
      expect(result!.origin, isNull);
      expect(result.destination.latitude, closeTo(-23.6, 0.0001));
    });

    test('retorna null para URL inválida', () {
      final uri = Uri.parse('https://maps.google.com/maps?q=pizza');
      final result = parseMapsUri(uri);
      expect(result, isNull);
    });
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

```
flutter test test/utils/geo_uri_parser_test.dart
```
Esperado: FAIL — `parseMapsUri` não existe + `destination` não existe (struct mudará).

- [ ] **Step 3: Atualizar `geo_uri_parser.dart`**

Substituir o conteúdo completo por:

```dart
import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef GeoLocation = ({LatLng coords, String? label});

// Resultado de parseMapsUri — pode ter origem + destino
typedef MapsRoute = ({LatLng? origin, LatLng destination});

/// Parses a `geo:` URI into coordinates and optional label.
GeoLocation? parseGeoUri(Uri uri) {
  if (uri.scheme != 'geo') return null;

  final q = uri.queryParameters['q'];
  if (q != null) {
    String? label;
    String coords = q;
    final parenIdx = q.indexOf('(');
    if (parenIdx != -1) {
      label = q.substring(parenIdx + 1, q.endsWith(')') ? q.length - 1 : q.length);
      coords = q.substring(0, parenIdx).trim();
    }
    final latLng = _parseLatLng(coords);
    if (latLng == null) return null;
    return (coords: latLng, label: label?.isNotEmpty == true ? label : null);
  }

  final latLng = _parseLatLng(uri.path);
  if (latLng == null) return null;
  return (coords: latLng, label: null);
}

/// Parses a `https://maps.google.com/maps?saddr=...&daddr=...` URI.
/// Returns null if daddr is missing or unparseable.
MapsRoute? parseMapsUri(Uri uri) {
  if (uri.host != 'maps.google.com') return null;

  final daddrStr = uri.queryParameters['daddr'];
  if (daddrStr == null) return null;
  final destination = _parseLatLng(daddrStr);
  if (destination == null) return null;

  final saddrStr = uri.queryParameters['saddr'];
  final origin = saddrStr != null ? _parseLatLng(saddrStr) : null;

  return (origin: origin, destination: destination);
}

LatLng? _parseLatLng(String s) {
  final parts = s.split(',');
  if (parts.length < 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  if (lat == 0.0 && lng == 0.0) return null;
  return LatLng(lat, lng);
}
```

- [ ] **Step 4: Rodar testes**

```
flutter test test/utils/geo_uri_parser_test.dart
flutter analyze
```
Esperado: PASS, zero issues.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/geo_uri_parser.dart test/utils/geo_uri_parser_test.dart
git commit -m "feat(deeplink): parseMapsUri suporta maps.google.com com saddr+daddr"
```

---

### Task 11: intent filter no AndroidManifest

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Localizar o `<activity>` principal**

Abrir `android/app/src/main/AndroidManifest.xml`. Localizar o `<activity android:name=".MainActivity">`.

- [ ] **Step 2: Adicionar intent filter**

Dentro do `<activity>`, após o intent filter existente de `geo:`, adicionar:

```xml
<!-- maps.google.com — aparece no chooser ao receber link de rota compartilhada -->
<intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data
        android:scheme="https"
        android:host="maps.google.com"
        android:pathPrefix="/maps"/>
</intent-filter>
```

- [ ] **Step 3: Verificar que o app ainda compila**

```
flutter build apk --debug
```

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "feat(deeplink): registra intent filter para maps.google.com/maps"
```

---

### Task 12: botão compartilhar e handler de origem no MapScreen

**Files:**
- Modify: `lib/screens/map_screen.dart`

> `share_plus` já está no pubspec. `parseMapsUri` foi criada na Task 10.

- [ ] **Step 1: Atualizar `_handleGeoUri` para aceitar maps.google.com**

Localizar o método `_initDeepLinks`. Atualizar o listener e o initial link para também tentar `parseMapsUri`:

```dart
Future<void> _initDeepLinks() async {
  final appLinks = AppLinks();
  final initial = await appLinks.getInitialLink();
  if (initial != null && mounted) _handleIncomingUri(initial);
  _deepLinkSub = appLinks.uriLinkStream.listen((uri) {
    if (mounted) _handleIncomingUri(uri);
  });
}

void _handleIncomingUri(Uri uri) {
  // Tenta maps.google.com primeiro
  final route = parseMapsUri(uri);
  if (route != null) {
    _setDeepLinkRoute(route);
    return;
  }
  // Fallback para geo: URI (destino apenas)
  final geo = parseGeoUri(uri);
  if (geo == null) return;
  _handleGeoUri(geo);
}

void _setDeepLinkRoute(MapsRoute route) {
  setState(() {
    _destination      = route.destination;
    _destinationLabel = 'Destino compartilhado';
    _destinationKey   = ValueKey('dest_shared_${DateTime.now().millisecondsSinceEpoch}');
    if (route.origin != null) {
      _origin      = route.origin;
      _originLabel = 'Origem compartilhada';
      _originKey   = ValueKey('origin_shared_${DateTime.now().millisecondsSinceEpoch}');
    }
  });
  context.read<RouteProvider>().clear();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(route.origin != null
          ? 'Rota recebida — toque em Calcular para rotear'
          : 'Destino recebido — toque em Calcular para rotear'),
      duration: const Duration(seconds: 4),
    ),
  );
  if (_origin != null && _destination != null) _calculate();
}
```

Renomear o antigo `_handleGeoUri` para aceitar `GeoLocation` diretamente:
```dart
void _handleGeoUri(GeoLocation geo) {
  if (_destination != null) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar como destino?'),
        content: const Text('Isso vai substituir o destino atual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _setDeepLinkDestination(geo); },
            child: const Text('Usar'),
          ),
        ],
      ),
    );
  } else {
    _setDeepLinkDestination(geo);
  }
}
```

- [ ] **Step 2: Criar `_shareRoute`**

```dart
Future<void> _shareRoute() async {
  if (_origin == null || _destination == null) return;
  final originLabel  = _originLabel  ?? 'Origem';
  final destLabel    = _destinationLabel ?? 'Destino';
  final url = 'https://maps.google.com/maps'
      '?saddr=${_origin!.latitude},${_origin!.longitude}'
      '&daddr=${_destination!.latitude},${_destination!.longitude}';
  await SharePlus.instance.share(
    ShareParams(
      text: '🚛 $originLabel → $destLabel\n$url\n\n'
            'Se tiver o Truck Router instalado, escolha ele no seletor de apps.',
    ),
  );
}
```

- [ ] **Step 3: Adicionar botão no card de resultado**

Localizar onde é exibido o card de resultado da rota (botão "Iniciar navegação"). Adicionar um `IconButton` de compartilhar ao lado:

```dart
// Dentro do row de ações do card de rota, consumindo RouteProvider
if (context.watch<RouteProvider>().status == RouteStatus.success)
  IconButton(
    icon: const Icon(Icons.share),
    tooltip: 'Compartilhar rota',
    onPressed: _shareRoute,
  ),
```

- [ ] **Step 4: Lint**

```
flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/map_screen.dart
git commit -m "feat(share): botão compartilhar rota + deep link com origem+destino"
```

---

## Self-review

### Cobertura do spec

| Requisito | Task |
|---|---|
| Novos tipos de restrição: peso, truck_ban | Task 1 — mas `maxweight` já existia. `truck_ban` é o real novo tipo. |
| Badge isVerified (pin) | Já estava implementado (borda dourada). Task 2 adiciona label textual no sheet. |
| Alertas de polícia: modelo + Firestore | Task 3 |
| TTL 30min + confirmação +15min + notThere ×3 | Task 3 (PoliceAlertService) |
| Pins no mapa por tipo | Task 4 |
| Bottom sheet confirmar / não está mais lá | Task 4 |
| Botão de reporte | Task 4 |
| Banner de proximidade na navegação (500m) | Task 5 |
| Firestore TTL nativo | Task 6 |
| Cache de roteamento no backend | Task 7 + 8 |
| Deploy backend | Task 9 |
| `parseMapsUri` para maps.google.com | Task 10 |
| Intent filter AndroidManifest | Task 11 |
| Botão compartilhar + share message | Task 12 |
| Deep link com origem + destino | Task 12 |

### Nota sobre Fase 2

O spec descrevia Fase 2 como "mover proxy ao backend" — mas o proxy já existe e a chave HERE já está no Secret Manager. O que esta fase implementa é apenas o cache em memória (sem mudanças no Flutter). O fallback HERE→TomTom já é feito pelo RouteProvider no Flutter em paralelo.

### Gaps identificados

- **Índice Firestore para police_alerts** (Task 6): precisa ser criado manualmente. Firestore apontará o link quando a primeira query falhar por falta do índice.
- **`maxwidth` restriction**: já existia no código (assim como `maxweight`). O spec mencionava "weight" como novo, mas o tipo era `maxweight` que já existia. Truck_ban é o único realmente novo.
