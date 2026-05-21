# CONTEXT — RS50H Thermal Controller

> Referência rápida de estado e decisões técnicas para retomar o desenvolvimento.
> Manter atualizado a cada sessão relevante.
> Para roadmap de versões: [`ROADMAP.md`](./ROADMAP.md)

---

## Estado atual (2026-05-18)

**Firmware:** v1.0.0 — pré-publicação  
**Hardware validado em bancada:** parcialmente (sem motor 24 V real ainda)  
**Repositório:** privado / local — não publicado no GitHub
**Última gravação:** `COM5` via USB-CDC, `arduino-cli 1.1.1` + `esp32:esp32@2.0.14`

### O que está funcionando

| Subsistema | Status | Observação |
|-----------|--------|------------|
| Boot ESP32-S3 + serial | ✅ | Banner RS50H, heap e flash logados |
| Leitura NTC GPIO1 | ✅ | Steinhart-Hart B3950, média N=8 |
| PWM fan 25 kHz GPIO5 | ✅ | LEDC legado core 2.0.14 |
| WS2812 5 LEDs GPIO9 | ✅ | FastLED 3.6.0, cores por estado FSM |
| Relé via MOSFET GPIO4 | ✅ | Topologia NC fail-safe |
| FSM térmica 5 estados | ✅ | IDLE/WARMING/WARNING/CRITICAL/RESTART |
| Dashboard HTTP/WS | ✅ | Servido via PROGMEM, auth OK |
| UDP broadcast SimHub | ✅ | Token opcional desativado por padrão |
| OTA rs50h-thermal.local | ✅ | Com senha, fan 100 % durante upload |
| Thresholds NVS (Preferences) | ✅ | POST /config validado + rollback |
| Validação bounds `/config` | ✅ | CFG_MIN_TEMP/CFG_MAX_TEMP (0..100 °C) |
| AP fallback de emergência | ✅ | RS50H-Setup se STA falhar |
| AP→STA recovery | ✅ | Retry a cada 60 s |
| WS anti-DoS (timeout AUTH 10 s) | ✅ | Desconecta clientes ociosos |
| Task watchdog 15 s | ✅ | Reset explícito em loop e OTA (BF-1: granular após cada handler) |
| **Compilar + gravar** | ✅ | COM5, USB-CDC, sem erros |
| **Teste com motor 24 V real** | ⏳ | Pendente — primeira prioridade pós-push |

---

## Decisões de design abertas / pendentes

### 1. Thresholds de temperatura (aferir com motor real)

Os valores atuais são conservadores por design — o NTC está montado **no estator**,
não diretamente no enrolamento, e há offset de medição desconhecido.

```
fan_on = 40 °C   warn = 60 °C   crit = 68 °C   rest = 58 °C
```

**Histerese:** 10 °C (68 → 58). Motor volta com ventoinha ~90 %.  
**Após validação em bancada:** medir temperatura real do enrolamento durante sessão
de sim-racing, calcular offset NTC vs estator, e recalibrar. Ver `ROADMAP.md` v1.1.0.

> `TEMP_RESTART = 58.0f` — ajustado de 55 para reduzir tempo de parada do motor.
> Máximo possível sem alterar `warn`: 59 °C. Não alterar acima de `warn - 1`.

### 2. Broadcast WebSocket sem filtro de autenticação (decisão intencional)

`broadcastWs()` agora envia telemetria **apenas** para clientes que completaram
o handshake `AUTH <token>`. Decisão em relação à versão pré-release que
broadcastava para todos.

Motivação: alinhar com o WS anti-DoS (timeout de 10 s). Como o cliente já é
desconectado se não autenticar, o broadcast aberto não tinha valor prático.

Documentado em `SECURITY.md`. **Não reverter sem re-avaliar o modelo de segurança.**

### 3. LEDC legacy API — não migrar para core 3.x sem reescrever

```c
ledcSetup(LEDC_CHAN_FAN, LEDC_FREQ_FAN, LEDC_RES_FAN);
ledcAttachPin(PIN_FAN_PWM, LEDC_CHAN_FAN);
ledcWrite(LEDC_CHAN_FAN, duty);
```

Core 3.x remove essas funções. Guard em `config.h.example` bloqueia compilação
se `ESP_ARDUINO_VERSION_MAJOR >= 3`. Migração futura requer:

```c
ledcAttach(PIN_FAN_PWM, LEDC_FREQ_FAN, LEDC_RES_FAN);
ledcWrite(PIN_FAN_PWM, duty);  // por pino, não por canal
```

---

## Arquitetura de arquivos críticos

```
include/config.h.example   ← fonte de verdade de pinos, thresholds e credenciais
include/config.h           ← gerado localmente (gitignored) — nunca commitar
src/rs50h_thermal/
  rs50h_thermal.ino        ← firmware principal (649 linhas)
  dashboard.h              ← HTML do dashboard em PROGMEM (~22 kB)
docs/
  dashboard-source.html    ← fonte editável do dashboard (sincronizar com dashboard.h)
  wiring-ascii.txt         ← fonte da verdade de pinagem (hardware)
ci/libraries.txt           ← FastLED@3.6.0 + WebSockets@2.4.1 (versões fixas)
```

**Fluxo dashboard:** editar `docs/dashboard-source.html` →
copiar HTML para a raw string em `src/rs50h_thermal/dashboard.h` →
verificar com `python3 scripts/extract_dashboard.py --header src/rs50h_thermal/dashboard.h --out /tmp/check.html && diff /tmp/check.html docs/dashboard-source.html`. O CI falha se os dois estiverem fora de sincronia.

---

## Sequência de próximos passos

1. **[git]** git init no repo recriado → primeiro commit "feat: initial public release v1.0.0"
2. **[git]** Adicionar remote → git push -u origin main
3. **[release]** git tag v1.0.0 && git push --tags → CI dispara build + release
4. **[hardware]** Instalar NTC no estator, primeira sessão com motor 24 V real
5. **[hardware]** Medir offset NTC — termopar externo vs leitura serial
6. **[release]** Após validação em bancada: bump para v1.0.1, entry no CHANGELOG
7. **[post-release]** Recalibrar thresholds com dados reais → v1.1.0

---

## Referências rápidas

- `POST /config` body: `{"fan_on":40,"warn":60,"crit":68,"rest":58}`
- Invariante obrigatória: `fan_on < rest < warn < crit`
- Bounds absolutos: todos thresholds em `[CFG_MIN_TEMP, CFG_MAX_TEMP]` = `[0, 100] °C`
- mDNS: `http://rs50h-thermal.local` (porta 80) / OTA porta 3232
- Serial: 115200 baud — log de temperatura a cada 500 ms
- WDT: 15 s — alimentado em `loop()` após cada handler bloqueante (OTA, HTTP, WS) e em `OTA.onProgress`
- NTC fail-safe: 10 leituras inválidas consecutivas → fan 100 % + estado mínimo WARNING
- WS AUTH timeout: 10 s — clientes sem `AUTH <token>` são desconectados
- AP→STA retry: 60 s — quando em fallback, tenta voltar ao roteador

---

## Comandos validados (Windows / PowerShell)

# Compilar
```powershell
arduino-cli compile `
  --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled" `
  --build-property "compiler.cpp.extra_flags=-I$((Get-Location).Path.Replace('\','/'))/include" `
  src\rs50h_thermal
```

# Upload (COM5 — ajustar conforme dispositivo)
```powershell
arduino-cli upload `
  -p COM5 `
  --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled" `
  src\rs50h_thermal
```

# Monitor serial
```powershell
arduino-cli monitor -p COM5 -c baudrate=115200
```

---
