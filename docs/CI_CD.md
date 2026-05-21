# CI/CD — RS50H Thermal Controller

Documentação do pipeline de integração e entrega contínua.

---

## 🏗️ Workflows

| Arquivo | Disparo | Propósito |
|---------|---------|-----------|
| `build.yml` | Push em `main`, `develop`, `fix/*`, `feat/*`; PRs para `main` | Compila o firmware e sobe o `.bin` como artefato |
| `release.yml` | Push de tag `v[0-9]+.[0-9]+.[0-9]+` | Compila, extrai dashboard e cria GitHub Release |

---

## 🔧 Stack de Build

- **Ferramenta:** `arduino-cli` (sem PlatformIO)
- **Plataforma:** `esp32:esp32@2.0.14`
- **FQBN:** `esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled`
- **Bibliotecas:** declaradas em `ci/libraries.txt` com versões fixas

> **⚠️ Não atualizar o core além de 2.0.14** sem migrar as chamadas LEDC no firmware.
> A API `ledcSetup` / `ledcAttachPin` / `ledcWrite(channel, duty)` foi removida no core v3.x.

---

## 📦 `build.yml` — Build de Rotina

### Passos

1. **Checkout** — `actions/checkout@v4`
2. **Instalar arduino-cli** — via script oficial, binário em `/usr/local/bin`
3. **Configurar board index** — URL do índice Espressif ESP32
4. **Instalar plataforma** — `esp32:esp32@2.0.14` (fixado)
5. **Instalar bibliotecas** — lê `ci/libraries.txt`, instala cada linha
6. **Copiar config.h** — `cp include/config.h.example include/config.h`
7. **Verificar sincronismo dashboard** — compara `dashboard.h` extraído com `docs/dashboard-source.html`; **falha o build com `exit 1`** se dessincronizados. Para editar o dashboard: altere `docs/dashboard-source.html`, copie o HTML para dentro da raw string em `src/rs50h_thermal/dashboard.h`, e verifique: `python3 scripts/extract_dashboard.py --header src/rs50h_thermal/dashboard.h --out /tmp/check.html && diff /tmp/check.html docs/dashboard-source.html`
8. **Compilar firmware** — `arduino-cli compile --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled" ...`
9. **Renomear artefatos** — prefixo `rs50h_thermal_<ref>_`
10. **Upload de artefatos** — `actions/upload-artifact@v4`

### Flag de include

```yaml
--build-property "compiler.cpp.extra_flags=-I${{ github.workspace }}/include"
```

Necessário porque o `.ino` usa `#include "../../include/config.h"` — o flag
garante que o compilador encontra o header mesmo com caminhos relativos.

---

## 🚀 `release.yml` — Release Automático

Disparado por qualquer tag que corresponda a `v*.*.*`.

### Passos extras (além do build padrão)

1. **Renomear binário** — `rs50h_thermal_v1.0.0.bin`
2. **Extrair dashboard** — `scripts/extract_dashboard.py --header ... --out dashboard.html`
3. **Criar GitHub Release** — `softprops/action-gh-release@v2`
   - Nome: `RS50H Thermal Controller vX.Y.Z`
   - Body: seção `## [X.Y.Z]` extraída do `CHANGELOG.md` (não o arquivo inteiro)
   - Assets: `.bin` + `dashboard.html` (se extraído com sucesso)

---

## 📋 `ci/libraries.txt`

```
FastLED@3.6.0
WebSockets@2.4.1
```

Versões fixas para builds reproduzíveis. Ao atualizar uma biblioteca, altere aqui
e registre no `CHANGELOG.md`.

---

## 🔄 Fluxo de Release

```bash
# 1. Trabalhe em branch
git checkout -b fix/descricao

# 2. Commit (pre-commit roda automaticamente)
git add .
git commit -m "fix(scope): descricao"

# 3. Merge na main
git checkout main && git merge --no-ff fix/descricao

# 4. Tag — dispara release.yml automaticamente
git tag -a v1.0.1 -m "RS50H v1.0.1 descricao"
git push origin main --tags
```

Ou via PowerShell:

```powershell
.\scripts\ps\commit.ps1           # commit interativo
.\scripts\ps\03_push.ps1          # push main
.\scripts\ps\04_tag_release.ps1   # tag + push -> dispara release
.\scripts\ps\05_ci_watch.ps1      # monitora Actions em tempo real
```

---

## 🩹 Hotfix Rapido

```powershell
.\scripts\ps\06_hotfix.ps1 -Version 1.0.1 -Message "fix: descricao do hotfix"
```

O script: atualiza `FW_VERSION` em `config.h.example`, commita, faz push e cria a tag.

---

## 🔍 Diagnostico Local

```powershell
.\scripts\ps\00_AUDIT_REPORT.ps1   # verifica toda a estrutura do projeto
```

---

## 📎 Referencias

- [arduino-cli docs](https://arduino.github.io/arduino-cli/latest/)
- [ESP32 Arduino Core releases](https://github.com/espressif/arduino-esp32/releases)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)
