# Política de Segurança — RS50H Thermal Controller

## Escopo

Este projeto é firmware para uso em LAN doméstica / bancada de sim-racing.
O modelo de segurança protege o **controle** do dispositivo (dashboard, OTA,
thresholds) contra acesso não-autorizado na rede local. Não se destina a
deployment em redes públicas.

## Superfície de ataque relevante

| Vetor | Proteção implementada |
|-------|----------------------|
| OTA (ArduinoOTA) | Senha obrigatória via `OTA_PASSWORD` |
| Dashboard HTTP | HTTP Basic Auth (`HTTP_AUTH_USER` / `HTTP_AUTH_PASS`) |
| WebSocket | Token de sessão emitido após Basic Auth (`/ws-token`, TTL 10 min) |
| Thresholds (`/config`) | Exige Basic Auth; validação de ordem e bounds |
| Telemetria WS | Broadcast público na LAN — intencional (dados não-sensíveis) |
| UDP SimHub | Token FNV-1a opcional (`UDP_TOKEN_ENABLED`); desativado por padrão |

## Credenciais padrão — você DEVE alterar

O arquivo `include/config.h.example` contém placeholders que **nunca devem
ser usados em produção**:

```c
#define OTA_PASSWORD     "change-me-ota-pw"
#define HTTP_AUTH_USER   "admin"
#define HTTP_AUTH_PASS   "change-me-http-pw"
#define UDP_SHARED_SECRET "change-me-udp-secret"
```

Copie para `include/config.h` (gitignored) e substitua por valores reais
antes do primeiro deploy.

## Reportando vulnerabilidades

Se encontrar uma vulnerabilidade de segurança:

1. **Não abra uma issue pública** com detalhes do exploit.
2. Abra uma [GitHub Security Advisory](https://github.com/Jean-DrEaD/rs50h-thermal-controller/security/advisories/new)
   (privada por padrão) descrevendo o problema, versão afetada e impacto.
3. Aguarde confirmação antes de divulgação pública — prazo máximo de resposta: **7 dias**.

Vulnerabilidades em bibliotecas de terceiros (FastLED, WebSockets, ArduinoOTA)
devem ser reportadas diretamente aos respectivos projetos.
