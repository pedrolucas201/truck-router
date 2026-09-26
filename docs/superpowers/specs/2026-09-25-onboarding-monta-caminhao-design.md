# Onboarding "Monta o teu caminhão" — spec (25/09/2026)

**Por quê:** o onboarding de 24–25/09 (6 telas de história + cadastro + permissões) é um tour de funcionalidades em
carrossel, o formato com pior evidência: o NN/g mostrou que muita gente pula e quem lê acha as tarefas *mais difíceis*;
tours passivos de 7+ passos terminam em 16% (Chameleon, 550M eventos). O que funciona é o usuário fazer a coisa e ver
o próprio resultado (Duolingo: adiar o cadastro pra depois da 1ª lição ≈ +20% DAU). Todo concorrente vende
funcionalidade e cobra o que importa (RoadPro cobra o limite de caminhão; Sygic cobra mapa; Trucker Path exige login);
a dor nº 1 do caminhoneiro é roubo/segurança (64,6% CNT 2019; 46% já teve carga roubada, CNTA 2024), média de 46 anos,
37% com ensino médio, cultura de áudio. Pesquisa completa (4 frentes, com fontes) resumida no fim.

**Decisão do Pedro (25/09):** "topa" — trocar o tour pelo fluxo em que o motorista monta o caminhão dele e o app
responde com o trecho real dele.

## Princípios (não relitigar sem dado novo)
1. **Toda tela tem uma ação do motorista** e mostra o efeito dela na hora. Nenhuma tela só de leitura.
2. **O caminhão do motorista é o protagonista**: o que ele escolhe aparece na cena, não um caminhão genérico.
3. **O resultado é real e offline**: radares e restrições do asset em volta dele, com o limite de caminhão. Nada de
   número inventado, nada de rede no caminho.
4. **Cada permissão é pedida onde ela se paga**, com o motivo falado. Negar nunca trava.
5. **Voz + texto curto**: cada tela tem uma frase que aparece e é falada pela voz do guia. Texto sempre na tela; a voz
   complementa.
6. **Honestidade do verbo**: o asset **avisa**; quem **desvia** é a rota da HERE. Tela nunca promete o que o dado não faz.

## Fluxo (6 páginas)

| # | Página | Ação do motorista | O que ele vê/ouve | Botões |
|---|---|---|---|---|
| 0 | Chegada | — (1 toque) | fundo cinematográfico, o caminhão entra e o alien acena. Voz: **"Oi! Eu sou seu parceiro no trecho. Grátis de verdade, sem cadastro."** | **Bora** |
| 1 | Garagem | escolhe o tipo | 5 cartões grandes (toco, truck, carreta, bitrem, rodotrem); o caminhão da cena troca na hora, eixos contam, o alien reage. Voz: **"Com que caminhão você roda?"** Link "Ajustar medidas" abre o formulário atual (altura, comprimento, peso, eixos) já preenchido pelo tipo | **É esse** |
| 2 | Onde você está | permite localização | cena de mapa neon esperando. Voz: **"Deixa eu ver onde você está pra te mostrar o seu trecho."** | **Mostrar meu trecho** · Escolher cidade |
| 3 | Seu trecho (o "aha") | — | radar de varredura neon centrado nele com os pontos reais (ver abaixo). Voz lê o resumo | **Próxima** |
| 4 | Ajuda na estrada | permite notificação | cena do S.O.S. Voz: **"Se der problema, quem está perto recebe o seu pedido. E você recebe o deles."** | **Ativar ajuda** · Agora não |
| 5 | Bora | — | amanhecer, o caminhão arranca com o alien acenando, ícone + "No Trecho". Voz: **"Bora pro trecho?"** | **Começar** |

- **"Agora não" / pular** existe em 1–4 e avança sem gravar nada daquela etapa. Nunca há bloqueio.
- Indicador de progresso fino no topo (6 segmentos), não bolinhas.
- **Mudo:** ícone de alto-falante no canto superior direito, visível em todas as páginas; estado salvo em prefs.
- Tom: **"você"** (Pedro, 25/09). Falas acima são a copy proposta; o Pedro revisa no device.

## Página 1 — Garagem

**Tipos (pré-preenchem o `TruckProfile`)** — limites da Lei da Balança (Res. CONTRAN 210/2006):

| Tipo | Eixos | PBT/PBTC | Comprimento | Altura | Fonte / status |
|---|---|---|---|---|---|
| Toco | 2 | 16.000 kg | 10,00 m | 4,40 m | 6 + 10 t por eixo; ≤ 14 m |
| Truck | 3 | 23.000 kg | 14,00 m | 4,40 m | 6 + 17 t; ≤ 14 m |
| Carreta | 5 | 41.500 kg | 18,60 m | 4,40 m | 6 + 10 + 25,5 t; **conferir** comprimento (fontes dizem 18,60 e 19,30) |
| Bitrem | 7 | 57.000 kg | 19,80 m | 4,40 m | PBTC 57 t |
| Rodotrem | 9 | 74.000 kg | 25,00 m | 4,40 m | 74 t **com AET**; comprimento até 30 m com AET |

- ⚠️ **Os pesos por tipo são derivados dos limites por eixo e têm que ser conferidos na tabela oficial antes de codar.**
  Um resumo automático do Guia do TRC deu 57 t pra carreta de 5 eixos, o que contradiz a conta por eixo (41,5 t).
- **Altura padrão 4,40 m (o teto legal), não 4,20.** Princípio do projeto: falso alarme é passável, sem alarme é multa.
  Altura maior → mais viaduto avisado/evitado, nunca menos. Decidido com o Pedro em 25/09.
- Escolher um tipo **não grava** até "É esse"; grava pelo caminho atual (`caminhaoMudou` + `saveProfile`, espelho).
- "Ajustar medidas" reaproveita os `_campo` atuais (mesma validação).
- Cena: o caminhão vivo por cima do fundo. **Fase 1** usa o sprite atual escalado em comprimento + selo de eixos;
  **fase 3** troca por sprites próprios (ver "Arte").

## Página 3 — Seu trecho (o "aha")

**Cálculo (puro, testável, offline):** a partir da posição e do caminhão escolhido, varrer o cache de
`RadarService.load()` e `PhysicalRestrictionService.load()` num raio de 30 km (bbox + `RadarService.haversine`).
- **Radares:** só `type` contendo "Radar" (**19.223 das 45.155 linhas são lombada**; sem o filtro o número infla ~2×).
  Limite de caminhão por `truckRadarLimit(speedKmh, officialTruckLimit: truckLimitOff)`.
- **Viadutos:** `type == 'maxheight'` e `value < altura do caminhão`.
- **Resumo (3 casos):**
  1. Há viaduto baixo: *"Num raio de 30 km: N radares e M passagens mais baixas que o seu caminhão. O app avisa cada uma."*
  2. Zero viaduto (interior; Cuiabá e Uberlândia dão 0): *"O radar mais perto tá a X km. Pro seu caminhão o limite é Y."*
     (Y é o diferencial: ninguém mais sabe o limite de pesado.)
  3. Zero radar em 30 km (MT rural): expande pra 100 km; se ainda zero, *"Aqui tá tranquilo. Quando aparecer, eu aviso."*
- **Visual:** radar de varredura neon (CustomPainter), o caminhão no centro, radares em verde, viadutos em vermelho,
  posição por rumo e distância. **Sem GoogleMap** no onboarding (platform view pesada; histórico de tela cinza).
- **Nome da via** só aparece se `roadName` existir. Restrição tem contaminação conhecida (heliponto, prédio, trevo):
  por isso o texto conta e avisa, não afirma "você não passa na rua X".
- **Custo:** o parse do CSV de radar (2,3 MB) roda num isolate (`compute`) disparado na página 0; a varredura é
  ~57 mil comparações, poucos ms. Estimado, **medir no Redmi**.
- **Localização negada** → "Escolher cidade": lista curta das capitais + cidades-polo; mesmo cálculo no centro dela.

## Permissões
- **Localização (página 2):** `markLocationAsked()` **antes** de pedir, igual ao onboarding atual e ao boot do mapa
  (segunda negação no Android vira permanente). Só "durante o uso". "Permitir sempre" sai do onboarding: vai pro
  início da primeira navegação, onde ele se explica sozinho.
- **Notificação (página 4):** contexto S.O.S.; `FirebaseMessaging.requestPermission()` pelo `PermissoesApi` atual.
- **Bateria e início automático (Xiaomi):** saem do onboarding. A bateria já é pedida antes do foreground service na
  primeira navegação (memória `project_background_permission`). O início automático vira uma linha na página 5
  **só em Xiaomi**, com o botão "Abrir" atual.
- Tudo com o que já está no `pubspec`. Nenhuma dependência nova além do `video_player` (já adicionado no experimento).

## Fundo e arte
- **Fundo em vídeo, caminhão vivo por cima** (recomendação da frente de tecnologia): o `filme.py` ganha a opção de
  renderizar **sem o herói** e em **loops de 6 s por cena** (cidade à noite, garagem, mapa neon, S.O.S., amanhecer),
  com emenda por crossfade no fim. H.264 720p, ~1 MB cada.
- O caminhão escolhido, as rodas girando e o alien acenando são o `_Sprite` atual (sai do `cena_onboarding.dart`).
- **Pôster WebP** de cada fundo enquanto o vídeo inicializa e quando "reduzir animações" está ligado.
- **Sprites por tipo (fase 3, Pedro gera no Gemini):** um **cavalo mecânico** e um **semirreboque** separados, em
  magenta, cabine pra esquerda, mesmo estilo do herói. O código compõe: carreta = cavalo + 1 semi, bitrem = cavalo +
  2 semis, rodotrem = cavalo + semi + dolly + semi. Toco e truck usam o herói atual em dois comprimentos.
- **Orçamento de assets do onboarding sobe de 2 MB pra 7 MB** (WebP + MP4). O teste passa a somar os dois. APK +~5 MB.
  **Decisão do Pedro.**

## Voz
- `FlutterTts` próprio do onboarding com `VoiceSettings.apply` (usa a voz escolhida, se houver). Uma fala por página ao
  entrar; troca de página cancela a anterior (`stop()`). Falha do TTS nunca trava: o texto está na tela.
- Mudo salvo em prefs (`onboarding_voz_muda`).

## O que sai
- As 6 telas de história (`kTelasOnboarding`), o `CenaOnboarding` ao vivo e o experimento `ONB_FILME`
  (`_FilmeOnboarding`). O git guarda. A copy aprovada em 24/09 e os pedidos do Beto de 25/09 deixam de existir nessa
  forma; a coruja, o ET no baú e o velocímetro 88→80 sobrevivem no filme de loja/redes.
- A página de permissões com 4 cartões.

## Telemetria (`FieldLog.event`, nunca em hot path, nunca coordenada)
`onboarding_step {i}`, `onboarding_skip {from}`, `onboarding_truck {tipo, changed, ajustou}`,
`onboarding_perm {kind, result}`, `onboarding_aha {raio_km, radares_faixa, viadutos_faixa, caso, cidade_manual}`,
`onboarding_voz {muda}`, `onboarding_done {ms}`. Faixas (0, 1–10, 11–100, 100+), nunca o número exato nem o lugar.

## Testes
- Puros: tipo → `TruckProfile` (números da tabela, depois de conferidos); cálculo do "aha" com fixture (filtra
  lombada, compara altura, escolhe o caso 1/2/3, expande raio); destino do "Agora não" por página;
  `locationAskedThisInstall` segue valendo (o onboarding carimba antes de pedir).
- Widget: percorre as 6 páginas com permissões falsas, "Agora não" em todas chega no "Começar" e grava
  `onboarding_done`; escolher "bitrem" + "É esse" grava 7 eixos.
- Asset: soma de `assets/onboarding/*` ≤ 7 MB.
- Device (obrigatório antes de dizer pronto): instalação limpa (`pm clear`) no Redmi, fluxo completo com localização
  concedida e negada, `--profile` com timeline do vídeo + sprite, e o `onboarding_aha` chegando no field_logs.

## Fases
1. **Fluxo + garagem + aha + voz**, com o fundo atual (cena ao vivo) e o sprite atual escalado. Já entrega o estalo.
2. **Fundos em vídeo sem herói** (loops) + pôster + reduzir animações.
3. **Sprites por tipo** (cavalo + semirreboque) quando o Pedro gerar.

## Fora de escopo
Login, paywall, modelo/cor/placa (ficha do S.O.S., lugar próprio), iPhone, efeitos sonoros e háptico (sem evidência
sólida; o motorista está em público), 3D ao vivo, Rive (exportação exige plano pago), ponte baixa como cena.

## Pré-mortem
- **Motorista pula tudo** → "Agora não" leva ao mapa com o caminhão padrão; `onboarding_skip` mostra onde. O padrão
  conservador (4,40 m) protege quem pula.
- **Tipo com número errado** → rota errada. Mitigação: tabela conferida na fonte antes do código, teste trava os
  valores, "Ajustar medidas" sempre à mão.
- **"Aha" vazio ou falso** → os 3 casos cobrem zero; contaminação de restrição não vira afirmação sobre uma rua.
- **TTS mudo ou lento no primeiro uso** → texto na tela; a fala é bônus.
- **Vídeo engasga em aparelho fraco** → pôster + medir; fase 1 nem usa vídeo.
- **Restore de backup pula o onboarding** → igual hoje: `onboarding_done` restaurado; o boot do mapa segue pedindo
  localização pela regra do `location_asked`.
- **O que me faria estar errado:** `onboarding_done` cair em relação ao fluxo atual, ou opt-in de localização não
  subir. A comparação é pelo field_logs das duas versões (hoje: `onboarding_step` e `onboarding_perm` já existem).

## Decisões
- ✅ Orçamento de assets 7 MB (APK +~5 MB) — Pedro, 25/09.
- ✅ Tom "você" — Pedro, 25/09.
- ✅ ~~Voz ligada com mudo~~ → **sem voz no onboarding** (Pedro no device, 25/09: "melhor sempre deixar mudo, tira essa opção de som"). As falas da tabela ficam só como texto.
- ✅ Sprites de cavalo e semirreboque: Pedro gera no Gemini (prompts abaixo) — 25/09.
- ✅ **Altura padrão pra quem pula a garagem: 4,40 m** (teto legal; Pedro aceitou a recomendação, 25/09). Falso
  alarme incomoda, sem alarme bate. Quem escolhe tipo ou ajusta usa o próprio valor. Constante única, reversível.
- Sprites (25/09): `cavalo.jpg` aprovado (cabine igual à do herói, quinta-roda, 3 eixos). `semirreboque.jpg`
  **refazer**: veio com cambão/olhal (é reboque, não semirreboque) e pés de apoio baixados. Contagem visual de eixos
  bate com os tipos: carreta = cavalo 3 + semi 2 = 5; bitrem = 3 + 2 + 2 = 7; rodotrem = 3 + 2 + dolly 2 + 2 = 9.

## Prompts dos sprites (Gemini, chat "Neon Alien Truck Driver Icon", anexar `docs/marca/onboarding/heroi.jpg`)
Cavalo mecânico:
> Same style, colors and neon edge light as the attached truck. Flat 2D side view of a white semi-truck TRACTOR UNIT
> only (cab + chassis + fifth wheel, no trailer), cab facing LEFT, same cab design as the attached image, the green
> alien driver in the side window. 3 axles. Isolated on a solid flat magenta background (#FF00FF), no ground, no
> shadow, no text.

Semirreboque:
> Same style as the previous images. Flat 2D side view of a dark box SEMI-TRAILER only (no tractor), front end facing
> LEFT with the kingpin, 3 rear axles, the same neon green frame and the same neon alien face logo on the side as the
> attached truck. Isolated on a solid flat magenta background (#FF00FF), no ground, no shadow, no text.

## Fontes da pesquisa (25/09)
NN/g onboarding e tutoriais mobile; Chameleon (product tours); First Round Review (Duolingo); Adapty (testes de
onboarding); Finch (Pratt IXD); Incognia (opt-in de localização); Android usage-notes e location runtime; Radarbot
planos; Sygic/Adapty paywall library; fórum do Waze (sem caminhão); CNT 2019; CNTA 2024; Canaltech (áudio no
WhatsApp); Rive pricing; flutter_scene (pub.dev); Guia do TRC e Res. CONTRAN 210/2006 (limites). URLs no histórico
da sessão de 25/09 e no HANDOFF.
