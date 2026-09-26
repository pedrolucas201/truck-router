# Onboarding — como mudar sem quebrar

Guia de manutenção do onboarding "Monta o seu caminhão" (26/09/2026). Decisões e porquês:
`docs/superpowers/specs/2026-09-25-onboarding-monta-caminhao-design.md`. Aqui é o **onde mexer**.

## O fluxo hoje (6 páginas)

| # | Constante | Página | Ação do motorista | Cena atrás |
|---|---|---|---|---|
| 0 | `kPagChegada` | "Oi! Sou seu parceiro no trecho." | Bora | cidade à noite, caminhão entra pela esquerda |
| 1 | `kPagGaragem` | "Com que caminhão você roda?" | escolhe tipo, − / + altura, "Ajustar medidas", É esse | pátio; ao escolher, passa numa praça com o valor pelo eixo |
| 2 | `kPagLocal` | "Deixa eu ver onde você está." | Mostrar meu trecho / Escolher cidade | radar de varredura procurando |
| 3 | `kPagTrecho` | resumo real (radares e passagens baixas em 30 km) | Próxima | radar com os pontos reais |
| 4 | `kPagAjuda` | S.O.S. | Ativar ajuda (notificação) | sertão, o caminhão para atrás de um parado |
| 5 | `kPagBora` | "Bora pro trecho?" + promessa da 1ª rota | Começar (+ permitir sempre / início automático Xiaomi, opcionais) | amanhecer, alien acenando |

Depois do onboarding: **cartão de estreia** na 1ª rota com pedágio/radar/desvio (`widgets/map/estreia_sheet.dart`, uma vez só,
prefs `estreia_vista`). É ele que cumpre a promessa da página 5.

## Onde mexer, por tipo de mudança

| Quero mudar... | Arquivo | Onde |
|---|---|---|
| **Texto** de uma página | `lib/screens/onboarding_screen.dart` | `_pagina0`, `_paginaGaragem`, `_paginaLocal`, `_paginaTrecho`, `_paginaAjuda`, `_paginaBora` |
| **Ordem / número de páginas** | `lib/widgets/onboarding/onboarding_logic.dart` | `kPag*`, `kTotalPaginas`, `cenaDaPagina`, `mostraVarredura`, `pularDestino`; e a lista `children:` do `PageView` na tela |
| **Tipos de caminhão** (nome, eixos, peso, comprimento) | `onboarding_logic.dart` | `enum TipoCaminhao`. Teste trava os valores: mudou, atualiza `onboarding_logic_test.dart` |
| **Altura padrão** (hoje 4,40, teto legal) | `lib/models/truck_profile.dart` | `kAlturaPadraoCm` (vale pro app todo) |
| **Faixa / passo do − / + de altura** | `onboarding_logic.dart` | `ajustaAltura` (3,00–4,80, 5 cm) |
| **Valor do pedágio de exemplo** | `onboarding_logic.dart` | `kTarifaExemploPorEixo` (ilustrativo, R$ 9,50/eixo) e `pedagioExemplo` |
| **Texto do "seu trecho"** (3 casos) | `lib/widgets/onboarding/trecho.dart` | `ResumoTrecho.titulo` / `.texto`. Nunca prometer "desvia": o asset **avisa** |
| **Raio / o que conta como radar** | `trecho.dart` | `calcularTrecho` (30 km, expande a 100), `ehRadarDeVelocidade` (lombada e semáforo com câmera NÃO) |
| **Cidades pra quem nega localização** | `onboarding_logic.dart` | `kCidades` |
| **Visual do radar de varredura** | `lib/widgets/onboarding/radar_varredura.dart` | `_Painter` |
| **Cenário de uma página** (hora do dia, prédios, morros, cactos...) | `lib/widgets/onboarding/cena_onboarding.dart` | `_Mundo.de(Cena)` |
| **Movimento do caminhão** (entra, para, freia na praça) | `cena_onboarding.dart` | `_velocidade()` por `Cena` |
| **Evento desenhado** (placa de km, praça, S.O.S.) | `cena_onboarding.dart` | `_placaKm`, `_pedagio`, `_sos`; selos em `_FrentePainter._eventos` |
| **Sprites** (caminhão, alien acenando, parado) | `assets/onboarding/*.webp` | gerar no Gemini em magenta e recortar com `docs/marca/onboarding/recorta.py` (raiz `maps api`) |
| **Permissões** pedidas | `onboarding_screen.dart` | localização em `_mostrarMeuTrecho` (carimba `markLocationAsked` ANTES de pedir), notificação em `_ativarAjuda`; opcionais na `_paginaBora` |
| **Cartão de estreia** | `lib/widgets/map/estreia_sheet.dart` | `linhasEstreia` (texto), `mostrarEstreiaSeFor` (quando) |

## Regras que não podem quebrar (e o teste que trava)

- **Pular nunca grava caminhão** e nunca pede permissão → `test/screens/onboarding_flow_test.dart`.
- **Instalação limpa**: garagem sem nada marcado, "É esse" desligado até escolher → mesmo teste.
- **Caminhão atual igual a um tipo** marca o tipo; medidas próprias viram cartão com o nome dele → `onboarding_logic_test.dart` (`tipoIgual`, `nomeDoAtual`).
- **"Padrão" vira o nome do tipo**, nome do motorista nunca é trocado → `nomeDoCaminhao`.
- **Localização**: carimbar `markLocationAsked()` antes de pedir (2ª negação no Android é permanente; o boot do mapa respeita a marca) → teste `shouldAskLocationOnBoot`.
- **"Seu trecho"**: lombada não conta, viaduto compara com a altura DELE, texto sem "desvi" → `onboarding_logic_test.dart` (grupo "seu trecho").
- **Sem voz** no onboarding (Pedro, 25/09). Não religar sem ele.
- **Sem "grátis"** em texto nenhum: o app não será 100% grátis (memória `project_app_nao_gratis`).
- **Espelho do caminhão**: `saveProfile` só quando `caminhaoMudou` ou o nome mudou; confirmar "O meu" sem mudar não escreve.

## Telemetria (field_logs)

`onboarding_step {i}`, `onboarding_skip {from}`, `onboarding_truck {tipo, changed, ajustou}`, `onboarding_perm {kind, result}`,
`onboarding_aha {raio_km, radares, viadutos, caso, cidade_manual}` (faixas, nunca coordenada), `onboarding_done {ms}`,
`estreia_vista {pedagios, radares, desvios}`. É com isso que se decide mudar o fluxo, não com opinião.

## Ver no device (receita)

```
flutter build apk --release --dart-define-from-file=dart_defines.json --dart-define=APP_VERSION=trunk-X
adb install -r "C:\Users\PC\Documents\maps api\truck_router\build\app\outputs\flutter-apk\app-release.apk"
# app aberto: ☰ (976,198) → Configurações (540,1140) → Ver apresentação (300,2239); botão principal em (540,2196)
adb shell screenrecord --time-limit 30 --size 720x1600 /sdcard/x.mp4   # vídeo pra ver animação
```
O adb sem fio do Redmi cai em quase todo build: conferir `adb devices` e a data do APK antes de instalar.

## Material de marca (repo raiz `maps api`)

`docs/marca/onboarding/`: prompts dos sprites, `recorta.py`, `filme.py` (filme de 36 s renderizado por código, pra loja
e redes; NÃO está no app), `cavalo.jpg` (aprovado, fase 3), `mock_ponte_baixa.png` (reprovado: ponte lateral lê como colisão).
