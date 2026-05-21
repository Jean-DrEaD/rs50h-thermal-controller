# HERITAGE — Rastreabilidade RS50 → RS50H

> Este documento registra a cadeia de evolução do firmware de controle térmico,
> desde o protótipo inicial `rs50-thermal-controller` até o release oficial `rs50h-thermal-controller`.

---

## Linha do tempo

```
rs50-thermal-controller v3.1.0   (protótipo inicial)
  └── rs50-thermal-controller v3.2.0   (cadeia LM2596, relé)
        └── rs50-thermal-controller v3.3.0   (topologia fail-safe)
              └── rs50-thermal-controller v3.3.13  (última versão "RS50")
                    │
                    ▼
              rs50h-thermal-controller v1.0.0  ← release oficial / rebranding
```

---

## Marcos de desenvolvimento

| Versão (RS50) | Data aprox. | Mudança principal |
|---------------|-------------|-------------------|
| v3.1.0 | 2024-Q3 | Protótipo: ESP32-S3 + NTC + ventoinha simples via `analogWrite` |
| v3.1.5 | 2024-Q3 | Migração para `ledcSetup`/`ledcAttachPin` (PWM 25 kHz) |
| v3.2.0 | 2024-Q4 | Cadeia de alimentação dupla LM2596 (24 V → 12 V → 5 V) |
| v3.2.4 | 2024-Q4 | Introdução do relé SLA-24VDC-SL-C (topologia NC) |
| v3.2.8 | 2024-Q4 | Diodo flyback 1N4007 + resistor pull-down no gate MOSFET |
| v3.3.0 | 2024-Q4 | Topologia fail-safe consolidada; FSM com 5 estados |
| v3.3.5 | 2025-Q1 | Dashboard HTML embutido em PROGMEM (`dashboard.h`) |
| v3.3.8 | 2025-Q1 | WebSocket telemetria 2 Hz; UDP SimHub 1 Hz |
| v3.3.10 | 2025-Q1 | OTA ArduinoOTA com estado seguro (relay LOW, fan 0 %) |
| v3.3.11 | 2025-Q1 | FastLED WS2812 indicando FSM em tempo real |
| v3.3.13 | 2025-Q1 | Última versão sob nome "RS50" — CI estável, todos os sistemas OK |
| **v1.0.0** | **2026-Q2** | **Release oficial sob nome RS50H — rebranding, SemVer público** |

---

## O que mudou entre RS50 v3.3.13 e RS50H v1.0.0

| Área | RS50 v3.3.13 | RS50H v1.0.0 |
|------|--------------|--------------|
| Nome do repositório | `rs50-thermal-controller` | `rs50h-thermal-controller` |
| Nome do sketch | `rs50_thermal.ino` | `rs50h_thermal.ino` |
| Macro `HW_MODEL` | (ausente) | `"RS50H"` |
| Macro `FW_VERSION` | (ausente / interno) | `"1.0.0"` — SemVer público |
| Header `config.h` | Inline no `.ino` | Separado em `include/config.h` |
| Template de config | Ausente | `include/config.h.example` |
| CI/CD | Ad-hoc | GitHub Actions (`build.yml` + `release.yml`) |
| Hooks git | Ausente | `.githooks/pre-commit` (validação local) |
| Scripts de dev | Ausentes | `scripts/ps/` (audit, commit, push, tag, monitor) |
| Versionamento | 3.3.x (interno, não-público) | SemVer público a partir de 1.0.0 |

> ⚠️ **Não há mudança elétrica** entre v3.3.13 e v1.0.0.
> A topologia de hardware, a FSM térmica, os thresholds e os GPIOs são **idênticos**.
> A transição é **organizacional e simbólica** — marca a passagem de protótipo iterativo
> para release oficial estável com identidade pública consolidada.

---

## Origem do nome "RS50H"

- **RS50** — identificador interno do projeto de volante DirectDrive (sim-racing).
- **H** — sufixo de *Hoverboard*: refere-se ao motor BLDC extraído de hoverboard
  (tipicamente 15 Nm, 250 W, sensor Hall, acionado pelo MKS XDrive Mini / FFBeast).
- Sem qualquer relação com produtos da marca Logitech ou similares.

---

## Rastreabilidade de hardware

O hardware foi validado em campo durante todo o ciclo v3.x antes do release v1.0.0.
A topologia de proteção (relé NC + MOSFET IRLZ44N + flyback) opera desde v3.2.4
sem alteração de esquema ou valores de componentes.

Referência: [`docs/wiring-schematic.svg`](./wiring-schematic.svg) · [`docs/wiring-ascii.txt`](./wiring-ascii.txt)

---

## Notas de compatibilidade

- **ESP32 Arduino core:** pinado em `2.0.14`. A API LEDC legada (`ledcSetup` / `ledcAttachPin`)
  foi removida no core v3.x. Qualquer migração futura requer reescrita das chamadas LEDC.
- **PSRAM:** o ESP32-S3-Zero (Waveshare) **não possui PSRAM**. O FQBN mantém `PSRAM=disabled`.
  Toda a pilha de runtime (WiFi ~80 kB, WebSocket, FastLED) cabe nos 512 kB de SRAM interna.
  O `dashboard.h` é armazenado em PROGMEM (flash) — zero custo de SRAM.
