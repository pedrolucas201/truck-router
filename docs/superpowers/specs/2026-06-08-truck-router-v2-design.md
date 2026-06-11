# Spec: Truck Router v2 — Restrições, Proxy de Roteamento e Compartilhamento

**Data:** 2026-06-08  
**Status:** Aprovado para implementação  
**Abordagem:** Usuário primeiro (Fase 1 → Fase 2 → Fase 3)

---

## Escopo

Três fases independentes, entregáveis separadamente:

| Fase | O que é | Visível ao usuário |
|---|---|---|
| 1 | Novos tipos de restrição + alertas de polícia efêmeros | Sim |
| 2 | Proxy de roteamento no backend Go | Não (infraestrutura) |
| 3 | Compartilhar rota pelo WhatsApp | Sim |

**Fora do escopo:**
- Fotos como evidência em restrições
- Geocoding via proxy
- Onboarding (está bom)
- Play Store / monetização

---

## Fase 1 — Restrições comunitárias + Alertas de polícia

### 1.1 Novos tipos de restrição permanente

**Modelo de dados — `user_restrictions/{id}` (Firestore)**

Campo `type` existente ganha dois novos valores:

| type | Novo campo | Descrição |
|---|---|---|
| `bridge` | `heightCm: int` | Existente — sem mudança |
| `weight` | `weightKg: int` | Novo — limite de tonelagem |
| `truck_ban` | — | Novo — proibido caminhões |

Campos existentes sem mudança: `lat`, `lng`, `label`, `uid`, `confirmedBy`, `isVerified`.

**Flutter — `UserRestriction` model:**
- Adicionar `weightKg: int?`
- `type` vira enum ou string com os três valores
- `AddRestrictionSheet`: seletor de tipo + campos condicionais (altura para bridge, peso para weight, nenhum extra para truck_ban)

### 1.2 Badge isVerified

O campo `isVerified` já existe no modelo e no Firestore. Falta apenas UI:
- Pin no mapa com cor/ícone diferenciado para restrições verificadas
- Label "Verificado" no bottom sheet de detalhes da restrição

### 1.3 Alertas de polícia efêmeros

**Modelo de dados — `police_alerts/{id}` (Firestore)**

```
type:          "radar" | "police" | "blitz"
lat:           double
lng:           double
uid:           string           — quem reportou
createdAt:     Timestamp
expireAt:      Timestamp        — TTL nativo do Firestore apaga o doc automaticamente
confirmations: int              — cada confirmação adiciona 15 min ao expireAt
notThereCount: int              — ao atingir 3: expireAt = now (expira imediatamente)
```

**TTL nativo do Firestore:**  
Configurar política de expiração no campo `expireAt` via Firebase Console (ou Terraform). Firestore apaga documentos com `expireAt` no passado automaticamente — sem Cloud Function, sem custo extra.

**Ciclo de vida:**

```
Reportar         → expireAt = now + 30min
Confirmar        → expireAt += 15min (sem teto)
"Não está mais lá" → notThereCount++
notThereCount ≥ 3 → expireAt = now
```

Flutter filtra sempre `where expireAt > now` — documentos expirados somem da UI mesmo antes da deleção física pelo Firestore.

**UX no mapa:**
- Pins coloridos por tipo: radar (laranja), polícia (azul), blitz (vermelho)
- Tap no pin: bottom sheet com tipo, tempo restante estimado (`expireAt - now`), botões **Confirmar** e **Não está mais lá**
- Botão de reporte disponível durante navegação
- Banner no topo da tela de navegação ao se aproximar de alerta ativo (raio: 500m)

**Novo serviço Flutter:** `PoliceAlertService` — responsável por:
- Stream de alertas ativos na região visível do mapa
- `report(type, lat, lng)`
- `confirm(alertId)`
- `notThere(alertId)`

---

## Fase 2 — Proxy de roteamento no backend Go

### Problema atual

`HereRoutingService` no Flutter chama a HERE API diretamente. A chave `hereApiKey` está em `lib/config.dart` — qualquer pessoa que descompile o APK tem acesso.

### Solução

Flutter passa a chamar o backend Go. O backend chama HERE (ou TomTom como fallback). A chave HERE fica apenas no Secret Manager do Cloud Run.

### Contrato da API

**`POST /v1/route`** — autenticado com Firebase ID token

```json
// Request
{
  "origin":      { "lat": -23.5, "lng": -46.6 },
  "destination": { "lat": -23.6, "lng": -46.7 },
  "truck":       { "heightCm": 420, "lengthCm": 1400, "weightKg": 25000 }
}

// Response
{
  "polyline":    "encoded...",
  "distanceKm":  45.2,
  "durationMin": 52,
  "provider":    "here" | "tomtom",
  "fromCache":   true | false
}
```

`provider` e `fromCache` são informativos — o Flutter não precisa se importar com o valor.

### Estrutura do backend Go

Novo pacote `backend/routing/`:

```
routing/
  provider.go   — interface RoutingProvider { Route(ctx, req) (*RouteResult, error) }
  here.go       — implementa HERE Routing API v8
  tomtom.go     — implementa TomTom Routing API v1 (novo — não existe ainda no Go)
  cache.go      — sync.Map com TTL, chave = hash(origem 4dp + destino 4dp + perfil)
  handler.go    — orquestra: cache → HERE → fallback TomTom → 502
```

**Cache:**
- Storage: `sync.Map` em memória (stateless Cloud Run — cache não compartilhado entre instâncias, aceitável para o volume atual)
- Chave: hash SHA256 de `lat/lng` arredondados a 4 casas decimais (~11m precisão) + perfil do caminhão
- TTL: 2 horas

**Fallback:**
- HERE com timeout de 8s
- Se HERE retornar 5xx ou timeout → loga provider, tenta TomTom
- TomTom com timeout de 8s
- Ambos falham → HTTP 502 com body `{"error": "routing_unavailable"}`

### Mudanças no Flutter

- `HereRoutingService` → renomeado/substituído por `RoutingService`
- `RoutingService.calculateRoute()` chama `POST /v1/route` com Firebase ID token no header `Authorization: Bearer <token>`
- `RouteResult` ganha `String? provider` opcional — sem impacto na UI existente
- `config.dart`: `hereApiKey` removido após validação do proxy em produção
- `HereGeocodingService` não muda — geocoding continua direto

---

## Fase 3 — Compartilhar rota

### Fluxo

**Quem compartilha:**
1. Rota calculada → botão "Compartilhar" aparece no card de resultado no `MapScreen`
2. Flutter gera URL: `https://maps.google.com/maps?saddr=OLAT,OLNG&daddr=DLAT,DLNG`
3. Flutter monta mensagem WhatsApp:
   ```
   🚛 [label origem] → [label destino]
   [URL]
   
   Se tiver o Truck Router instalado, escolha ele no seletor de apps.
   ```
4. Abre share sheet do Android via `share_plus`

**Quem recebe:**
1. Clica o link no WhatsApp
2. Android mostra chooser: Google Maps / Waze / Truck Router
3. Escolhe Truck Router → app abre com origem e destino preenchidos
4. Escolhe Maps/Waze → abre normalmente no app escolhido

**Limitação conhecida:** se o receptor tiver Google Maps configurado como app padrão para URLs `maps.google.com`, o Android pode abrir direto sem mostrar o chooser. Comportamento do sistema, fora do controle do app — mitigado pela instrução no texto da mensagem.

### AndroidManifest.xml — novo intent filter

```xml
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

`autoVerify="false"` garante que nosso app apareça no chooser em vez de tentar se tornar handler padrão.

### Mudanças no Flutter

- **`geo_uri_parser.dart`:** extender para parsear formato `saddr=LAT,LNG&daddr=LAT,LNG` além do `geo:` existente — retorna origem + destino
- **`MapScreen`:** ao receber deep link com origem+destino, preencher ambos os campos (hoje só preenche destino)
- **Botão compartilhar:** apenas visível quando `RouteProvider.state == success`
- **Dependência:** verificar se `share_plus` está no `pubspec.yaml`; adicionar se necessário

---

## Ordem de implementação sugerida

```
Fase 1a: modelo + UI de novos tipos de restrição (weight, truck_ban)
Fase 1b: badge isVerified na UI
Fase 1c: police_alerts — backend (Firestore TTL, serviço Go se necessário)
Fase 1d: police_alerts — Flutter (PoliceAlertService, pins, sheet, banner navegação)
Fase 2a: interface RoutingProvider + implementação HERE no Go
Fase 2b: implementação TomTom no Go
Fase 2c: cache + handler + endpoint /v1/route
Fase 2d: Flutter — RoutingService aponta pro backend
Fase 3a: geo_uri_parser extendido + MapScreen com origem+destino
Fase 3b: intent filter no AndroidManifest
Fase 3c: botão compartilhar + geração de URL + share_plus
```

---

## Decisões técnicas registradas

| Decisão | Alternativa descartada | Motivo |
|---|---|---|
| Firestore TTL nativo para police_alerts | Cloud Function agendada | Zero infra extra, mesma semântica |
| Cache em memória (sync.Map) para roteamento | Redis / Firestore | Volume atual não justifica infra adicional |
| maps.google.com como formato do link compartilhado | Scheme customizado `truckrouter://` | Waze e Maps já suportam, sem app novo necessário para abrir |
| Geocoding permanece direto (não via proxy) | Proxy também para geocoding | Latência por keystroke inaceitável em 3G |
| Fotos fora do escopo | Evidência visual nas restrições | Nem Waze tem — complexidade de storage + moderação sem ROI |
