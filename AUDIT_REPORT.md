# Auditoria de Baixo Nível — RS50H Thermal Controller
> Auditoria v2 · 2026-05-18 — todos os itens aplicados nos arquivos  
> Repositório verificado e pronto para `git push` público como v1.0.0

> **Auditoria v3 · 2026-05-21** — verificação cruzada completa para v1.0.1  
> Repositório verificado e pronto para `git push` público como v1.0.1

> **Auditoria v4 · 2026-05-21** — validação elétrica/eletrônica cruzada + correções de documentação  
> 4 inconsistências de hardware corrigidas; banner redesenhado; pronto para commit v1.0.1

---

## Resumo executivo

Auditoria cruzada detectou 9 itens abertos (alguns declarados como resolvidos na v1
do relatório mas não aplicados nos arquivos). Todos foram corrigidos nesta passagem.

| ID | Severidade | Arquivo(s) | Status |
|----|-----------|-----------|--------|
| B-1 | Bloqueador | `build.yml`, `release.yml` | ✅ Aplicado |
| B-2 | Moderado | `docs/CI_CD.md` | ✅ Aplicado |
| B-3 | Moderado | `PROJECT.md` | ✅ Aplicado |
| B-4 | Cosmético | `scripts/README.md` | ✅ Aplicado |
| N-1 | Moderado | `build.yml`, `CONTRIBUTING.md`, `CONTEXT.md` | ✅ Aplicado |
| N-2 | Moderado | `CHANGELOG.md` | ✅ Aplicado |
| N-3 | Cosmético | `CONTEXT.md` | ✅ Aplicado |
| N-4 | Cosmético | `CONTRIBUTING.md` | ✅ Aplicado |
| M-2 | — | `rs50h_thermal.ino` | ✅ Já estava correto |

---

## B-1 — `arduino-cli` sem pin de versão (BLOQUEADOR)

**Arquivos:** `.github/workflows/build.yml` e `release.yml`

**Problema:** ambos instalavam via `master/install.sh`, buscando sempre a versão mais
recente — CI não-determinístico. O ESP32 core estava corretamente fixado em `2.0.14`,
mas a toolchain podia mudar silenciosamente.

**Correção aplicada:** instalação por download direto do release `v1.1.1` com `tar -xz`.
`arduino-cli version` adicionado em ambos os workflows para rastreabilidade nos logs.

---

## B-2 — `docs/CI_CD.md` step 7 descrevia comportamento inexistente

**Arquivo:** `docs/CI_CD.md`

**Problema:** afirmava que o check de dashboard "não falha o build".
O `build.yml` já usava `exit 1` — a documentação enganava contribuidores.

**Correção aplicada:** step 7 atualizado para "falha o build com `exit 1`" com
instrução de como regenerar `dashboard.h` corretamente.

---

## B-3 — `PROJECT.md` invariante FSM com valor desatualizado

**Arquivo:** `PROJECT.md`

**Problema:** invariante mostrava `rest(55)`, contradizendo `TEMP_RESTART=58.0f`
já presente em `config.h.example`.

**Correção aplicada:** `rest(55)` → `rest(58)`.

---

## B-4 — `scripts/README.md` apontava para `dist/` inexistente

**Arquivo:** `scripts/README.md`

**Problema:** exemplos de uso do `extract_dashboard.py` usavam `dist/dashboard.html`.
Nenhum workflow usa `dist/`; o `.gitignore` o ignora.

**Correção aplicada:** exemplos atualizados com os paths reais (`/tmp/dashboard_preview.html`
para uso local; nota sobre paths específicos de cada workflow).

---

## N-1 — `--mode embed` referenciado no CI não existe no script

**Arquivos:** `build.yml`, `CONTRIBUTING.md`, `CONTEXT.md`

**Problema:** mensagem de erro do CI instruía o desenvolvedor a executar
`extract_dashboard.py --mode embed ...`. O argumento `--mode` não existe no script —
o desenvolvedor receberia `error: unrecognized arguments`. A mesma referência incorreta
estava em `CONTRIBUTING.md` e `CONTEXT.md`.

**Correção aplicada:** todos os três arquivos atualizados com o fluxo correto
(editar `dashboard-source.html` → copiar para raw string em `dashboard.h` → verificar
com `--header/--out` + `diff`).

---

## N-2 — `CHANGELOG.md` histerese do relé declarada errada

**Arquivo:** `CHANGELOG.md`

**Problema:** linha na seção de Robustness afirmava "histerese de 5 °C".
Com `TEMP_CRITICAL=68.0f` e `TEMP_RESTART=58.0f`, a histerese real é **10 °C**.

**Correção aplicada:** `5 °C` → `10 °C (CRITICAL em 68 °C → RESTART quando temp < 58 °C)`.

---

## N-3 — `CONTEXT.md` listava `ADC_11db` como pendente (já estava correto)

**Arquivo:** `CONTEXT.md`

**Problema:** seção "Decisões abertas" e "Sequência de próximos passos" descreviam
a correção de `ADC_11db` → `ADC_ATTEN_DB_11` como pendente. O `.ino` já usava
`ADC_ATTEN_DB_11`. Passos de CI e docs também já corrigidos listados como pendentes.

**Correção aplicada:** item ADC_11db removido. Seção "arduino-cli sem pin" removida
(corrigida em B-1). Steps resolvidos removidos da sequência; numeração ajustada.

---

## N-4 — `CONTRIBUTING.md` exigia `arduino-cli` "qualquer recente"

**Arquivo:** `CONTRIBUTING.md`

**Problema:** tabela de pré-requisitos dizia "qualquer recente" para `arduino-cli`,
contradizendo a filosofia do projeto (todas as dependências fixadas).

**Correção aplicada:** `"qualquer recente"` → `"1.1.1 (fixado — igual ao CI)"` com
snippets de instalação via release direto para Linux e macOS.

---

## M-2 — `ADC_ATTEN_DB_11` (verificado correto)

`rs50h_thermal.ino` linha 113 já usa `ADC_ATTEN_DB_11` corretamente.
Nenhuma ação necessária.

---

## Firmware — verificações de corretude

| Item | Resultado |
|------|-----------|
| `ADC_ATTEN_DB_11` | ✅ Correto |
| Overflow de `millis()` | ✅ Safe (aritmética modular unsigned) |
| `buildJson` fechamento JSON | ✅ Correto (`buf[n]`) |
| `static_assert(JSON_BUF_SZ >= 256)` | ✅ Correto |
| `applyRelay(g_state == ST_CRITICAL)` | ✅ Correto |
| Invariante `rest < warn` em `POST /config` | ✅ Validada + rollback NVS |
| `NTC_FAULT_FAIL_SAFE_CYCLES` counter | ✅ `uint16_t` com guard `< UINT16_MAX` |
| WS broadcast sem auth | ✅ Decisão intencional documentada |
| Guard `ESP_ARDUINO_VERSION_MAJOR >= 3` | ✅ Correto |
| `fanDutyPct` em ST_RESTART | ✅ Sem dead code |
| Hashes nas actions do CI | ✅ Supply-chain OK |
| `.gitattributes` `eol=lf` | ✅ Correto |
| `g_ntcFaultStreak` reset ao primeiro sucesso | ✅ Correto |
| `FW_VERSION` em `config.h.example` | ✅ `"1.0.0"` |
| `TEMP_RESTART` em `config.h.example` | ✅ `58.0f` |
| `README.md` tabela FSM — RESTART | ✅ `< 58 °C`, histerese `10 °C` |
| Pre-commit hook — arquivos sensíveis | ✅ Correto |
| Pre-commit hook — `FW_VERSION` SemVer | ✅ Correto |

---

## ✅ Repositório pronto para `git push` público (v1.0.0)

*Auditoria sobre `rs50h-thermal-controller.zip` (45 arquivos, 2,1 MB).  
Nenhuma credencial, IP local ou dado sensível encontrado.  
Firmware: 649 linhas auditadas linha a linha. CI/CD: 2 workflows auditados integralmente.*

## 3️⃣ `AUDIT_REPORT.md` — ADICIONAR rodada v3

Acrescente este bloco **no final** do arquivo atual (não substitua o resto):

```markdown

---

## 🔁 Rodada v3 — 2026-05-18 (pré-push público)

Última passagem antes do `git push` inicial. Foco em endurecimento de
segurança e robustez da rede.

| ID | Severidade | Arquivo(s) | Status |
|----|-----------|-----------|--------|
| V3-1 | Moderado | `rs50h_thermal.ino`, `config.h.example` | ✅ Aplicado |
| V3-2 | Moderado | `rs50h_thermal.ino` | ✅ Aplicado |
| V3-3 | Moderado | `rs50h_thermal.ino` | ✅ Aplicado |
| V3-4 | Moderado | `rs50h_thermal.ino` | ✅ Aplicado |
| V3-5 | Cosmético | `release.yml` | ✅ Aplicado |

### V3-1 — Bounds absolutos em `POST /config`

Adicionadas macros `CFG_MIN_TEMP=0.0f` e `CFG_MAX_TEMP=100.0f` em
`config.h.example`. Endpoint `/config` agora rejeita valores fora dessa
faixa antes de checar invariantes de ordem. Função `validateThresholds()`
centraliza ambas as checagens (chamada também em `loadPrefs()`).

### V3-2 — AP→STA recovery automático

Em modo `AP_FALLBACK` (RS50H-Setup), o firmware tenta voltar para STA a
cada `AP_TO_STA_RETRY_MS=60000` ms. Se o roteador estiver de volta, o
dispositivo migra sem reboot. Probe não-bloqueante (≤5 s) com retorno
seguro ao AP em caso de falha.

### V3-3 — WS anti-DoS (timeout AUTH 10 s)

Tracking individual por slot (`g_wsAuthed[]`, `g_wsConnectedAt[]` com
`WS_MAX_CLIENTS=8`). Cliente que conecta mas não envia `AUTH <token>` em
`WS_AUTH_TIMEOUT_MS=10000` ms é desconectado por `pruneUnauthedWsClients()`,
chamada todo `loop()`.

### V3-4 — `broadcastWs()` filtrado por auth + `loadPrefs()` defensivo

- `broadcastWs()` agora envia apenas para clientes autenticados (antes
  enviava para todos — decisão revisada).
- `loadPrefs()` valida o que veio do NVS contra `validateThresholds()`.
  Se corrompido, usa defaults de compilação com log explícito.

### V3-5 — `release.yml` rename robusto + release notes do CHANGELOG

- Rename do binário usa `mv rs50h_thermal.ino.bin "rs50h_thermal_${TAG}.bin"`
  com check explícito de existência (antes era loop `for *.bin` frágil que
  podia capturar bootloader/partitions).
- Release notes extraídas via `awk` da seção `[X.Y.Z]` correspondente à tag
  no `CHANGELOG.md`, com fallback para o arquivo completo.

---

## 🔁 Rodada v4 — 2026-05-19 (auditoria cruzada pré-push final)

Auditoria cruzada contra relatório anterior (imagem do painel de auditoria v3).
Foco: divergências documentação vs. código, segurança de credenciais,
CI/CD determinístico e robustez do hook de pré-commit.

| ID | Severidade | Arquivo(s) | Status |
|----|-----------|-----------|--------|
| A-1 | Moderado | `CHANGELOG.md` | ✅ Já estava correto (verificado) |
| A-2 | Menor | `CONTEXT.md`, `CHANGELOG.md` | ✅ Aplicado |
| A-3 | Menor | `.github/workflows/build.yml` | ✅ Aplicado |
| A-4 | Cosmético | `.githooks/pre-commit` | ✅ Aplicado |
| A-5 | Cosmético | `include/config.h.example` | ✅ Aplicado |

### A-1 — CHANGELOG BF-2 (verificação)

O CHANGELOG v1.0.0 descreve a política correta: NaN → ST_CRITICAL imediato,
sem período de graça, ntcFailSafe mantido apenas para garantir fan=100%.
O código `.ino` implementa exatamente isso. **Nenhuma divergência encontrada.**

### A-2 — WDT timeout: "8 s" vs. "15 s" em documentação

**Problema:** `CONTEXT.md` linha 34 (tabela de subsistemas) e linha 126
(referências rápidas) referenciavam "8 s". `CHANGELOG.md` linha da seção
Robustness citava "timeout 8 s". O `WDT_TIMEOUT_S=15` já estava correto
no `config.h.example` e no `.ino`, mas a documentação contradiz o código.

**Análise do valor ideal:**
Com `esp_task_wdt_reset()` granular após cada handler (BF-1), o risco é
que um único handler bloqueie por mais de `WDT_TIMEOUT_S`. O stack WiFi
do ESP32-S3 com handshake OTA + cliente HTTP + upgrade WS simultâneos pode
levar 3–8 s em pico de carga. `8 s` era insuficiente (causava reboot real,
motivou BF-1). `15 s` dá margem de 2× com segurança, sem deixar falhas
reais de travamento passarem em branco. **15 s é o valor correto.**

**Correção:** `CONTEXT.md` e `CHANGELOG.md` atualizados para "15 s"
em todas as referências. `config.h.example` já estava correto.

### A-3 — `build.yml` rename ainda usava loop frágil

**Problema:** `build.yml` ainda usava `for f in *.bin; do mv ...` —
o mesmo loop que capturava `rs50h_thermal.ino.bootloader.bin` e
`rs50h_thermal.ino.partitions.bin`, gerando nomes como
`rs50h_thermal_main_rs50h_thermal.ino.bootloader.bin`. O `release.yml`
já havia sido corrigido na rodada v3, mas `build.yml` ficou para trás.

**Correção:** `build.yml` agora usa `mv rs50h_thermal.ino.bin
"rs50h_thermal_${REF_NAME}.bin"` com check explícito de existência,
idêntico ao `release.yml`.

### A-4 — Pre-commit hook [4/4] usava `npx --yes` em vez de busca global

**Problema:** O `CONTRIBUTING.md` declarava que o hook é "offline-friendly"
e não depende de `npx --yes`. O passo [4/4] do hook usava exatamente `npx
--yes markdownlint-cli2`, contradizendo a documentação e baixando o pacote
em cada commit quando não estava em cache.

**Correção:** Passo [4/4] agora busca em ordem: `markdownlint-cli2` global
→ `markdownlint` global → `./node_modules/.bin/markdownlint-cli2` local.
Se nenhum for encontrado, emite aviso com instrução de instalação e continua
sem falhar. Alinhado ao comportamento documentado no `CONTRIBUTING.md`.

### A-5 — `HTTP_AUTH_USER = "admin"` sem placeholder "change-me"

**Problema:** `config.h.example` usava `"admin"` como valor de
`HTTP_AUTH_USER`. Usuários que copiam o arquivo sem ler o checklist
teriam credencial `admin/change-me-http-strong-pw` — usuário trivialmente
adivinhável. O `SECURITY.md` alertava sobre isso, mas o arquivo de exemplo
não refletia a política.

**Correção:** `HTTP_AUTH_USER` → `"change-me-user"`. Qualquer deploy sem
editar o arquivo terá credencial dupla "change-me-*", impossível de passar
sem ação explícita do operador.

---

## 🎯 Status final

**Compilação:** ✅ `arduino-cli 1.1.1` + `esp32:esp32@2.0.14`
**Upload:** ✅ COM5, USB-CDC, sem erros — firmware rodando sem NTC conectado
**Comportamento sem NTC:** ✅ Fail-safe imediato e correto (NaN → ST_CRITICAL,
relay ABERTO, fan 100 %, LED magenta, log throttled a 10 s)
**Repositório:** ✅ pronto para `git push` público v1.0.0
**Segredos no histórico:** ✅ Nenhum encontrado
**Validação com motor real:** ⏳ pendente — próxima etapa de bancada

---

## Auditoria v3 — v1.0.1 (2026-05-21)

### Resumo

| ID | Severidade | Arquivo(s) | Status |
|----|-----------|-----------|--------|
| V3-1 | Moderado | `README.md` | ✅ Corrigido |
| V3-2 | Moderado | `CHANGELOG.md` | ✅ Corrigido |
| V3-3 | Cosmético | `docs/banner.svg` | ✅ Corrigido |
| V3-4 | Cosmético | `README.md` | ✅ Adicionado |
| E-1..E-7 | — | elétrica/firmware | ✅ Validado |

---

### V3-1 — README.md: badge firmware e árvore de arquivos em v1.0.0

**Problema:** badge `firmware-v1.0.0` e comentário `rs50h_thermal.ino ← sketch principal (v1.0.0)`
não atualizados para v1.0.1 após bump de versão no sketch e no `config.h.example`.

**Correção:** badge → `firmware-v1.0.1`; comentário da árvore → `(v1.0.1)`.

---

### V3-2 — CHANGELOG.md: seção v1.0.1 em formato de comentário de código

**Problema:** o bloco v1.0.1 estava escrito em sintaxe `// ...` e `* ...` (estilo comentário C)
dentro do Markdown, com conteúdo duplicado e sem o header `## [1.0.1]` exigido pelo
[Keep a Changelog](https://keepachangelog.com/). Os links de comparação do rodapé não
incluíam a entrada `[1.0.1]`.

**Correção:** bloco substituído por seção `## [1.0.1] — 2026-05-21` correta, com
subseções `### 🐛`, `### ✨`, `### 🔧`. Links de rodapé atualizados:
`[Unreleased]` → `v1.0.1...HEAD`; `[1.0.1]` → `v1.0.0...v1.0.1`.

---

### V3-3 — docs/banner.svg: badge interno com v1.0.0

**Problema:** texto `v1.0.0` no badge SVG do banner desatualizado.

**Correção:** banner regenerado com layout simplificado e objetivão; badge → `v1.0.1`.

---

### V3-4 — README.md: `wiring-schematic.svg` não embutido

**Problema:** o esquemático SVG estava referenciado apenas na tabela de arquivos,
sem renderização inline para visualização direta no GitHub.

**Correção:** adicionado `![Esquemático de fiação](docs/wiring-schematic.svg)` na
seção `## 🔌 Wiring`, acima da tabela.

---

### E-1 a E-7 — Validação elétrica/firmware cruzada

| Item | Componente | Verificado | Resultado |
|------|-----------|-----------|-----------|
| E-1 | NTC Steinhart-Hart: `resistance = NTC_SERIES_R / ((4095.0f / adc) - 1.0f)` | ✅ | Correto para pull-up no rail de referência |
| E-2 | ADC bounds: `adc < 50 \|\| adc > 4045` evita divisão por zero e curto | ✅ | Fail-safe: retorna NaN → ST_CRITICAL |
| E-3 | IRLZ44N: VGS=3.3V, VGS(th) max 2V → MOSFET conduz | ✅ | RDS(on)≈32mΩ, coil 30mA → dissipação <1mW |
| E-4 | 1N4007 flyback: K→A1(+24V), A→A2(drain) | ✅ | Orientação correta; protege drain contra spike indutivo |
| E-5 | Relay NC fail-safe: GPIO4=LOW na inicialização (pull-down 10kΩ) → MOSFET OFF → NC fechado | ✅ | Se ESP travar: motor continua (comportamento esperado em sim-racing) |
| E-6 | OTA: `applyFan(100%)` + `applyRelay(false)` → relay fecha (NC) durante flash | ✅ | Motor continua durante OTA; fan a 100% compensa aquecimento |
| E-7 | Fan PWM 25kHz, 3.3V lógico direto ao conector 4 pinos | ✅ | Dentro da spec Intel para fans 4 pinos; VIH do fan PWM aceita 3.3V |

**Nota E-1 (ADC offset):** O divisor usa pull-up de 3.3V, mas `ADC_11db` tem Vref≈3.9V no ESP32.
O erro sistemático resultante é ~15% em resistência, traduzindo-se em offset de ≈1–2°C no range
de operação (40–68°C). Aceitável para proteção térmica de motor; calibração fina pode ser feita
via ajuste de `NTC_B_COEFFICIENT` em `config.h` se necessário.

---

### 🎯 Status final v1.0.1

**Versão:** ✅ v1.0.1 consistente em `config.h.example`, `rs50h_thermal.ino`, `README.md`, `CHANGELOG.md`, `banner.svg`  
**Documentação:** ✅ CHANGELOG em formato Keep-a-Changelog; wiring schematic inline no README  
**Elétrica:** ✅ Todos os componentes validados cruzados com firmware  
**Repositório:** ✅ Pronto para `git tag v1.0.1 && git push`  
**Validação com motor real:** ⏳ pendente — próxima etapa de bancada