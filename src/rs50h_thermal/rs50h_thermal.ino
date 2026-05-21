/*
 * RS50H Thermal Controller — Firmware v1.0.1
 * Platform : ESP32-S3-Zero (Waveshare) — no PSRAM, 4 MB Flash
 * Compiler : arduino-cli · FQBN: esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,
 *                                  FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled
 *
 */

#include "config.h"
#include "dashboard.h"
#define  FASTLED_INTERNAL  // suprime pragma messages do FastLED
#include <FastLED.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ESPmDNS.h>
#include <WebServer.h>
#include <WebSocketsServer.h>
#include <ArduinoOTA.h>
#include <Preferences.h>
#include <esp_task_wdt.h>
#include <math.h>

// ── LEDC (core 2.0.14 legacy API) ────────────────────────────────────────────
#define LEDC_CHAN_FAN   0
#define LEDC_FREQ_FAN   25000
#define LEDC_RES_FAN    8

// ── Anti-spam log throttle ───────────────────────────────────────────────────
#define NTC_LOG_THROTTLE_MS  10000UL

// ── WS anti-DoS ──────────────────────────────────────────────────────────────
#define WS_AUTH_TIMEOUT_MS   10000UL
#define WS_MAX_CLIENTS       8

// ── AP→STA retry ─────────────────────────────────────────────────────────────
#define AP_TO_STA_RETRY_MS   60000UL

// ── FSM ──────────────────────────────────────────────────────────────────────
enum ThermalState : uint8_t {
    ST_IDLE, ST_WARMING, ST_WARNING, ST_CRITICAL, ST_RESTART
};

// ── Runtime thresholds (M1 — mutáveis via NVS) ───────────────────────────────
static float g_tFanOn = TEMP_FAN_ON;
static float g_tWarn  = TEMP_WARNING;
static float g_tCrit  = TEMP_CRITICAL;
static float g_tRest  = TEMP_RESTART;

// ── Globals ──────────────────────────────────────────────────────────────────
static float        g_temp      = 0.0f;
static uint8_t      g_duty      = 0;
static uint16_t     g_rpm       = 0;       // BF-5: RPM (estimado ou real)
static bool         g_relayOpen = false;
static ThermalState g_state     = ST_IDLE;
static bool         g_ntcValid  = true;
static uint16_t     g_ntcFaultStreak = 0;
static bool         g_otaActive = false;
static uint32_t     g_lastSample      = 0;
static uint32_t     g_lastWsBcast     = 0;
static uint32_t     g_lastUdpBcast    = 0;
static uint32_t     g_lastWifiRetry   = 0;
static uint32_t     g_lastApToStaRetry = 0;
static uint32_t     g_bootMs          = 0;
static CRGB         g_leds[NUM_LEDS];
static WebServer        g_http(80);
static WebSocketsServer g_ws(81);
static WiFiUDP          g_udp;
static bool             g_wifiOk = false;
static bool             g_apMode = false;
static Preferences      g_prefs;

// ── Anti-spam state ──────────────────────────────────────────────────────────
static uint32_t g_lastNtcLogMs    = 0;
static bool     g_ntcAbsentLogged = false;

// ── WS session token (C2) + per-client auth tracking ─────────────────────────
static char     g_wsToken[17]  = {0};
static uint32_t g_wsTokenIssuedMs = 0;
static bool     g_wsAuthed[WS_MAX_CLIENTS]      = {false};
static uint32_t g_wsConnectedAt[WS_MAX_CLIENTS] = {0};

// ── Tachometer (BF-5) ────────────────────────────────────────────────────────
// rpm_src: "tach" quando PIN_FAN_TACH >= 0; "est" quando estimado por duty.
// Estimativa pressupõe curva linear 0–RPM_ESTIMATED_MAX.
// Nota: PWM=0 → g_rpm=0 (firmware comanda parado); fan pode girar em mínimo de hardware.
#if defined(PIN_FAN_TACH) && PIN_FAN_TACH >= 0
static volatile uint32_t g_tachPulses = 0;
static void IRAM_ATTR tachISR() {
    g_tachPulses++;
}
static const char* RPM_SRC = "tach";
#else
static const char* RPM_SRC = "est";
#endif

// ── Prototypes ───────────────────────────────────────────────────────────────
static float        readNTC();
static ThermalState nextState(float temp, ThermalState prev);
static uint8_t      fanDutyPct(float temp, ThermalState st);
static void         applyFan(uint8_t pct);
static void         applyRelay(bool open);
static void         applyLEDs(ThermalState st, bool ntcOk);
static void         updateRpm(uint32_t now);
static void         broadcastWs();
static void         broadcastUdp();
static void         setupWifi();
static void         startApFallback();
static void         tryRecoverSta();
static void         setupOTA();
static void         setupHttpRoutes();
static String       buildJson(bool includeUdpToken);
static const char*  stName(ThermalState s);
static void         loadPrefs();
static void         savePrefs();
static bool         httpAuthOk();
static void         generateWsToken();
static String       computeUdpToken(uint32_t bucketMs);
static void         pruneUnauthedWsClients();
static bool         validateThresholds(float fanOn, float warn, float crit, float rest);
static bool         parseJsonFloat(const String& body, const char* key, float& out);

// ─────────────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(SERIAL_BAUD);
    Serial.setTxTimeoutMs(0); // BF-4: CDC não bloqueia sem host USB
    delay(200);
    Serial.printf("\n[BOOT] RS50H Thermal v%s — HW=%s\n", FW_VERSION, HW_MODEL);
    Serial.printf("[RS50H] Free heap: %u B  Flash: %u B\n", ESP.getFreeHeap(), ESP.getFlashChipSize());

    loadPrefs();

    analogReadResolution(12);
    analogSetPinAttenuation(PIN_NTC, ADC_11db);

    pinMode(PIN_RELAY, OUTPUT);
    digitalWrite(PIN_RELAY, LOW);

    ledcSetup(LEDC_CHAN_FAN, LEDC_FREQ_FAN, LEDC_RES_FAN);
    ledcAttachPin(PIN_FAN_PWM, LEDC_CHAN_FAN);
    ledcWrite(LEDC_CHAN_FAN, 0);

    // BF-5: Tachometer ISR (opcional)
#if defined(PIN_FAN_TACH) && PIN_FAN_TACH >= 0
    pinMode(PIN_FAN_TACH, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(PIN_FAN_TACH), tachISR, FALLING);
    Serial.printf("[RPM] Tach ISR habilitado em GPIO%d\n", PIN_FAN_TACH);
#else
    Serial.printf("[RPM] Modo estimado por duty (PIN_FAN_TACH=-1). RPM_MAX=%d\n", RPM_ESTIMATED_MAX);
#endif

    FastLED.addLeds<WS2812, PIN_WS2812, GRB>(g_leds, NUM_LEDS);
    FastLED.setBrightness(LED_BRIGHTNESS);
    fill_solid(g_leds, NUM_LEDS, CRGB::Blue);
    FastLED.show();

    setupWifi();
    if (!g_wifiOk) {
        startApFallback();
    }

    if (g_wifiOk || g_apMode) {
        setupOTA();
        if (MDNS.begin(DEVICE_NAME)) {
            MDNS.addService("http", "tcp", 80);
            Serial.printf("[RS50H] mDNS: http://%s.local\n", DEVICE_NAME);
        }

        setupHttpRoutes();
        g_http.begin();
        g_ws.begin();
        g_ws.onEvent([](uint8_t num, WStype_t type, uint8_t* payload, size_t len) {
            if (num >= WS_MAX_CLIENTS) {
                g_ws.disconnect(num);
                return;
            }
            if (type == WStype_CONNECTED) {
                g_wsAuthed[num] = false;
                g_wsConnectedAt[num] = millis();
                Serial.printf("[WS] client #%u conectado — aguardando AUTH (%lums)\n",
                              num, (unsigned long)WS_AUTH_TIMEOUT_MS);
            } else if (type == WStype_DISCONNECTED) {
                g_wsAuthed[num] = false;
                g_wsConnectedAt[num] = 0;
            } else if (type == WStype_TEXT && payload && len > 0) {
                String msg((char*)payload, len);
                if (msg.startsWith("AUTH ")) {
                    String tok = msg.substring(5);
                    tok.trim();
                    bool ttlOk = (millis() - g_wsTokenIssuedMs) < WS_TOKEN_TTL_MS;
                    if (ttlOk && tok == String(g_wsToken)) {
                        g_wsAuthed[num] = true;
                        g_ws.sendTXT(num, "{\"auth\":\"ok\"}");
                        String j = buildJson(false);
                        g_ws.sendTXT(num, j);
                        Serial.printf("[WS] client #%u autenticado\n", num);
                    } else {
                        g_ws.sendTXT(num, "{\"auth\":\"fail\"}");
                        g_ws.disconnect(num);
                        Serial.printf("[WS] client #%u AUTH falhou — desconectado\n", num);
                    }
                }
            }
        });

        g_udp.begin(UDP_PORT);
        Serial.printf("[RS50H] HTTP :80  WS :81  UDP bcast :%u\n", UDP_PORT);
    } else {
        Serial.println("[RS50H] WiFi e AP fallback falharam — modo offline (serial only)");
    }

    esp_task_wdt_init(WDT_TIMEOUT_S, true);
    esp_task_wdt_add(NULL);
    Serial.printf("[WDT] Habilitado: timeout=%us\n", WDT_TIMEOUT_S);
    g_bootMs = millis();
    g_lastApToStaRetry = millis();
    Serial.println("[RS50H] Setup completo.\n");
}

// ─────────────────────────────────────────────────────────────────────────────
void loop() {
    esp_task_wdt_reset();

    if (g_wifiOk || g_apMode) {
        ArduinoOTA.handle();
        esp_task_wdt_reset();   // BF-1
        g_http.handleClient();
        esp_task_wdt_reset();   // BF-1
        g_ws.loop();
        esp_task_wdt_reset();   // BF-1
        pruneUnauthedWsClients();
    }

    uint32_t now = millis();

    // STA reconnect
    if (!g_apMode && WiFi.getMode() == WIFI_STA &&
        WiFi.status() != WL_CONNECTED &&
        (now - g_lastWifiRetry) >= WIFI_RECONNECT_MS) {
        g_lastWifiRetry = now;
        Serial.println("[WiFi] Desconectado — tentando reconectar...");
        WiFi.disconnect();
        WiFi.reconnect();
        g_wifiOk = false;
    } else if (!g_apMode && WiFi.status() == WL_CONNECTED && !g_wifiOk) {
        g_wifiOk = true;
        Serial.printf("[WiFi] Reconectado — %s\n", WiFi.localIP().toString().c_str());
    }

    // AP→STA recovery
    if (g_apMode && (now - g_lastApToStaRetry) >= AP_TO_STA_RETRY_MS) {
        g_lastApToStaRetry = now;
        tryRecoverSta();
    }

    if (now - g_lastSample >= SAMPLE_INTERVAL_MS) {
        g_lastSample = now;
        g_temp = readNTC();

        bool ntcFailSafe = (g_ntcFaultStreak >= NTC_FAULT_FAIL_SAFE_CYCLES);
        ThermalState newState = nextState(g_temp, g_state);

        if (newState != g_state) {
            const char* ntcTag = (!isfinite(g_temp) ? "  [NTC-FAILSAFE]" : "");
            Serial.printf("[FSM] %s → %s  T=%.1f°C%s\n",
                          stName(g_state), stName(newState), g_temp, ntcTag);
            g_state = newState;
        }

        if (!g_otaActive) {
            g_duty = ntcFailSafe ? 100 : fanDutyPct(g_temp, g_state);
            applyFan(g_duty);
        }

        // BF-5: Calcular RPM após atualizar duty
        updateRpm(now);

        applyRelay(g_state == ST_CRITICAL);
        applyLEDs(g_state, g_ntcValid);  // BF-6: termômetro progressivo

        if (g_ntcValid && isfinite(g_temp)) {
            Serial.printf(
                "[RS50H] T=%5.1f°C  Fan=%3d%%  RPM=%4u(%s)  Relay=%-7s  State=%-8s  NTCfault=%u  Heap=%u\n",
                g_temp, g_duty, g_rpm, RPM_SRC,
                g_relayOpen ? "ABERTO" : "fechado",
                stName(g_state), g_ntcFaultStreak, ESP.getFreeHeap()
            );
            g_ntcAbsentLogged = false;
        } else {
            if (!g_ntcAbsentLogged || (now - g_lastNtcLogMs) >= NTC_LOG_THROTTLE_MS) {
                g_lastNtcLogMs = now;
                g_ntcAbsentLogged = true;
                Serial.printf(
                    "[RS50H] T=--.--°C  Fan=%3d%%  RPM=%4u  Relay=%-7s  State=%-8s  NTCfault=%u  Heap=%u  [sensor ausente]\n",
                    g_duty, g_rpm,
                    g_relayOpen ? "ABERTO" : "fechado",
                    stName(g_state), g_ntcFaultStreak, ESP.getFreeHeap()
                );
            }
        }
    }

    if ((g_wifiOk || g_apMode) && now - g_lastWsBcast >= WS_INTERVAL_MS) {
        g_lastWsBcast = now;
        broadcastWs();
    }

    if (g_wifiOk && now - g_lastUdpBcast >= UDP_INTERVAL_MS) {
        g_lastUdpBcast = now;
        broadcastUdp();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// BF-5: Cálculo de RPM — estimado por duty ou medido por tachômetro
// ─────────────────────────────────────────────────────────────────────────────
static void updateRpm(uint32_t now) {
#if defined(PIN_FAN_TACH) && PIN_FAN_TACH >= 0
    // Janela de medição de 1 s (2 amostras de 500 ms → acumulamos e dividimos)
    static uint32_t lastTachMs     = 0;
    static uint32_t lastTachCount  = 0;
    uint32_t elapsed = now - lastTachMs;
    if (elapsed >= 1000UL) {
        noInterrupts();
        uint32_t cnt = g_tachPulses;
        interrupts();
        uint32_t delta = cnt - lastTachCount;
        lastTachCount  = cnt;
        lastTachMs     = now;
        // 2 pulsos/revolução; elapsed em ms → RPM = (pulsos/2) * (60000/elapsed)
        g_rpm = (uint16_t)((uint32_t)delta * 30000UL / elapsed);
    }
    // Se elapsed < 1000 ms, mantém o último g_rpm válido
#else
    // Estimativa linear: 0% → 0 RPM, 100% → RPM_ESTIMATED_MAX
    // Nota: fan físico pode girar abaixo do mínimo de hardware mesmo com duty=0.
    // O firmware reporta o RPM *comandado*, não a rotação residual de hardware.
    g_rpm = (uint16_t)((uint32_t)g_duty * RPM_ESTIMATED_MAX / 100UL);
#endif
}

// ─────────────────────────────────────────────────────────────────────────────
static void pruneUnauthedWsClients() {
    uint32_t now = millis();
    for (uint8_t i = 0; i < WS_MAX_CLIENTS; i++) {
        if (g_wsConnectedAt[i] != 0 && !g_wsAuthed[i] &&
            (now - g_wsConnectedAt[i]) >= WS_AUTH_TIMEOUT_MS) {
            Serial.printf("[WS] client #%u timeout sem AUTH — desconectado\n", i);
            g_ws.disconnect(i);
            g_wsConnectedAt[i] = 0;
        }
    }
}

static float readNTC() {
    uint32_t sum = 0;
    for (uint8_t i = 0; i < NTC_SAMPLES; i++) {
        sum += analogRead(PIN_NTC);
        delayMicroseconds(200);
    }
    float adc = (float)sum / NTC_SAMPLES;

    if (adc < 50.0f || adc > 4045.0f) {
        if (g_ntcValid) {
            Serial.printf("[NTC] ADC fora de faixa: %.1f — sensor desconectado?\n", adc);
        }
        g_ntcValid = false;
        if (g_ntcFaultStreak < UINT16_MAX) g_ntcFaultStreak++;
        return NAN;
    }

    float resistance = NTC_SERIES_R / ((4095.0f / adc) - 1.0f);
    float steinhart;
    steinhart  = resistance / NTC_R_NOMINAL;
    steinhart  = log(steinhart);
    steinhart /= NTC_B_COEFFICIENT;
    steinhart += 1.0f / (NTC_T_NOMINAL + 273.15f);
    steinhart  = 1.0f / steinhart;
    float tempC = steinhart - 273.15f;

    if (tempC < TEMP_MIN_VALID || tempC > TEMP_MAX_VALID) {
        if (g_ntcValid) {
            Serial.printf("[NTC] Temperatura fora de faixa: %.1f°C\n", tempC);
        }
        g_ntcValid = false;
        if (g_ntcFaultStreak < UINT16_MAX) g_ntcFaultStreak++;
        return NAN;
    }

    if (!g_ntcValid) {
        Serial.printf("[NTC] Sensor recuperado — T=%.1f°C\n", tempC);
    }
    g_ntcValid = true;
    g_ntcFaultStreak = 0;

    return tempC;
}

static ThermalState nextState(float temp, ThermalState prev) {
    switch (prev) {
        case ST_IDLE:
            if (!isfinite(temp) || temp >= g_tCrit) return ST_CRITICAL;
            if (temp >= g_tWarn) return ST_WARNING;
            if (temp >= g_tFanOn) return ST_WARMING;
            return ST_IDLE;
        case ST_WARMING:
            if (!isfinite(temp) || temp >= g_tCrit) return ST_CRITICAL;
            if (temp >= g_tWarn) return ST_WARNING;
            if (temp <  g_tFanOn) return ST_IDLE;
            return ST_WARMING;
        case ST_WARNING:
            if (!isfinite(temp) || temp >= g_tCrit) return ST_CRITICAL;
            if (temp <  g_tFanOn) return ST_IDLE;
            if (temp <  g_tWarn)  return ST_WARMING;
            return ST_WARNING;
        case ST_CRITICAL:
            // FSM-2: só sai de CRITICAL com temperatura confirmada abaixo de g_tRest
            if (isfinite(temp) && temp < g_tRest) return ST_RESTART;
            return ST_CRITICAL;
        case ST_RESTART:
            if (!isfinite(temp) || temp >= g_tCrit) return ST_CRITICAL;
            if (temp >= g_tWarn)  return ST_WARNING;
            if (temp >= g_tFanOn) return ST_WARMING;
            return ST_IDLE;
    }
    return ST_IDLE;
}

static uint8_t fanDutyPct(float temp, ThermalState st) {
    if (st == ST_CRITICAL || !isfinite(temp)) return 100;
    if (temp >= g_tWarn)  return 100;
    if (temp <  g_tFanOn) return 0;
    float ratio = (temp - g_tFanOn) / (g_tWarn - g_tFanOn);
    return (uint8_t)(constrain(ratio, 0.0f, 1.0f) * 100.0f);
}

static void applyFan(uint8_t pct) {
    ledcWrite(LEDC_CHAN_FAN, map(pct, 0, 100, 0, 255));
}

static void applyRelay(bool open) {
    if (open == g_relayOpen) return;
    g_relayOpen = open;
    digitalWrite(PIN_RELAY, open ? HIGH : LOW);
    Serial.printf("[RELAY] %s\n", open ? "ABERTO — emergência!" : "fechado — motor OK");
}

// ─────────────────────────────────────────────────────────────────────────────
// BF-6: LEDs WS2812 — Termômetro Progressivo + Animações de Estado
// ─────────────────────────────────────────────────────────────────────────────
// Comportamento por estado:
//   NTC fault  → pulso magenta: 500 ms on / 500 ms off (todos os 5 LEDs)
//   CRITICAL   → pisca vermelho: 300 ms on / 300 ms off (todos os 5 LEDs)
//   IDLE       → termômetro azul: 0–2 LEDs (escala 0→g_tFanOn)
//   WARMING    → termômetro verde: 2–3 LEDs (escala g_tFanOn→g_tWarn)
//   WARNING    → termômetro âmbar: 3–5 LEDs; LED do topo pulsa (800 ms)
//   RESTART    → termômetro roxo: escala 0→g_tCrit
//
// Escala geral do termômetro: 0°C → 0 LEDs; g_tCrit → 5 LEDs (linear).
// O número de LEDs acesos reflete a temperatura em tempo real.
// ─────────────────────────────────────────────────────────────────────────────
static void applyLEDs(ThermalState st, bool ntcOk) {
    uint32_t now = millis();

    fill_solid(g_leds, NUM_LEDS, CRGB::Black);

    if (!ntcOk) {
        // Falha NTC: todos pulsam magenta (500 ms on/off)
        if (now % 1000UL < 500UL) {
            fill_solid(g_leds, NUM_LEDS, CRGB::Magenta);
        }
        FastLED.show();
        return;
    }

    if (st == ST_CRITICAL) {
        // CRITICAL: todos piscam vermelho rápido (300 ms on/off)
        if (now % 600UL < 300UL) {
            fill_solid(g_leds, NUM_LEDS, CRGB::Red);
        }
        FastLED.show();
        return;
    }

    // Termômetro: cor por estado
    CRGB stateColor;
    switch (st) {
        case ST_IDLE:     stateColor = CRGB::Blue;        break;
        case ST_WARMING:  stateColor = CRGB::Green;       break;
        case ST_WARNING:  stateColor = CRGB(255, 140, 0); break;  // âmbar
        case ST_RESTART:  stateColor = CRGB(128, 0, 128); break;  // roxo
        default:          stateColor = CRGB::White;       break;
    }

    // Número de LEDs acesos: mapeado linearmente de 0°C a g_tCrit
    int numLit = 0;
    if (isfinite(g_temp) && g_tCrit > 0.0f) {
        float ratio = g_temp / g_tCrit;
        numLit = (int)(constrain(ratio, 0.0f, 1.0f) * (float)NUM_LEDS + 0.5f);
        // Garante ao menos 1 LED aceso quando temp > 5°C (para dar feedback visual)
        if (numLit == 0 && g_temp > 5.0f) numLit = 1;
    }

    // WARNING: LED do topo (último aceso) pulsa para indicar proximidade ao CRITICAL
    bool pulseTop = (st == ST_WARNING);
    bool topOn    = (now % 800UL < 400UL);

    for (uint8_t i = 0; i < NUM_LEDS; i++) {
        if (i < (uint8_t)numLit) {
            bool isTop = (i == (uint8_t)(numLit - 1));
            if (pulseTop && isTop) {
                g_leds[i] = topOn ? stateColor : CRGB::Black;
            } else {
                g_leds[i] = stateColor;
            }
        }
        // else: permanece Black (já feito por fill_solid acima)
    }

    FastLED.show();
}

static void setupWifi() {
    Serial.printf("[WiFi] Conectando a '%s'", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.persistent(false);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    uint8_t tries = 0;
    while (WiFi.status() != WL_CONNECTED && tries++ < 20) {
        delay(500);
        Serial.print('.');
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
        g_wifiOk = true;
        Serial.printf("[WiFi] OK — %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("[WiFi] Timeout — STA falhou");
    }
}

static void startApFallback() {
    Serial.println("[WiFi] Subindo AP de emergência...");
    WiFi.mode(WIFI_AP);
    if (WiFi.softAP(AP_FALLBACK_SSID, AP_FALLBACK_PASS)) {
        g_apMode = true;
        Serial.printf("[WiFi] AP '%s' em %s\n", AP_FALLBACK_SSID, WiFi.softAPIP().toString().c_str());
    } else {
        Serial.println("[WiFi] AP fallback falhou");
    }
}

static void tryRecoverSta() {
    Serial.println("[WiFi] AP ativo — tentando voltar para STA...");
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    uint32_t deadline = millis() + 5000UL;
    while (millis() < deadline && WiFi.status() != WL_CONNECTED) {
        g_http.handleClient();
        g_ws.loop();
        pruneUnauthedWsClients();
        esp_task_wdt_reset();
        delay(50);
    }
    if (WiFi.status() == WL_CONNECTED) {
        g_apMode = false;
        g_wifiOk = true;
        Serial.printf("[WiFi] STA recuperado — %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("[WiFi] STA ainda indisponível — voltando ao AP");
        startApFallback();
    }
}

static void setupOTA() {
    ArduinoOTA.setHostname(DEVICE_NAME);
    ArduinoOTA.setPort(OTA_PORT);
    ArduinoOTA.setPassword(OTA_PASSWORD);
    ArduinoOTA.onStart([]() {
        Serial.println("[OTA] Iniciando atualização...");
        g_otaActive = true;
        applyFan(OTA_FAN_DUTY_PCT);
        applyRelay(false);
        fill_solid(g_leds, NUM_LEDS, CRGB::Magenta);
        FastLED.show();
    });
    ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
        static uint8_t lastPct = 255;
        uint8_t pct = (uint8_t)(progress * 100 / total);
        if (pct != lastPct) {
            lastPct = pct;
            Serial.printf("[OTA] %3d%%\r", pct);
            esp_task_wdt_reset();
        }
    });
    ArduinoOTA.onEnd([]() {
        Serial.println("\n[OTA] Concluído — reiniciando...");
    });
    ArduinoOTA.onError([](ota_error_t err) {
        Serial.printf("[OTA] Erro %u\n", (unsigned)err);
        g_otaActive = false;
    });
    ArduinoOTA.begin();
    Serial.printf("[OTA] Pronto em %s.local:%u (com senha)\n", DEVICE_NAME, OTA_PORT);
}

static bool parseJsonFloat(const String& body, const char* key, float& out) {
    String searchKey = String("\"") + key + "\"";
    int keyPos = body.indexOf(searchKey);
    if (keyPos < 0) return false;
    int colonPos = body.indexOf(':', keyPos + (int)searchKey.length());
    if (colonPos < 0) return false;
    int valuePos = colonPos + 1;
    while (valuePos < (int)body.length() && body[valuePos] == ' ') valuePos++;
    char c = (valuePos < (int)body.length()) ? body[valuePos] : '\0';
    if (c != '-' && c != '.' && (c < '0' || c > '9')) return false;
    out = body.substring(valuePos).toFloat();
    return true;
}

static bool validateThresholds(float fanOn, float warn, float crit, float rest) {
    if (fanOn < CFG_MIN_TEMP || fanOn > CFG_MAX_TEMP) return false;
    if (warn  < CFG_MIN_TEMP || warn  > CFG_MAX_TEMP) return false;
    if (crit  < CFG_MIN_TEMP || crit  > CFG_MAX_TEMP) return false;
    if (rest  < CFG_MIN_TEMP || rest  > CFG_MAX_TEMP) return false;
    if (!(fanOn < warn && warn < crit)) return false;
    if (!(fanOn < rest && rest < warn)) return false;
    return true;
}

static void setupHttpRoutes() {
    g_http.on("/", HTTP_GET, []() {
        if (!httpAuthOk()) return;
        g_http.send_P(200, "text/html", DASHBOARD_HTML);
    });

    g_http.on("/ws-token", HTTP_GET, []() {
        if (!httpAuthOk()) return;
        generateWsToken();
        String body = "{\"token\":\"";
        body += g_wsToken;
        body += "\",\"ttl_ms\":";
        body += String((uint32_t)WS_TOKEN_TTL_MS);
        body += "}";
        g_http.send(200, "application/json", body);
    });

    g_http.on("/status", HTTP_GET, []() {
        if (!httpAuthOk()) return;
        g_http.send(200, "application/json", buildJson(false));
    });

    g_http.on("/config", HTTP_POST, []() {
        if (!httpAuthOk()) return;
        String body = g_http.arg("plain");
        float prevOn = g_tFanOn, prevWarn = g_tWarn, prevCrit = g_tCrit, prevRest = g_tRest;
        parseJsonFloat(body, "fan_on", g_tFanOn);
        parseJsonFloat(body, "warn",   g_tWarn);
        parseJsonFloat(body, "crit",   g_tCrit);
        parseJsonFloat(body, "rest",   g_tRest);
        if (validateThresholds(g_tFanOn, g_tWarn, g_tCrit, g_tRest)) {
            savePrefs();
            g_http.send(200, "application/json", "{\"ok\":true}");
        } else {
            g_tFanOn = prevOn; g_tWarn = prevWarn; g_tCrit = prevCrit; g_tRest = prevRest;
            g_http.send(400, "application/json",
                "{\"ok\":false,\"err\":\"invalid\","
                "\"hint\":\"require 0<=values<=100 AND fan_on<warn<crit AND fan_on<rest<warn\"}");
        }
    });

    g_http.onNotFound([]() {
        g_http.sendHeader("Location", "/", true);
        g_http.send(302, "text/plain", "");
    });
}

static bool httpAuthOk() {
    if (!g_http.authenticate(HTTP_AUTH_USER, HTTP_AUTH_PASS)) {
        g_http.requestAuthentication(BASIC_AUTH, "RS50H", "Auth required");
        return false;
    }
    return true;
}

static void generateWsToken() {
    uint32_t r1 = esp_random();
    uint32_t r2 = esp_random();
    snprintf(g_wsToken, sizeof(g_wsToken), "%08x%08x", r1, r2);
    g_wsTokenIssuedMs = millis();
}

static String computeUdpToken(uint32_t bucketMs) {
    uint32_t hash = 2166136261u;
    auto mix = [&](uint8_t b){ hash ^= b; hash *= 16777619u; };
    for (int i = 0; i < 4; i++) mix((bucketMs >> (i * 8)) & 0xFF);
    const char* s = UDP_SHARED_SECRET;
    while (*s) mix((uint8_t)*s++);
    char buf[9];
    snprintf(buf, sizeof(buf), "%08x", hash);
    return String(buf);
}

static void broadcastWs() {
    String json = buildJson(false);
    for (uint8_t i = 0; i < WS_MAX_CLIENTS; i++) {
        if (g_wsAuthed[i]) {
            g_ws.sendTXT(i, json);
        }
    }
}

static void broadcastUdp() {
#if UDP_TOKEN_ENABLED
    String json = buildJson(true);
#else
    String json = buildJson(false);
#endif
    g_udp.beginPacket(IPAddress(255, 255, 255, 255), UDP_PORT);
    g_udp.print(json);
    g_udp.endPacket();
}

// BF-5: JSON_BUF_SZ aumentado de 320 → 384 para acomodar rpm + rpm_src
#define JSON_BUF_SZ 384
static_assert(JSON_BUF_SZ >= 320, "JSON_BUF_SZ insuficiente — mínimo seguro: 320");

static String buildJson(bool includeUdpToken) {
    uint32_t uptime = (millis() - g_bootMs) / 1000UL;
    char buf[JSON_BUF_SZ];

    // Sanitiza temperatura: NaN/Inf → "null" (JSON válido)
    char tField[16];
    if (isfinite(g_temp)) {
        snprintf(tField, sizeof(tField), "%.1f", g_temp);
    } else {
        strcpy(tField, "null");
    }

    int n = snprintf(buf, sizeof(buf),
        "{\"t\":%s,\"pwm\":%u,\"rpm\":%u,\"rpm_src\":\"%s\","
        "\"state\":\"%s\","
        "\"relay\":%s,\"ntc\":%s,\"ntc_faults\":%u,"
        "\"heap\":%u,\"uptime\":%lu,\"fw\":\"%s\",\"hw\":\"%s\","
        "\"cfg\":{\"fan_on\":%.1f,\"warn\":%.1f,\"crit\":%.1f,\"rest\":%.1f}}",
        tField, (unsigned)g_duty, (unsigned)g_rpm, RPM_SRC,
        stName(g_state),
        g_relayOpen ? "true"  : "false",
        g_ntcValid  ? "true"  : "false",
        (unsigned)g_ntcFaultStreak, (unsigned)ESP.getFreeHeap(),
        (unsigned long)uptime, FW_VERSION, HW_MODEL,
        g_tFanOn, g_tWarn, g_tCrit, g_tRest);

    if (includeUdpToken && n > 0 && n < (int)sizeof(buf) - 50) {
        buf[n - 1] = '\0';
        uint32_t bucket = millis() / UDP_TOKEN_BUCKET_MS;
        String tok = computeUdpToken(bucket);
        char extra[64];
        snprintf(extra, sizeof(extra), ",\"bucket\":%lu,\"tok\":\"%s\"}",
                 (unsigned long)bucket, tok.c_str());
        strncat(buf, extra, sizeof(buf) - strlen(buf) - 1);
    }

    return String(buf);
}

static const char* stName(ThermalState s) {
    switch (s) {
        case ST_IDLE:     return "IDLE";
        case ST_WARMING:  return "WARMING";
        case ST_WARNING:  return "WARNING";
        case ST_CRITICAL: return "CRITICAL";
        case ST_RESTART:  return "RESTART";
        default:          return "UNKNOWN";
    }
}

static void loadPrefs() {
    g_prefs.begin("rs50h", true);
    float fanOn = g_prefs.getFloat("fan_on", TEMP_FAN_ON);
    float warn  = g_prefs.getFloat("warn",   TEMP_WARNING);
    float crit  = g_prefs.getFloat("crit",   TEMP_CRITICAL);
    float rest  = g_prefs.getFloat("rest",   TEMP_RESTART);
    g_prefs.end();

    if (validateThresholds(fanOn, warn, crit, rest)) {
        g_tFanOn = fanOn; g_tWarn = warn; g_tCrit = crit; g_tRest = rest;
        Serial.printf("[NVS] Thresholds: fan_on=%.1f warn=%.1f crit=%.1f rest=%.1f\n",
                      g_tFanOn, g_tWarn, g_tCrit, g_tRest);
    } else {
        g_tFanOn = TEMP_FAN_ON; g_tWarn = TEMP_WARNING;
        g_tCrit  = TEMP_CRITICAL; g_tRest = TEMP_RESTART;
        Serial.printf("[NVS] Valores corrompidos (%.1f/%.1f/%.1f/%.1f) — usando defaults\n",
                      fanOn, warn, crit, rest);
    }
}

static void savePrefs() {
    g_prefs.begin("rs50h", false);
    g_prefs.putFloat("fan_on", g_tFanOn);
    g_prefs.putFloat("warn",   g_tWarn);
    g_prefs.putFloat("crit",   g_tCrit);
    g_prefs.putFloat("rest",   g_tRest);
    g_prefs.end();
    Serial.println("[NVS] Thresholds persistidos");
}
