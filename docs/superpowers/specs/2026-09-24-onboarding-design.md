# Onboarding novo — spec (24/09/2026)

**Por quê:** o onboarding atual é uma tela (logo + frase + "Começar"). O Pedro viu o do Radarbot (6 telas ilustradas
animadas) e quer o nosso "tão brabo quanto", com identidade própria. Decisões tomadas com o Pedro nesta data.

## Decisões
1. **Apresentação + ação:** 5 telas de apresentação, 1 de cadastro do caminhão, 1 de permissões.
2. **Ilustração gerada por IA em camadas**, animada pelo Flutter. Sem Lottie/Rive (dependência nova só com decisão do Pedro).
3. **Telas e ordem** (copy aprovada):
   | # | Tela | Cena | Título / texto |
   |---|---|---|---|
   | 1 | Abertura | caminhão da marca, pista neon, noite | **Feito pra quem vive no trecho.** Rota, radar e pedágio pensados pro pesado. |
   | 2 | Rota | pórtico 4,20 m · 25 t · 5 eixos | **A rota que cabe no seu caminhão.** Altura, peso e eixos decidem o caminho, não o carro de passeio. |
   | 3 | Radar | radar na pista, seta do sentido | **Radar no seu sentido, no limite de pesado.** O da pista contrária não te incomoda. |
   | 4 | Pedágio | praça iluminada, R$ 28,50 | **Pedágio já com o valor do seu eixo.** Antes de sair, você sabe quanto vai gastar. |
   | 5 | S.O.S. | dois caminhões no acostamento, um com pisca | **Pediu ajuda? Quem está perto recebe.** Buzina, voz e a distância até você. |
   | 6 | Seu caminhão | formulário | altura, comprimento, peso, eixos, padrão preenchido |
   | 7 | Permissões | celular na cabine | localização, notificação, bateria; uma linha do porquê em cada |
4. **Permissão negada ou pulada nunca segura:** "Começar" libera sempre; pendência reaparece no mapa como hoje.

## Fluxo
- `PageView` com 7 páginas, indicador de bolinhas, "Pular" nas páginas 1–5 (→ página 6), "Próxima"; página 7 tem "Começar".
- `onboarding_done` (prefs) continua a chave; quem já passou (ou restaurou backup) não vê. Não relitigar: pedir
  permissão no onboarding não substitui o pedido do boot, porque o restore pula o onboarding.
- App morto no meio: recomeça da página 1; o caminhão só é salvo ao confirmar a página 6.

## Cena animada (páginas 1–5)
`Stack`: (a) gradiente da marca (`#0e1720` → `#050a14`, brilho verde `#5dff3c` no topo); (b) **pista neon por
`CustomPainter`**, tracejados correndo em loop (`AnimationController` ~1,6 s), a mesma em todas as telas; (c) caminhão
(imagem recortada) com balanço senoidal de 2–3 px; (d) elemento da dor (imagem recortada) entrando por deslize
400 ms `easeOutCubic` ao abrir a página; (e) título e texto com fade + subida 300 ms. `MediaQuery.disableAnimations`
→ tudo estático. Ilustração em `Expanded` com altura mínima 40% da tela e teto 52%; texto nunca clipa (rola se precisar).

## Imagens
- `assets/onboarding/`: `caminhao.webp` + `cena{2..5}.webp` (elemento da dor), 1080 px de largura, WebP lossy q80.
- **Orçamento: 2 MB somados** (APK já tem 63 MB); teste reprova se passar.
- Geração: prompts no estilo da arte aprovada (`docs/marca/README.md`, memória `project_app_nome_logo`), elemento em
  fundo preto liso pra recorte por chroma. Plano B se o recorte sair com halo: cena inteira em uma imagem por tela,
  só com balanço e parallax.
- **Até as imagens chegarem:** todas as telas usam a pista desenhada + o caminhão da arte existente (`assets/brand/`).
  Trocar arquivo não mexe em código.

## Página 6 — Seu caminhão
Reaproveita o formulário de "Editar caminhão" (mesmos campos e validação) pré-preenchido com o padrão
(4,20 m · 14,00 m · 2,60 m · 25.000 kg · 5 eixos). Confirmar salva no caminhão ativo pelo mesmo caminho do espelho.
Modelo/cor/placa ficam fora (é a ficha do S.O.S., opcional, tem lugar próprio).

## Página 7 — Permissões
Cartões com estado **Concedida / Pendente** e botão por item:
- **Localização:** pede "durante o uso" (`geolocator`); concedida → segundo passo "Permitir sempre" abre os Ajustes do
  app. Ao pedir aqui, grava `location_asked_install` (o mesmo do `map_screen`) → o boot **não** pede de novo
  (segunda negação no Android vira permanente).
- **Notificação:** `FirebaseMessaging.requestPermission()` (Android 13+); abaixo disso já vem concedida.
- **Bateria:** isenção via o caminho que já existe pro foreground service (`flutter_foreground_task`).
- **Xiaomi/MIUI:** linha extra "Início automático" com botão pra tela do sistema; não dá pra pedir, só orientar.
Sem dependência nova: tudo com o que já está no `pubspec`.

## Telemetria (`FieldLog.event`, nunca em hot path)
`onboarding_step {i}`, `onboarding_skip {from}`, `onboarding_truck {changed}`, `onboarding_perm {kind, result}`,
`onboarding_done {ms}`. Responde: quem pula e onde, quem cadastra o caminhão de verdade, qual permissão nega.

## Testes
- Puros: destino do "Pular" por página; estado dos cartões a partir das permissões; `shouldAskLocationOnBoot(perm,
  alreadyAsked=true)` é falso depois do onboarding pedir (o teste que reprova se a segunda chance for gasta).
- Widget: percorre as 7 páginas, "Pular" na 3 cai na 6, "Começar" grava `onboarding_done`.
- Asset: soma de `assets/onboarding/*.webp` ≤ 2 MB.

## Fora de escopo
Paywall, Lottie/Rive, iPhone, pedir permissão de novo a quem restaurou backup, modelo/cor/placa no onboarding, clima
e ponte baixa como telas próprias (ponte entra na fala da tela 2).

## Pré-mortem
- Segunda negação permanente → `location_asked_install` compartilhado com o mapa.
- MIUI mata em segundo plano mesmo com tudo concedido → início automático é orientação, não promessa; tela 7 não afirma "vai funcionar".
- APK pesado → orçamento com teste.
- Recorte feio → plano B de cena inteira.
- O que me faria estar errado: motorista pular tudo (telemetria `onboarding_skip` mostra) ou ninguém mudar o caminhão padrão (`onboarding_truck changed=false` em massa) — aí a tela 6 vira obrigatória de olhar, não de preencher.
