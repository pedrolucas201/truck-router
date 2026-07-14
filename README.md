# 🚛 Truck Router

**Navegação para caminhoneiros no Brasil.** Rota que respeita a altura do teu baú, o peso do teu eixo e o horário que a prefeitura deixa você passar — e que te avisa do radar antes dele.

Um GPS comum manda o caminhão embaixo de um viaduto de 3,80 m. Este não.

<p>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.10-02569B?logo=flutter&logoColor=white">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.10-0175C2?logo=dart&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-APK-3DDC84?logo=android&logoColor=white">
  <img alt="Firebase" src="https://img.shields.io/badge/Firebase-Firestore-FFCA28?logo=firebase&logoColor=black">
  <img alt="Testes" src="https://img.shields.io/badge/testes-123%20passando-success">
</p>

---

## O que ele faz

### 🛣️ Rota que entende de caminhão
- **HERE Routing v8** com as dimensões reais do veículo (altura, peso, comprimento, largura) — evita viaduto baixo, ponte com limite de peso e via proibida pra carga.
- **TomTom Routing v1 em paralelo**, adotada quando é >10% mais rápida.
- **Restrição de horário**: avisa quando a rota cruza uma via com janela fechada pra caminhão.
- **Rota alternativa sem terra**: mostra as duas (pavimentada × com estrada de terra) e deixa escolher no toque.
- **Recálculo com rumo de marcha**: manda o `course` do GPS junto — sem isso a HERE devolvia meia-volta quando o motorista pegava outro caminho.

### 🎯 Navegação feita pra quem está dirigindo
- Turn-by-turn com **voz em português** e três níveis de áudio.
- **Puck fixo** na tela com o mapa girando embaixo (heading-up), a 30 fps.
- **Olhar-ao-redor**: arrasta o mapa pra espiar o trecho à frente e ele volta sozinho pro acompanhamento.
- **GPS com a tela apagada** (foreground service) — o caminhoneiro dirige com o celular no bolso.
- Zoom em três níveis, velocímetro e a placa de limite (padrão **R-19**) do jeito que ele lê num relance.

### 📸 Radar, lombada e blitz
- **39.835 radares** embarcados (CSV) + radares marcados pela comunidade.
- **Corredor de 22 m perpendicular à rota**: radar de via paralela não dispara alerta falso.
- **Flash vermelho na tela** ao passar do limite dentro de área de radar.
- **O motorista é o curador**: o app pergunta *"esse radar existe?"* e a palavra dele vira fato — nega o radar, corrige a velocidade, e o verdicto vale **offline, na hora**, sem esperar servidor.
- Alertas de blitz/polícia com linha do tempo.

### 🌉 Restrições da comunidade
- Marca viaduto baixo, limite de peso, largura e estrada de terra direto no mapa (mira/crosshair).
- Sincroniza via Firestore e alimenta o roteamento (vira `avoidArea` no próximo cálculo).
- **Alerta pulsante + voz** ao se aproximar de uma restrição que conflita com o teu perfil.

### 📡 Telemetria de campo
O motorista não captura logcat dirigindo. Então o app conta a própria história: cada evento crítico (recálculo, saída de rota, chegada, congelamento) vai pro Firestore **carimbado com a versão do build**, e fica consultável ao vivo — sem depender do device dele.

---

## 🏗️ Arquitetura

```
lib/
├── config.dart              # Chaves via --dart-define (NUNCA hardcoded)
├── main.dart
├── models/                  # RouteResult, TruckProfile, RadarPoint, BridgeRestriction…
├── providers/               # RouteProvider (idle→loading→success|error), TruckProfileProvider
├── repositories/            # Interface + impl Firestore / backend Go
├── services/
│   ├── here_routing_service.dart      # rota (via backend)
│   ├── tomtom_routing_service.dart    # rota alternativa (via backend)
│   ├── radar_service.dart             # CSV + geometria (corredor perpendicular)
│   ├── firestore_radar_service.dart   # crowd + verdictos do curador
│   ├── field_log.dart                 # telemetria de campo
│   └── …
├── screens/
│   ├── map_screen.dart                # busca, perfil, cálculo
│   └── navigation_screen.dart         # turn-by-turn
├── widgets/nav/                       # puck, barra de instrução, bottom bar
└── utils/                             # geometria, ângulos, frases de manobra
```

**Fluxo:** `MapScreen` → `RouteProvider.calculate()` → backend Go → HERE/TomTom → `RouteResult` (polyline decodificada do *Flexible Polyline* da HERE) → `NavigationScreen`.

| Camada | Tecnologia |
|---|---|
| Framework | Flutter 3.10 / Dart 3.10 |
| Mapa | `google_maps_flutter` |
| Roteamento | HERE Routing v8 + TomTom Routing v1 |
| Busca | HERE Geocode + Discover |
| Estado | Provider (`ChangeNotifier`) |
| Crowd / telemetria | Firebase Auth anônima + Firestore |
| Crash / breadcrumbs | Firebase Crashlytics |
| GPS em background | `flutter_foreground_task` |
| Distribuição | Firebase App Distribution + GCS |

---

## 🔐 Chaves de API

**Nenhuma chave de roteamento vive no app.** O cliente fala com um backend Go, e as chaves **HERE** e **TomTom** ficam no **Secret Manager** (GCP).

A única chave embarcada é a do **Google Maps** — ela precisa estar no APK pra renderizar o mapa, e é protegida por restrição de *package name* + SHA-1 no console do Google.

Ela entra por `--dart-define`, a partir de um `dart_defines.json` que **não vai pro git**:

```jsonc
// dart_defines.json  (gitignored)
{
  "GOOGLE_MAPS_API_KEY": "...",
  "BACKEND_URL": "https://..."
}
```

```bash
flutter run --dart-define-from-file=dart_defines.json
```

---

## ⚙️ Comandos

```bash
flutter pub get
flutter run --dart-define-from-file=dart_defines.json

flutter analyze          # lint — roda a cada mudança, sem exceção
flutter test             # 123 testes

# Release: build + GCS + notifica os motoristas no App Distribution
# (bumpe a versão no pubspec.yaml ANTES)
./release.ps1 -Notes "o que mudou pro motorista"
./release.ps1 -SkipDistribution   # só publica, sem avisar os testers
```

**Trocar a fonte de restrições:**
```bash
flutter run                                              # Firestore (padrão)
flutter run --dart-define=BACKEND_URL=http://localhost:8080   # backend Go
```

---

## 🚚 Perfil do caminhão

Múltiplos perfis nomeados, persistidos localmente. Os campos vão direto pros parâmetros da HERE:

| Campo | Param HERE | Padrão |
|---|---|---|
| `heightCm` | `vehicle[height]` | 420 cm |
| `lengthCm` | `vehicle[length]` | 1400 cm |
| `weightKg` | `vehicle[grossWeight]` | 25 000 kg |

---

## 🧪 Qualidade

Este app anda em rodovia com um caminhão de verdade. Bug aqui não é ticket — é o motorista parado no acostamento.

- **`docs/regressao-p0.md`** — checklist de regressão dos bugs P0. A regra é dura: *fix de sintoma não fecha o item*. Todo build que vai pro motorista passa por ele inteiro.
- **Teste guarda invariante, não implementação.** Cada correção de campo deixa pra trás o teste que falha se o bug voltar — o nome do teste conta o caso real (*"digitar 40 devolve 40"*, *"o radar negado não ressuscita"*).
- **Telemetria antes de conserto.** Sintoma na tela costuma ter duas causas possíveis; a gente instrumenta, dirige, lê o log — e só então mexe no código.

---

## 📋 Status

Em uso real por motoristas, distribuído via Firebase App Distribution. Desenvolvimento ativo.
