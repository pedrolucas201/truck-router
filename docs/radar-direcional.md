# Radar da pista contrária alerta errado

**Resumo (o quê):** quando existe um radar na pista de quem vem no sentido
contrário, o app às vezes alerta como se o radar fosse o do motorista. A causa
é que o nosso radar é só um ponto no mapa — ele não sabe pra qual sentido
"olha". Pra resolver de verdade, cada radar precisa ter uma direção.

---

## Por que acontece (o problema real)

O dado do radar é um ponto pelado: `lat, lng, tipo, velocidade`. Sem direção.
Quando duas pistas opostas estão a poucos metros (canteiro estreito) e o GPS
erra ~10 m, não há como a geometria decidir se o radar é do seu lado ou do
lado de quem vem. Por isso mexer no "corredor" (distância que conta como
pertinho) é gangorra: aperta pra matar o oposto → começa a perder radar
legítimo do mesmo lado em curva/via larga.

Waze/Maps não têm esse problema porque o radar deles **já vem com o sentido
que fiscaliza** (e é casado à via direcionada). Aí é trivial suprimir o da
contramão.

## O que foi verificado (2026-07-07)

- **Nossa CSV (`assets/maparadar.csv`)**: 3 campos, sem direção. Confirmado no parser (`radar_service.dart`).
- **Fonte MapaRadar exporta direção?** O formato iGO tem colunas `DirType` +
  `Direction`. Baixei um export iGO real do Brasil (19.690 pontos) e **contei:
  100% vêm `DirType=0, Direction=0`** — a coluna existe mas está totalmente
  vazia. **A fonte grátis não resolve.** (hipótese do "fix barato" descartada por dado)
- OSM tem etiqueta de direção em radar, mas cobertura BR é fraca — só complemento.

## Caminhos possíveis (nenhum é de graça)

1. **Deduzir a direção pela estrada (offline, uma vez).** Encaixar cada ponto na
   via (OSM/HERE); se a via é separada por sentido (rodovia com canteiro),
   atribuir o rumo dela; se é mão dupla, deixar sem direção. Mata o caso mais
   comum (rodovia com canteiro), custo zero em runtime, sem lib nova. Não
   resolve mão dupla estreita.
2. **Crowd-source o rumo (modelo Waze).** Gravar o heading de quem passa/descarta
   o radar; após N passagens o radar ganha um sentido. Resolve tudo, escala,
   encaixa na infra Firestore existente (`radars` + `radar_dismissals`). Maior esforço.

## Recomendação

Começar por **(1) deduzir da estrada** — melhor custo-benefício, ataca o caso
mais frequente. **(2) crowd-source** entra por cima depois pra cobrir o resto.
Parar de calibrar o corredor (não resolve, só troca o erro de lugar).

## Prioridade

Depois do reroute (P0). Não é trabalho de agora — este doc registra a análise
pra decidir com calma entre (1) e (2).
