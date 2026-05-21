# RS50H Thermal Controller — Referência Técnica

> **Versão:** 1.0.0 · **Herança:** `rs50-thermal-controller` v3.3.13 → ver [`docs/HERITAGE.md`](./docs/HERITAGE.md)

---

## Stack de build

| Item | Valor |
|------|-------|
| MCU | ESP32-S3-Zero (Waveshare) — 512 kB SRAM, 4 MB Flash, sem PSRAM |
| Arduino core | `esp32:esp32@2.0.14` (LEDC legado — não atualizar para 3.x sem migrar) |
| FQBN | `esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled` |
| FastLED | `3.6.0` |
| WebSockets | `2.4.1` |

---

## Topologia fail-safe

```
+24 V ─── Relé NC (SLA-24VDC) ─── MKS VIN+
GND ──────────────────────────── MKS GND

GPIO4=LOW  → MOSFET OFF → bobina desenergizada → relé NC FECHADO → motor OK
GPIO4=HIGH → MOSFET ON  → bobina energizada    → relé ABERTO    → motor PARA

Sem 5 V na ESP → GPIO4 flutuante → pull-down 10k → LOW → relé FECHADO (seguro)
```

---

## Invariantes da FSM

```
fan_on(40) < warn(60) < crit(68)     [ordem dos limiares de aquecimento]
fan_on(40) < rest(58) < warn(60)     [garantia: religar abaixo de WARNING]
```

A condição `rest < warn` é validada no endpoint `POST /config` e garante que
o motor religue com a ventoinha em modo linear (abaixo de 100 %), evitando
o loop CRITICAL → RESTART → WARNING → CRITICAL imediato.

> **Atenção**: `rest` deve ser **menor** que `warn`. Valores de `rest` acima
> de `warn` violam a invariante e são rejeitados por `POST /config` com HTTP 400.

---

## Segurança (superfície LAN doméstica)

| Vetor | Proteção |
|-------|----------|
| OTA | `ArduinoOTA.setPassword(OTA_PASSWORD)` |
| Dashboard HTTP | HTTP Basic Auth |
| WebSocket | Token de sessão via `/ws-token` (TTL 10 min) |
| `POST /config` | Basic Auth + validação de ordem |
| Telemetria WS | Broadcast público — dados não-sensíveis (intencional) |
| UDP SimHub | Token FNV-1a opcional (`UDP_TOKEN_ENABLED 0`) |

> ⚠️ Não expor na internet. Projetado para LAN doméstica / bancada de sim-racing.

---

## Fluxo de release

```
branch fix/* ou feat/*
  → CI build (build.yml)
  → merge na main
  → git tag -a vX.Y.Z
  → release.yml: build + GitHub Release automático
```

Ver [`docs/CI_CD.md`](./docs/CI_CD.md) para detalhes e scripts PowerShell.
