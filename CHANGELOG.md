# 📋 Changelog — RS50H Thermal Controller

Todos os lançamentos notáveis deste projeto serão documentados aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [Unreleased]

### Planejado
- Testes em bancada com motor hoverboard 24V real (sessão de carga prolongada)
- Calibração fina da curva PWM vs temperatura
- Suporte opcional a sensor DS18B20 (1-Wire) como alternativa ao NTC
- Plugin SimHub oficial validando token UDP (HMAC FNV-1a)

---

## [1.0.1] — 2026-05-21

### 🐛 Correções de Bug

#### BF-5 — RPM sempre zero na Dashboard

Firmware não enviava os campos `rpm` / `rpm_src` no payload JSON. Corrigido: RPM agora é
estimado por duty (quando `PIN_FAN_TACH = -1`) ou lido via ISR de interrupção (quando
`PIN_FAN_TACH >= 0`). Dashboard exibe `0 RPM / IDLE` quando PWM=0 — comportamento correto.

> **Nota:** fans de 4 pinos possuem velocidade mínima de hardware (~200–400 RPM) mesmo
> com PWM=0 comandado. O firmware comanda 0% corretamente; a rotação residual é comportamento
> do controlador interno do fan, não do firmware.

#### BF-6 — LEDs WS2812: termômetro progressivo

5 LEDs em cor sólida desperdiçava o hardware. Novo comportamento:

- **Termômetro progressivo:** 0–5 LEDs acesos em escala 0 → `g_tCrit`
- Cor reflete estado FSM (azul/verde/âmbar/vermelho)
- CRITICAL: pisca vermelho (300 ms on/off)
- Falha NTC: pulsa magenta (500 ms on/off)

### ✨ Melhorias

#### Dashboard — compatibilidade cross-browser

- `fetch()` → `XMLHttpRequest` (IE11 / Safari < 10.1)
- `Promise` → callbacks (elimina dependência de Promise)
- `min()` CSS → fallback px + media query (IE11)
- `clamp()` CSS → fallback px antes da declaração (IE11)
- Prefixos `-ms-` adicionados onde necessário (já havia `-webkit-`)
- `touch-action: pan-y` no scrollbar do log (iOS/Android)
- `-webkit-overflow-scrolling: touch` no log (iOS momentum scroll)
- Breakpoint extra para 320 px (iPhone SE geração 1)

#### Dashboard — log de RPM

Entrada de log gerada quando RPM muda ≥ 50, e também quando fan entra em IDLE (RPM → 0).

### 🔧 Interno

- `JSON_BUF_SZ`: 320 → 384 bytes para acomodar campos `rpm` / `rpm_src`
- Footer e badge de versão do dashboard atualizados para v1.0.1

**Payload WS v1.0.1:**
```json
{"t":52.3,"pwm":62,"rpm":620,"rpm_src":"est","state":"WARMING",
 "relay":false,"ntc":true,"ntc_faults":0,"heap":234567,"uptime":3600,
 "fw":"1.0.1","hw":"RS50H","cfg":{"fan_on":40,"warn":60,"crit":68,"rest":58}}
```

---

## [1.0.0] — 2026-05-19

### 🎉 Primeira Release Pública Estável — Hoverboard Motor Edition

Fork e rebranding do projeto `rs50-thermal-controller` (v3.3.13) → **RS50H v1.0.0**.
Mesma topologia elétrica, firmware endurecido e identidade visual nova.

**Status de validação:** firmware compilado com `arduino-cli 1.1.1` + `esp32:esp32@2.0.14`
e gravado com sucesso no ESP32-S3-Zero via USB-CDC (porta COM5). Sem motor 24 V real
ainda — pendente em `CONTEXT.md`.

### 🐛 Correções de Bug

#### BF-1 — WDT reboot com segundo cliente WebSocket (loopTask bloqueado)

**Causa:** `esp_task_wdt_reset()` era chamado apenas no topo de `loop()`.
`ArduinoOTA.handle()`, `g_http.handleClient()` e `g_ws.loop()` podiam bloquear
individualmente por mais de `WDT_TIMEOUT_S` segundos durante handshakes lentos,
fazendo a `loopTask` parar de resetar o WDT e o ESP32-S3 reiniciar com
`task_wdt: loopTask`.

**Correção:** `esp_task_wdt_reset()` inserido imediatamente após cada um dos três
handlers bloqueantes. `WDT_TIMEOUT_S` aumentado de `8` para `15 s` para dar margem
ao stack WiFi do ESP32-S3 sob carga simultânea de conexões OTA + HTTP + WS.

#### BF-2 — `ntcFailSafe` dead code: período de graça nunca atuava

**Causa:** O bloco `if (ntcFailSafe && newState < ST_WARNING)` nunca executava porque
`nextState()` já retorna `ST_CRITICAL` para `temp=NaN` — e `ST_CRITICAL > ST_WARNING`,
então a condição era sempre `false`. O período de graça de 5 s (10 ciclos de 500 ms)
era completamente ignorado.

**Correção:** Lógica invertida corretamente. Durante os primeiros
`NTC_FAULT_FAIL_SAFE_CYCLES` ciclos consecutivos de leitura inválida (`!isfinite`),
o estado é limitado a `ST_WARNING` (fan = 100%, relay **fechado** — motor não cortado).
Após atingir o threshold, `ST_CRITICAL` é permitido (relay aberto — fail-safe completo).
Log de transição FSM agora distingue `[NTC-GRACE]` de `[NTC-FAILSAFE]`.

### 🔒 Segurança

- `config.h.example` mantido com placeholders corretos; credenciais reais nunca devem
  ser commitadas (arquivo está em `.gitignore`).
- `WDT_TIMEOUT_S` documentado com comentário explicando o valor escolhido.

---

Auditoria interna pré-release aplicou correções em 3 rodadas:
1ª — 2 críticas + 6 de robustez + 6 melhorias
2ª — JSON sanitization, dashboard consistency, log throttling
3ª — bounds absolutos em `/config`, AP→STA recovery, WS anti-DoS

### ✨ Added
- Identidade visual **RS50H** (banner SVG com gradient cyan→green→amber→red)
- Dashboard web embutido (`dashboard.h`) com:
  - Gauge de temperatura em tempo real
  - Controle manual/automático do PWM do fan
  - Badge de estado FSM (IDLE / WARMING / WARNING / CRITICAL / RESTART)
  - Telemetria via WebSocket (uptime, RSSI, heap, relé, ntc_faults)
  - Thresholds populados dinamicamente a partir do firmware
  - Label de histerese (`CRIT − REST`) calculada em runtime, não hardcoded
- Documento `HERITAGE.md` rastreando linhagem desde o RS50 original
- `WIRING.md` com diagramas ASCII limpos do path de potência e do fan PWM
- Pre-commit hook validando markdown, segredos e build
- **Macros `CFG_MIN_TEMP` / `CFG_MAX_TEMP`** em `config.h.example` para
  validação de bounds absolutos no endpoint `POST /config`

### 🔐 Security
- **OTA com senha obrigatória** via `ArduinoOTA.setPassword(OTA_PASSWORD)`.
  Macro `OTA_PASSWORD` em `config.h.example`. Uploads sem credencial falham
  com `Auth Failed`.
- **Dashboard HTTP protegido por Basic Auth** (`HTTP_AUTH_USER` / `HTTP_AUTH_PASS`).
- **WebSocket exige token de sessão** emitido pelo endpoint autenticado
  `/ws-token` (TTL 10 min). Clientes sem `AUTH <token>` na primeira mensagem
  são desconectados.
- **WS anti-DoS**: clientes que conectam mas não enviam `AUTH <token>` em
  até 10 s (`WS_AUTH_TIMEOUT_MS`) são desconectados automaticamente. Limite
  de `WS_MAX_CLIENTS=8` slots com tracking individual de autenticação.
- **WS broadcast filtrado por auth**: `broadcastWs()` agora envia telemetria
  apenas para clientes que completaram o handshake AUTH (mudança em relação à
  v1 do design — re-avaliação documentada em `SECURITY.md`).

### 🛡️ Robustness
- **Relé NC fail-safe** (normally-closed) com histerese de 10 °C
  (CRITICAL em 68 °C → RESTART quando temp < 58 °C)
- **FSM térmica com histerese** para evitar oscilação de estados
- **Flyback diode 1N4007** obrigatório no driver do fan
- **Reconexão WiFi automática** no `loop()` (retry a cada 5 s) com
  `WiFi.setAutoReconnect(true)` como reforço nativo
- **AP→STA recovery automático**: quando em `AP_FALLBACK` (RS50H-Setup),
  tenta voltar para STA a cada 60 s (`AP_TO_STA_RETRY_MS`). Se o roteador
  voltar, o dispositivo migra sem reboot.
- **Fan ativo durante OTA** em `OTA_FAN_DUTY_PCT` (default 100 %) — flag
  `g_otaActive` impede o FSM loop de sobrescrever o duty cycle
- **Fail-safe persistente para falha de NTC**: após
  `NTC_FAULT_FAIL_SAFE_CYCLES` (default 10 × 500 ms = 5 s) leituras inválidas
  consecutivas, fan vai a 100 % e estado mínimo passa a `WARNING`.
  Contador `ntc_faults` exposto na telemetria
- **`buildJson()` sanitiza NaN/Inf de `g_temp`** como literal `"null"` no
  payload, garantindo JSON sempre válido mesmo com sensor desconectado
  (dashboard e plugins UDP nunca quebram em runtime)
- **Log NTC com anti-spam**: mensagem única na transição
  valid→invalid e throttle de 10 s no estado "sensor ausente"
  (`NTC_LOG_THROTTLE_MS`), preservando serial legível em produção
- **Rollback explícito no `POST /config`**: snapshot dos thresholds antes
  da parse; se a invariante `fan_on < rest < warn < crit` falhar, restaura
  os valores em RAM sem depender da recarga via `loadPrefs()`
- **Validação de bounds absolutos em `POST /config`**: além das invariantes
  de ordem, todos os 4 thresholds devem estar em `[CFG_MIN_TEMP, CFG_MAX_TEMP]`
  (default `0..100 °C`). Body fora dos limites retorna `400` com hint.
- **Validação do NVS no boot**: `loadPrefs()` valida os valores recuperados
  contra a mesma invariante. Se o NVS estiver corrompido (flash desgastado,
  downgrade entre versões), usa defaults de compilação com log explícito.
- **Fallback AP automático** (`RS50H-Setup`) se a conexão STA falhar no
  boot — dispositivo permanece acessível para reconfiguração sem reflash
- **Task watchdog explícito** (`esp_task_wdt`, timeout 15 s) com
  `esp_task_wdt_reset()` no `loop()` e dentro de `OTA.onProgress`
- **Guard de versão de core ESP32**: `#error` em `config.h.example` se
  `ESP_ARDUINO_VERSION_MAJOR >= 3` (LEDC legacy API foi removida)

### 🐛 Fixed (pre-release polish)
- Dashboard exibia *"histerese 5 °C"* hardcoded, divergindo do firmware
  (real: 10 °C, `CRIT 68 → REST 58`). Agora o rótulo é calculado em runtime
  a partir do `cfg` recebido pelo WebSocket.
- Dashboard mostrava `0.0 °C` quando o firmware enviava `"t": null`
  (sensor em falha). Corrigido para `--.-`, consistente com o serial e com
  o estado real do sensor.
- Histórico do gráfico (`hist[]`) recebia `0` em vez de "sem ponto" durante
  falha de NTC, criando uma falsa queda artificial até 0 °C. Agora apenas
  leituras válidas são empilhadas — a linha pausa em vez de cair.
- `docs/dashboard-source.html` (fonte editável) estava defasado em relação
  a `dashboard.h` (sem auth WS, sem `ntc_faults`, sem `applyCfg`).
  Resincronizado e com simulação de FSM alinhada ao firmware
  (`T_REST=58`, histerese 10 °C).
- `release.yml` usava loop frágil para renomear o binário; agora renomeia
  explicitamente apenas `rs50h_thermal.ino.bin` (preservando bootloader e
  partitions como artefatos separados).
- `release.yml` agora extrai release notes da seção `[X.Y.Z]` do CHANGELOG
  via `awk`, com fallback para o arquivo completo se a seção não existir.

### 🔧 Configuration & Persistence
- **Thresholds persistentes via `Preferences`** (NVS, namespace `rs50h`).
  Endpoint `POST /config` aceita JSON
  `{"fan_on":..,"warn":..,"crit":..,"rest":..}` com validação de ordem +
  bounds absolutos. Defaults de compilação preservados como fallback.
- **FSM lê thresholds de variáveis runtime** (`g_tFanOn`, `g_tWarn`,
  `g_tCrit`, `g_tRest`) em vez de macros — defaults vêm de `config.h`
- **`static_assert(JSON_BUF_SZ >= 256)`** no buffer do payload JSON,
  evitando truncamento silencioso ao adicionar campos
- **UDP broadcast com token opcional** (`UDP_TOKEN_ENABLED`, default `0`).
  Quando ativado, JSON inclui `bucket` + `tok` (FNV-1a 32 sobre
  `bucket || UDP_SHARED_SECRET`). Desativado por padrão para manter
  compatibilidade com SimHub Custom UDP plugin sem modificações

### 🌐 HTTP Endpoints
- `GET /` — dashboard HTML (Basic Auth)
- `GET /status` — telemetria JSON pura (Basic Auth), pronta para
  Home Assistant REST sensor, Prometheus exporter, scripts curl
- `GET /ws-token` — emite token WS de sessão (Basic Auth)
- `POST /config` — atualiza thresholds em runtime, persiste em NVS,
  valida bounds + invariantes com rollback automático

### 🏗️ Infrastructure
- CI/CD GitHub Actions: build → artifacts → release automático em tag `v*`
- Geração de binários: firmware, bootloader, partitions
- Dependências fixadas: `arduino-cli@1.1.1`, `esp32:esp32@2.0.14`,
  `FastLED@3.6.0`, `WebSockets@2.4.1`
- **Pre-commit hook offline-friendly**: não depende mais de `npx --yes`.
  Procura `markdownlint-cli2` global → `markdownlint` global →
  `node_modules` local. Variáveis `SKIP_MD_LINT=1` e `REQUIRE_MD_LINT=1`
  para CI/local
- **`06_hotfix.ps1` valida `-Version`** via `[ValidatePattern]` SemVer
  estrito (incluindo prerelease `X.Y.Z-rc.1`), checa existência de tag
  remota antes de sobrescrever, e avisa se `-Message` não segue
  Conventional Commits

### 📜 Inherited from rs50-thermal-controller v3.3.13
- Algoritmo de controle térmico PID-lite
- Driver NTC com filtro moving-average (N=8)
- Configuração WiFi por SSID/PASS em config.h
- OTA Update via web (agora com senha obrigatória)

---

## Linhagem Histórica (pré-RS50H)

### rs50-thermal-controller — v3.3.13 (origem do fork)
Última versão antes do rebranding. Toda a base de código foi preservada.

### RS50 — v1.0.0 (protótipo)
Hardware similar, firmware ancestral. Validação inicial da topologia
XT60 → LM2596 → ESP32-S3 → Fan PWM 25kHz.

---

[Unreleased]: https://github.com/Jean-DrEaD/rs50h-thermal-controller/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/Jean-DrEaD/rs50h-thermal-controller/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Jean-DrEaD/rs50h-thermal-controller/releases/tag/v1.0.0
