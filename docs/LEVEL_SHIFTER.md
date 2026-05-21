# LEVEL SHIFTER — GPIO9 → WS2812

> Documento gerado pela auditoria de hardware v3 · 2026-05-20  
> Refere-se ao módulo da foto: **4-CH BSS138 Bidirectional Level Shifter**

---

## ⚠️ Diagnóstico: Level Shifter é necessário no GPIO9?

**Sim. Tecnicamente obrigatório para operação dentro de especificação.**

| Parâmetro | Valor |
|-----------|-------|
| Saída lógica do ESP32-S3 (GPIO9) | **3,3 V** |
| VIH mínimo do WS2812 (= 0,7 × VDD) | **3,5 V** (com VDD = 5 V) |
| Margem | **−0,2 V → fora de spec** |
| VCC dos LEDs WS2812 | **5 V** (rail LM2596 #2) |

O setup atual funciona em bancada porque clones WS2812 têm variação de processo
e frequentemente aceitam 3,3 V no DIN, especialmente com poucos LEDs e cabo curto.
Porém não é garantido: troca de fornecedor do LED, cabo mais longo ou interferência
podem causar falhas de comunicação intermitentes sem causa aparente.

---

## Módulo disponível: 4-CH BSS138 Bidirectional Level Shifter

O módulo da foto é o design padrão BSS138 (NMOS SOT-23) popularizado pela
Adafruit / SparkFun e vastamente clonado. Cada canal é bidirecional por natureza
(gate do BSS138 conectado ao LV rail; pull-ups 10 kΩ de cada lado).

```
Legenda do módulo (foto):
  Top row:    HV1  HV2  HV  GND  HV3  HV4
  Bottom row: LV1  LV2  LV  GND  LV3  LV4

  "103" = 10 kΩ pull-up (SMD 3-digit code)
  "J1Y" = BSS138 N-MOSFET em SOT-23
```

> **Nota WS2812:** o sinal DIN é unidirecional (MCU → LED). O BSS138
> bidirectional funciona, mas as pull-ups de 10 kΩ podem arredondar bordas em
> aplicações de alta velocidade. Com 5 LEDs e cabo < 50 cm, funciona sem problemas.
> Para setups maiores, prefira um buffer 74AHCT1G125 ou 74HCT125.

---

## Ligação com o módulo BSS138

```
                     ┌──────────────────────┐
                     │  BSS138 Level Shifter │
  3V3 (ESP32) ──────►│ LV             HV ◄──── 5V (LM2596 #2)
  GND ────────────►  │ GND           GND ◄──── GND (barramento)
                     │                        │
  GPIO9 ──────────►  │ LV1           HV1 ──────[330 Ω]──► WS2812 DIN
                     └──────────────────────┘
```

### Passo a passo de conexão

| Pino do módulo | Conectar em |
|----------------|-------------|
| `LV` | 3V3 do ESP32-S3-Zero |
| `HV` | 5V do LM2596 #2 (mesmo rail que alimenta os WS2812) |
| `GND` (qualquer dos dois) | GND do barramento |
| `LV1` | GPIO9 do ESP32-S3-Zero |
| `HV1` | Ponta do resistor 330 Ω → outra ponta vai ao DIN do WS2812 |

> ⚠️ **GND compartilhado obrigatório:** o ESP32, o módulo BSS138 e os WS2812
> devem compartilhar o mesmo GND. Sem GND comum, a lógica de nível não funciona.

> ⚠️ **O resistor 330 Ω permanece no circuito**, mas agora fica no lado HV
> (entre `HV1` do módulo e o pino `DIN` do WS2812), não mais entre GPIO9 e DIN.

---

## Diagrama atualizado (seção 6 do WIRING.md)

```
  5V ─────────────────────────────────────────► WS2812 VCC
  GND ────────────────────────────────────────► WS2812 GND
  3V3 ─────────────►[LV]  BSS138  [HV]◄──── 5V
  GND ─────────────►[GND]         [GND]◄──── GND
  GPIO9 ───────────►[LV1]         [HV1]──[330Ω]──► WS2812 DIN
```

---

## Canais LV2 / LV3 / LV4 disponíveis

O módulo possui 4 canais; os outros 3 ficam livres para uso futuro
(ex.: expansão de comunicação I²C com display, sensor extra).

---

## Impacto em config.h / firmware

**Nenhuma alteração de firmware necessária.**  
`PIN_WS2812 9` permanece igual — a conversão de nível é transparente para o ESP32.  
O FastLED continua enviando o sinal em 3,3 V para `LV1`; o BSS138 entrega 5 V em `HV1`.

---

## Resumo de status

| Item | Antes | Depois |
|------|-------|--------|
| Nível lógico no DIN do WS2812 | 3,3 V (fora de spec) | 5 V (dentro de spec) |
| Confiabilidade | Funciona, mas frágil | Garantida pelo datasheet |
| Firmware alterado | — | Não |
| GPIO alterado | — | Não |
| Resistor 330 Ω | Entre GPIO9 e DIN | Entre HV1 e DIN |
| Custo do fix | — | 1 canal do módulo BSS138 (já disponível) |
