# WIRING — RS50H Thermal Controller

> Version: 1.0.1 — Revisado 2026-05-20 (adicionada seção 6 com level shifter BSS138)
>
> Para diagrama gráfico: [`docs/wiring-schematic.svg`](wiring-schematic.svg)

---

## 1. Distribuição de Energia

```
XDrive Mini PSU ──┬── 24V ──► Songle Relay COM
 (24V/cabos       │            └─► NC ──► ODESC FFBeast (motor driver)
  1.5mm² fios)    │
                  ├── 24V ──► LM2596 #1 ─► 12V ──┬── Fan 12V (PWM direto)
                  │                               │
                  │                               └── LM2596 #2 ─► 5V ──► ESP32-S3-Zero VBUS
                  │                                                  └──► WS2812 VCC
                  │                                                  └──► BSS138 HV
                  │
                  └── 24V ──► Bobina do relé (A1)
```

---

## 2. Pinout ESP32-S3-Zero

```
                   ┌──────────────────────┐
                   │   ESP32-S3-Zero      │
                   │                      │
 NTC ────────────► │ GPIO 1  (ADC1_CH0)   │
                   │                      │
 Fan PWM ─────────►│ GPIO 5  (25kHz)      │  ← PWM direto (sem MOSFET!)
                   │                      │
 Relé MOSFET ─────►│ GPIO 4               │ ──► IRLZ44N Gate (220Ω)
                   │                      │
 WS2812 ──────────►│ GPIO 9               │ ──► BSS138 LV1 ──► [330Ω] ──► WS2812 DIN
                   │                      │    (⚠️ ver seção 6)
                   │ GND ─────── GND      │
                   │ 3V3 ─────── BSS138 LV│
                   │ 5V  ─────── VBUS     │
                   └──────────────────────┘
```

> ⚠️ **NÃO usar GPIO21** — LED RGB onboard do ESP32-S3-Zero.

---

## 3. NTC Thermistor (100K B3950)

```
 3.3V ──[100kΩ 1%]──┬──► GPIO 1 (ESP32 ADC)
                    │
                 ┌──┴──┐
                 │ NTC │  100K B3950 (no estator)
                 │     │
                 └──┬──┘
                    │
                   GND
 (100nF entre GPIO1 e GND)
```

---

## 4. Fan PWM 12V — Conexão Direta

```
            12V (LM2596 #1)
              │
        ┌─────▼─────┐
        │  FAN 120mm│  ← 4-pin PWM nativo
        │ 12V PWM   │     (GPIO5 3.3V direto!)
        └─────┬─────┘
              │
              └─► Fan GND
GPIO 5 ────────────────► Fan PWM (25kHz, 3.3V logic)
```

---

## 5. Relay de Segurança Fail-Safe NC — IRLZ44N

> ⚠️ **ATENÇÃO: Relé NC!** — Se o ESP travar, o motor **continua** (fail-safe).

```
            24V
             │
             ▼
        ┌─────────┐
        │ Relé    │ COM ───► 24V fonte
        │ Songle  │
        │ SLA-24V │ NC  ───► ODESC VIN+ (motor power)
        │  30A    │
        └────┬────┘
             │
             │ Bobina 24V
             │ A1 = +24V
             │ A2 = Drain IRLZ44N
             ▼
          [1N4007]  ← Flyback: K→A1 | A→A2
             │
        ┌──┴────────┐
        │ IRLZ44N   │
        │ G ─[220Ω]► GPIO 4
        │  │[10k↓]  │  ← Pull-down
        │ S ────► GND
        └───────────┘
```

---

## 6. LEDs de Status WS2812 — com Level Shifter BSS138

> ⚠️ **Por que o level shifter é necessário aqui?**  
> O ESP32-S3-Zero opera em lógica **3,3 V**. Os WS2812 alimentados a 5 V exigem
> **VIH ≥ 3,5 V** (= 0,7 × VDD). A saída de GPIO9 em 3,3 V está **0,2 V abaixo
> do mínimo especificado** — pode funcionar em bancada, mas não é confiável.  
> O módulo BSS138 4-CH disponível resolve com um único canal.  
> Ver detalhes completos em [`docs/LEVEL_SHIFTER.md`](LEVEL_SHIFTER.md).

```
  5V ─────────────────────────────────────────────────► WS2812 VCC
  GND ────────────────────────────────────────────────► WS2812 GND

                    ┌─────────────────────┐
  3V3 (ESP32) ─────►│ LV          HV ◄───── 5V (LM2596 #2)
  GND ─────────────►│ GND        GND ◄───── GND (barramento)
  GPIO9 ───────────►│ LV1        HV1 │──[330Ω]──► WS2812 DIN
                    │   BSS138 4-CH  │
                    │  (canais 2-4   │
                    │   disponíveis) │
                    └─────────────────────┘
```

`NUM_LEDS`: 1–5 LEDs (definido em `include/config.h`)

### Pinagem do módulo BSS138

| Pino BSS138 | Conectar em |
|-------------|-------------|
| `LV` | 3V3 do ESP32-S3-Zero |
| `HV` | 5V do LM2596 #2 |
| `GND` | GND do barramento |
| `LV1` | GPIO9 do ESP32-S3-Zero |
| `HV1` | Resistor 330 Ω → WS2812 DIN |

> Os canais LV2/HV2, LV3/HV3, LV4/HV4 ficam disponíveis para expansão futura.

---

## 7. Especificação de Cabos

| Circuito                  | Seção recomendada         |
|---------------------------|---------------------------|
| 24V (Relé / ODESC)        | 1,5 mm² (~16 AWG)         |
| NTC (sinal)               | 0,5 mm² trançado < 30 cm  |
| WS2812 (dados)            | 0,5 mm² < 50 cm           |
| Bobina do relé            | 0,5 mm²                   |
| BSS138 LV/HV (alimentação)| 0,5 mm² < 10 cm           |
