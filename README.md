# Truck Router

App Android de roteamento para caminhões no Brasil. Calcula rotas otimizadas para veículos pesados evitando viadutos baixos, vias com restrição de peso, estradas de terra e restrições de horário.

## Funcionalidades

- Roteamento truck-aware via HERE Routing API v8 (altura, peso, comprimento, largura)
- Fonte secundária TomTom Routing v1 em paralelo — usada quando >10% mais rápida
- Busca de endereços e empresas por nome (HERE Geocode + Discover)
- Navegação turn-by-turn interna com TTS em português
- Radares e lombadas (39.835 pontos, CSV bundled)
- Restrições crowd-sourced (viadutos, peso, largura, estradas de terra) via Firestore
- Marcação de restrições no mapa via crosshair (mapa e navegação)
- Visualização dual de rotas: pavimentada vs. com estrada de terra, com seleção por toque
- Alerta visual (overlay vermelho pulsante) e TTS ao se aproximar de restrição bloqueada
- Alerta de restrição de horário ao detectar `violatedVehicleRestriction` na rota
- GPS com tela apagada via foreground service
- Múltiplos perfis de caminhão nomeados, persistidos em SharedPreferences

## Stack

| Camada | Tecnologia |
|---|---|
| Framework | Flutter 3.10.7 / Dart 3.10.7 |
| Mapa | `google_maps_flutter ^2.9.0` |
| Roteamento | HERE Routing API v8, TomTom Routing API v1 |
| Geocodificação | HERE Geocode + Discover API |
| State management | Provider (ChangeNotifier) |
| Persistência local | SharedPreferences |
| Backend crowd | Firebase Auth anônima + Firestore |
| GPS background | `flutter_foreground_task` |

## Configuração

As chaves de API ficam em `lib/config.dart`:

```dart
const googleMapsApiKey = 'SUA_CHAVE';
const hereApiKey       = 'SUA_CHAVE';
const tomTomApiKey     = 'SUA_CHAVE';
```

A chave do Google Maps também está em `android/app/src/main/AndroidManifest.xml`.

## Comandos

```bash
# Rodar no dispositivo
flutter run

# Build APK release (--no-tree-shake-icons é obrigatório)
flutter build apk --release --no-tree-shake-icons

# Lint
flutter analyze

# Testes
flutter test
```

## Arquitetura

```
lib/
├── config.dart                  # Chaves de API
├── main.dart                    # Root widget, injeção de providers
├── models/
│   ├── bridge_restriction.dart  # Restrição de via (altura/peso/largura/terra)
│   ├── route_result.dart        # Resultado de rota + alternativa de terra
│   ├── truck_profile.dart       # Perfil do caminhão
│   └── ...
├── providers/
│   ├── route_provider.dart      # Estado da rota (idle→loading→success|error)
│   └── truck_profile_provider.dart
├── repositories/
│   ├── restriction_repository.dart          # Interface abstrata
│   ├── firestore_restriction_repository.dart
│   └── api_restriction_repository.dart      # Go backend (pronto, aguarda servidor)
├── services/
│   ├── here_routing_service.dart    # HERE Routing v8
│   ├── here_geocoding_service.dart  # Geocode + Discover
│   └── ...
├── screens/
│   ├── map_screen.dart          # Tela principal
│   └── navigation_screen.dart  # Navegação turn-by-turn
└── widgets/
    ├── crosshair.dart           # Widget de mira para marcar restrições
    └── add_restriction_sheet.dart
```

**Seleção de repositório de restrições:**

```bash
# Firestore (padrão)
flutter run

# Backend Go
flutter run --dart-define=BACKEND_URL=http://localhost:8080
```

## Perfil de caminhão

Campos mapeados diretamente para parâmetros HERE:

| Campo | HERE param | Padrão |
|---|---|---|
| `heightCm` | `vehicle[height]` | 420 cm |
| `lengthCm` | `vehicle[length]` | 1400 cm |
| `weightKg` | `vehicle[grossWeight]` | 25 000 kg |
