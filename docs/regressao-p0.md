# Checklist de regressão P0 — estressar ANTES de cada release

> Pedido do Márcio + Gilberto (2026-07-03): *"os mesmos erros voltam de forma
> diferente a cada versão."* Antes de rodar `release.ps1`, passar por esta lista
> e confirmar que nenhum dos top-10 P0 voltou. Um P0 aqui **bloqueia** o release.

Regra de ouro: **fix de sintoma não fecha o item.** Só marca como coberto quem
tem o gate verificável abaixo passando (unit, log de campo ou repro no Lockito).

Como estressar (setup padrão): Lockito com a rota real + `adb logcat` tethered
(Wi-Fi), e consulta ao `field_logs` (projeto **truck-router1**) pelo `event`.

---

## Os top-10 P0

### 1. Free-look "do nada" / marker azul travado no zoom
- **Sintoma:** câmera para de seguir sozinha (botão "Centralizar" aparece) sem o
  motorista tocar; ou marker azul congela no zoom e o recenter não pega.
- **Raiz:** `_onCameraMove` não distinguia o **próprio follow** (moveCamera a
  30fps) de um gesto — usava limiar de 40m contra `_animPos`, que corre à frente
  sob stall. 3 gatilhos: startup (default Brasília), catch-up pós-stall, refire
  do recenter. Fix definitivo: discriminador **espacial** (ring-buffer de alvos
  comandados) + guard de startup.
- **Fix:** v2.4.10 (ring-buffer). Antes: v2.4.5/2.4.7 (patches de sintoma).
- **Gate:** `flutter test test/screens/navigation_freelook_test.dart` verde **E**
  no `field_logs` os `freelook_enter` param de vir com `panM` 40–42 / `cause=zoom`
  `msProg=-1`. Repro Lockito: dirigir rápido + forçar stall → não pode entrar em
  free-look sem tocar na tela.

### 2. Tela cinza / crash no reroute
- **Sintoma:** tela fica cinza (platform view em branco) ao recalcular rota.
- **Raiz:** `RangeError` no `build` — ícones de radar dessincronizados no reroute.
  NÃO era ANR nem Impeller.
- **Fix:** v2.2.2 (+ Impeller off + throttle).
- **Gate:** forçar reroute no Lockito (sair da rota) 5× seguidas sem tela cinza;
  `field_logs` sem `error where=route_reroute*`.

### 3. Link de localização do WhatsApp não vira destino
- **Sintoma:** "Link não reconhecido: geo:LAT,LNG?q=endereço(Nome)".
- **Raiz:** `parseGeoUri` dava short-circuit no `q` textual e descartava as coords
  boas do path.
- **Fix:** v2.4.8. **Validado em campo pelo Gilberto (2026-07-03).**
- **Gate:** `flutter test test/utils/geo_uri_parser_test.dart` (inclui o link exato
  do print). `field_logs` sem `deeplink_unrecognized`.

### 4. Radar falso positivo (via paralela)
- **Sintoma:** alerta de radar que está na pista de sentido oposto/paralela.
- **Raiz:** proximidade sem checar direção do segmento.
- **Fix:** v2.2.0 (corredor perpendicular ao segmento, 22m). Viaduto ainda dispara
  (nenhuma fonte grátis dá direção em escala).
- **Gate:** rota que passa ao lado de uma via paralela com radar → não alerta.

### 5. Alerta de excesso em "storm"
- **Sintoma:** enxurrada de alertas de velocidade fora de área de risco.
- **Raiz:** alerta disparava em qualquer excesso.
- **Fix:** v2.4.0 (só em área de radar) + corredor de desvio 70m (anti-storm).
- **Gate:** trecho acima do limite fora de radar → silêncio; dentro de radar → 1 alerta.

### 6. Endereço de rodovia por km errado (~2km)
- **Sintoma:** destino "Rodovia X, km Y" caía ~2km fora.
- **Raiz:** HERE geocoding impreciso em rodovia por km.
- **Fix:** v2.4.1/2.4.2 (usa Google para esse caso).
- **Gate:** geocodar um "km" de rodovia conhecido e conferir < 200m.

### 7. "Rota recalculada" falso
- **Sintoma:** TTS/badge "rota recalculada" sem desvio real.
- **Raiz:** disparava em qualquer variação.
- **Fix:** v2.4.5 (só em desvio real).
- **Gate:** seguir a rota certinho no Lockito → nunca fala "recalculada".

### 8. GPS stream cai e congela a nav em silêncio
- **Sintoma:** app "morre" na nav sem erro visível.
- **Raiz:** `getPositionStream` sem `onError` — erro de GPS engolido.
- **Fix:** v2.4.9 (`FieldLog.error('gps_stream')`).
- **Gate:** `field_logs`: se aparecer `gps_stream`, investigar antes de soltar.

### 9. Auth cego apagava todos os sinais
- **Sintoma:** telemetria/Firestore paravam sem rastro (falha de login silenciosa).
- **Raiz:** `_ensureUser` engolia a exceção.
- **Fix:** v2.4.9 (loga `auth_signin` + rethrow).
- **Gate:** `field_logs` sem `error where=auth_signin` no boot.

### 10. Lag da seta / puck (device fraco)
- **Sintoma:** seta atrasada em relação ao carro (Adreno 610).
- **Raiz:** rebuild de 60fps + marker via method channel saturava a main thread.
- **Fix:** puck overlay fixo + follow por moveCamera + cap 30fps. Curva ainda em
  ajuste (bearing lerp reprovado em campo 2026-06-29).
- **Gate:** drive real liso; sem "derrapada" na curva.

---

## Rotina antes de `release.ps1`
1. `flutter analyze` limpo.
2. `flutter test` verde (inclui os gates unitários acima).
3. Repro no Lockito da rota do Gilberto cobrindo P0 #1, #2, #7.
4. Instalar a build e mandar pro Gilberto **só** depois de 1–3.
5. Pós-release: varrer `field_logs` da sessão dele pelos `event`/`where` dos gates.
