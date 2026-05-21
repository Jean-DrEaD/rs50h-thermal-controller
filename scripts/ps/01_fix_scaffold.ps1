#Requires -Version 5.1
<# ═══════════════════════════════════════════════════════════════════════════════
   RS50H · Fix & Scaffold  (arduino-cli edition)
   Versão alvo: 1.0.0

   CORREÇÕES NESTA VERSÃO:
   · Git user.email lido do git config global (não sobrescrito)
   · Pre-commit hook reescrito com LF (bash não aceita CRLF)
   · Hook chama PowerShell — 100% compatível com Windows
   · config.h.example escrito sem BOM, com LF
   · Todos os arquivos de projeto gerados sem BOM/CRLF
═══════════════════════════════════════════════════════════════════════════════ #>
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent | Split-Path -Parent)

# ── Helper: escreve arquivo com UTF-8 sem BOM e line endings LF ──────────────
function Write-Utf8Lf {
    param([string]$Path, [string]$Content)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lf = $Content -replace "`r`n", "`n"
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($lf)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RS50H · Fix & Scaffold  (arduino-cli edition)                  ║" -ForegroundColor Cyan
Write-Host "║  Versão alvo: 1.0.0                                             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[0/10] Configurando git user (email + name)" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$email = git config user.email 2>$null
$name  = git config user.name  2>$null
if (-not $email) { Write-Host "    ⚠️  user.email não configurado — configure com: git config --global user.email <seu@email>" -ForegroundColor Yellow }
if (-not $name)  { Write-Host "    ⚠️  user.name não configurado  — configure com: git config --global user.name <seu nome>" -ForegroundColor Yellow }
if ($email -and $name) { Write-Host "    ✅ git config: $name <$email>" -ForegroundColor Green }

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[1/10] Criando estrutura de diretórios" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
@('docs','ci','.github\workflows','scripts\ps','include','src\rs50h_thermal') | ForEach-Object {
    if (Test-Path $_) { Write-Host "    ✅ Já existe: $_" -ForegroundColor DarkGray }
    else { New-Item -ItemType Directory -Path $_ -Force | Out-Null; Write-Host "    🔧 Criado: $_" -ForegroundColor Green }
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[2/10] Verificando include\config.h.example" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
# GUARD: preserva config.h.example existente se tiver os macros corretos do projeto real
$cfgExPath = "include\config.h.example"
$cfgExExists = (Test-Path $cfgExPath) -and ((Get-Content $cfgExPath -Raw) -match 'PIN_NTC|PIN_FAN_PWM|TEMP_CRITICAL')
if ($cfgExExists) {
    Write-Host "    ✅ config.h.example real detectado (contém macros PIN_NTC/PIN_FAN_PWM) — preservado." -ForegroundColor DarkGray
} else {
    # config.h.example ausente ou incompleto — abortar: não existe substituto correto aqui.
    # O arquivo real deve vir do repositório. Nunca gerar um placeholder com macros errados.
    Write-Host "    ❌ include\config.h.example ausente ou incompleto!" -ForegroundColor Red
    Write-Host "       Restaure-o do repositório: git checkout include/config.h.example" -ForegroundColor Yellow
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[3/10] Verificando src\rs50h_thermal\rs50h_thermal.ino" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
# GUARD: se o firmware real já existir (detectado por dashboard.h ou pelo tamanho > 5 KB),
# NÃO sobrescrever — 01_fix_scaffold.ps1 é um scaffolder inicial, não um reset destrutivo.
$inoPath = "src\rs50h_thermal\rs50h_thermal.ino"
$dashboardPath = "src\rs50h_thermal\dashboard.h"
$inoExists = (Test-Path $inoPath) -and ((Get-Item $inoPath).Length -gt 5000)
$dashboardExists = Test-Path $dashboardPath
if ($inoExists -or $dashboardExists) {
    Write-Host "    ✅ Firmware real detectado ($inoPath — $(if($inoExists){'> 5 KB'}else{'dashboard.h presente'})) — preservado sem alteração." -ForegroundColor DarkGray
    Write-Host "    ⚠️  Este script não sobrescreve firmware existente. Use git para gerenciar versões." -ForegroundColor Yellow
} else {
    Write-Host "    ❌ $inoPath ausente e dashboard.h não encontrado!" -ForegroundColor Red
    Write-Host "       Restaure do repositório: git checkout src/rs50h_thermal/" -ForegroundColor Yellow
    exit 1
}  # end guard

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[4/10] Removendo platformio.ini do controle de versão" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
git ls-files --error-unmatch "platformio.ini" 2>$null
if ($LASTEXITCODE -eq 0) {
    git rm --cached platformio.ini 2>$null | Out-Null
    Write-Host "    🔧 platformio.ini removido do git (arquivo mantido localmente)" -ForegroundColor Yellow
} else {
    Write-Host "    ✅ platformio.ini já fora do git" -ForegroundColor DarkGray
}
if (Test-Path "platformio.ini") {
    Rename-Item "platformio.ini" "platformio.ini.local-only" -Force -ErrorAction SilentlyContinue
    Write-Host "    🔧 platformio.ini → platformio.ini.local-only" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[5/10] Escrevendo ci\libraries.txt (formato arduino-cli)" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$librariesTxt = @'
# RS50H · Dependências de biblioteca (arduino-cli)
# Formato: NomeDaBiblioteca@versão
# Instaladas pelo workflow antes da compilação.
# Versões fixas para builds reproduzíveis.

FastLED@3.6.0
WebSockets@2.4.1
'@
Write-Utf8Lf "ci\libraries.txt" $librariesTxt
Write-Host "    ✅ ci/libraries.txt atualizado (formato arduino-cli ✅)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[6/10] Escrevendo .gitignore" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$gitignore = @'
# ── Configuração local (NUNCA commitar — contém credenciais) ─────────────────
include/config.h
*.local-only

# ── Build / arduino-cli ──────────────────────────────────────────────────────
build/
*.bin
*.elf
*.map
.cache/
__pycache__/

# ── PlatformIO (não usado em CI, mantido localmente apenas) ──────────────────
platformio.ini.local-only
.pio/
.pioenvs/

# ── IDEs e OS ────────────────────────────────────────────────────────────────
.vscode/
.idea/
*.code-workspace
.DS_Store
Thumbs.db
desktop.ini
'@
Write-Utf8Lf ".gitignore" $gitignore
Write-Host "    ✅ .gitignore escrito (include/config.h ignorado ✅)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[7/10] Escrevendo .github\workflows\build.yml (arduino-cli)" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$buildYml = @'
name: Build Firmware

on:
  push:
    branches: [main, develop, "fix/*", "feat/*"]
  pull_request:
    branches: [main]

jobs:
  build:
    name: arduino-cli · ESP32-S3
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install arduino-cli
        env:
          ARDUINO_CLI_VERSION: "1.1.1"
        run: |
          curl -fsSL \
            "https://github.com/arduino/arduino-cli/releases/download/v${ARDUINO_CLI_VERSION}/arduino-cli_${ARDUINO_CLI_VERSION}_Linux_64bit.tar.gz" \
            | tar -xz -C /usr/local/bin arduino-cli
          arduino-cli version

      - name: Configure arduino-cli (ESP32 index)
        run: |
          arduino-cli config init
          arduino-cli config set board_manager.additional_urls \
            https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

      - name: Install ESP32 platform
        # Pinado em 2.0.14 — API LEDC legada (ledcSetup/ledcAttachPin).
        # NÃO alterar para 3.x sem atualizar o firmware: ledcSetup foi removido no core v3.
        run: |
          arduino-cli core update-index
          arduino-cli core install esp32:esp32@2.0.14

      - name: Install libraries
        run: |
          while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            arduino-cli lib install "$line"
          done < ci/libraries.txt

      - name: Copy config.h from example
        run: cp include/config.h.example include/config.h

      - name: Compile firmware
        run: |
          arduino-cli compile \
            --fqbn esp32:esp32:esp32s3 \
            --build-path "${{ github.workspace }}/build" \
            --build-property "compiler.cpp.extra_flags=-I${{ github.workspace }}/include" \
            "${{ github.workspace }}/src/rs50h_thermal"

      - name: Rename artifacts
        run: |
          cd "${{ github.workspace }}/build"
          for f in *.bin; do
            mv "$f" "rs50h_thermal_${{ github.ref_name }}_${f}" 2>/dev/null || true
          done
          ls -lh *.bin

      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: rs50h-firmware-${{ github.sha }}
          path: build/*.bin
          if-no-files-found: error
'@
Write-Utf8Lf ".github\workflows\build.yml" $buildYml
Write-Host "    ✅ build.yml escrito (arduino-cli ✅, FQBN esp32:esp32:esp32s3 ✅)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[8/10] Escrevendo .github\workflows\release.yml (arduino-cli)" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$releaseYml = @'
name: Release

on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+"

jobs:
  release:
    name: Build & Publish Release
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install arduino-cli
        env:
          ARDUINO_CLI_VERSION: "1.1.1"
        run: |
          curl -fsSL \
            "https://github.com/arduino/arduino-cli/releases/download/v${ARDUINO_CLI_VERSION}/arduino-cli_${ARDUINO_CLI_VERSION}_Linux_64bit.tar.gz" \
            | tar -xz -C /usr/local/bin arduino-cli
          arduino-cli version

      - name: Configure arduino-cli (ESP32 index)
        run: |
          arduino-cli config init
          arduino-cli config set board_manager.additional_urls \
            https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

      - name: Install ESP32 platform
        # Pinado em 2.0.14 — API LEDC legada (ledcSetup/ledcAttachPin).
        # NÃO alterar para 3.x sem atualizar o firmware: ledcSetup foi removido no core v3.
        run: |
          arduino-cli core update-index
          arduino-cli core install esp32:esp32@2.0.14

      - name: Install libraries
        run: |
          while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            arduino-cli lib install "$line"
          done < ci/libraries.txt

      - name: Copy config.h from example
        run: cp include/config.h.example include/config.h

      - name: Compile firmware
        run: |
          arduino-cli compile \
            --fqbn esp32:esp32:esp32s3 \
            --build-path "${{ github.workspace }}/build" \
            --build-property "compiler.cpp.extra_flags=-I${{ github.workspace }}/include" \
            "${{ github.workspace }}/src/rs50h_thermal"

      - name: Rename firmware binary
        run: |
          TAG="${{ github.ref_name }}"
          cd "${{ github.workspace }}/build"
          for f in *.bin; do
            mv "$f" "rs50h_thermal_${TAG}.bin" 2>/dev/null && break
          done
          ls -lh *.bin

      - name: Extract dashboard (if exists)
        run: |
          if [ -f "scripts/extract_dashboard.py" ] && [ -f "src/rs50h_thermal/dashboard.h" ]; then
            python3 scripts/extract_dashboard.py \
              --header src/rs50h_thermal/dashboard.h \
              --out dashboard.html
            echo "DASHBOARD_EXISTS=true" >> $GITHUB_ENV
          else
            echo "DASHBOARD_EXISTS=false" >> $GITHUB_ENV
            echo "dashboard.h ou extract_dashboard.py não encontrados — pulando"
          fi

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: "RS50H Thermal Controller ${{ github.ref_name }}"
          body_path: CHANGELOG.md
          files: |
            build/rs50h_thermal_${{ github.ref_name }}.bin
            ${{ env.DASHBOARD_EXISTS == 'true' && 'dashboard.html' || '' }}
          fail_on_unmatched_files: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
'@
Write-Utf8Lf ".github\workflows\release.yml" $releaseYml
Write-Host "    ✅ release.yml escrito (arduino-cli ✅, paths corretos ✅)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[9/10] Verificando CHANGELOG.md" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
# Preserva conteúdo do usuário — só cria se não existir
if (Test-Path "CHANGELOG.md") {
    Write-Host "    ✅ CHANGELOG.md preservado (conteúdo do usuário mantido)" -ForegroundColor DarkGray
} else {
    $changelog = @'
# Changelog · RS50H Thermal Controller

Todas as mudanças notáveis neste projeto seguem o padrão
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/) e
[Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [1.0.0] — 2025-01-01

### Adicionado
- Firmware inicial para ESP32-S3 com controle térmico por PWM
- Leitura de temperatura e cálculo de duty-cycle proporcional
- Parâmetro `TEMP_SHUTDOWN` para desligamento de emergência
- Parâmetro `SAMPLE_INTERVAL_MS` para intervalo de amostragem
- CI/CD com arduino-cli (build + release automático)
- Workflows GitHub Actions: `build.yml` e `release.yml`
- `config.h.example` para configuração local sem expor credenciais
- Scripts PowerShell para auditoria, commit, push e monitoramento

### Notas técnicas
- **ESP32 Arduino core pinado em `2.0.14`** — API LEDC legada (`ledcSetup` /
  `ledcAttachPin` / `ledcWrite(channel, duty)`) removida no core v3.x.
  Migrar para v3 exige nova API: `ledcAttach(pin, freq, res)` / `ledcWrite(pin, duty)`.
'@
    Write-Utf8Lf "CHANGELOG.md" $changelog
    Write-Host "    ✅ CHANGELOG.md criado" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[10/10] Corrigindo pre-commit hook (LF + PowerShell)" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════

# 10a) Escreve o validador PowerShell (chamado pelo hook)
$validatePs1 = @'
#Requires -Version 5.1
# pre_commit_validate.ps1 — chamado pelo .git/hooks/pre-commit
# Não altere o exit code sem intenção: 0 = ok, 1 = bloquear commit

$root = git rev-parse --show-toplevel 2>$null
if (-not $root) { exit 0 }
Set-Location $root

$failed = $false

Write-Host "╔══════════════════════════════════════════╗"
Write-Host "║  RS50H · Pre-commit Validation           ║"
Write-Host "╚══════════════════════════════════════════╝"

# [1] Arquivos sensíveis
Write-Host "  [1/3] Verificando arquivos sensíveis..."
$staged = git diff --cached --name-only 2>$null
$hits = $staged | Where-Object { $_ -match '(^|/)config\.h$|\.env$|secret|password|token' }
if ($hits) {
    Write-Host "  ❌ Arquivo sensível no stage: $($hits -join ', ')" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "  ✅ Nenhum arquivo sensível." -ForegroundColor Green
}

# [2] FW_VERSION em config.h.example
Write-Host "  [2/3] Verificando FW_VERSION em config.h.example..."
$cfgPath = "include/config.h.example"
if (Test-Path $cfgPath) {
    $cfgContent = [System.IO.File]::ReadAllText($cfgPath)
    if ($cfgContent -match 'FW_VERSION') {
        Write-Host "  ✅ FW_VERSION encontrado em $cfgPath." -ForegroundColor Green
    } else {
        Write-Host "  ❌ FW_VERSION não encontrado em $cfgPath" -ForegroundColor Red
        $failed = $true
    }
} else {
    Write-Host "  ⚠️  $cfgPath ausente — pulando verificação." -ForegroundColor Yellow
}

# [3] config.h não deve estar no stage
Write-Host "  [3/3] Verificando se config.h está no stage..."
if ($staged -match '(^|/)config\.h$') {
    Write-Host "  ❌ include/config.h está no stage! Remova com: git reset HEAD include/config.h" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "  ✅ config.h não está no stage." -ForegroundColor Green
}

if ($failed) { exit 1 } else { exit 0 }
'@
Write-Utf8Lf "scripts\ps\pre_commit_validate.ps1" $validatePs1

# 10b) Escreve o bash hook com LF (sem CRLF — bash quebraria com \r)
$hookBash = "#!/bin/sh`n# RS50H pre-commit hook`n# Chama PowerShell para validação compatível com Windows`npowershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/ps/pre_commit_validate.ps1`nexit `$?`n"
$hookBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($hookBash)
[System.IO.File]::WriteAllBytes(".git\hooks\pre-commit", $hookBytes)

# ─────────────────────────────────────────────────────────────────────────────
# 10c) Escreve .githooks/pre-commit corrigido (rastreado no git, sem pio/COMMIT_EDITMSG)
# ─────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path ".githooks")) { New-Item -ItemType Directory -Path ".githooks" | Out-Null }
$githook = @'
#!/usr/bin/env bash
# RS50H pre-commit hook (bash)
# Instalar: git config core.hooksPath .githooks
# Não usa PlatformIO nem arduino-cli — validação rápida apenas.
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  RS50H · Pre-commit Validation           ║"
echo "╚══════════════════════════════════════════╝"

STAGED=$(git diff --cached --name-only 2>/dev/null || true)

# ── [1/3] Arquivos sensíveis ──────────────────────────────────────────────────
echo "🔍 [1/3] Verificando arquivos sensíveis..."
if echo "$STAGED" | grep -qE '(^|/)config\.h$|\.env$|\.key$|\.pem$'; then
  echo "❌ Arquivo sensível no stage! Abortando."
  echo "   Arquivos: $(echo "$STAGED" | grep -E '(^|/)config\.h$|\.env$|\.key$|\.pem$')"
  exit 1
fi
echo "✅ Nenhum arquivo sensível."

# ── [2/3] FW_VERSION no config.h.example ─────────────────────────────────────
echo "🔍 [2/3] Verificando FW_VERSION em config.h.example..."
FW=$(grep -E '#define[[:space:]]+FW_VERSION' include/config.h.example 2>/dev/null | sed 's/.*\"\([^\"]*\)\".*/\1/' || echo "")
if [ -z "$FW" ]; then
  echo "❌ FW_VERSION não encontrado em include/config.h.example"
  exit 1
fi
if ! echo "$FW" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "❌ FW_VERSION='$FW' não é SemVer (esperado: X.Y.Z)"
  exit 1
fi
echo "✅ FW_VERSION=$FW"

# ── [3/3] Lint Markdown (opcional) ───────────────────────────────────────────
echo "🔍 [3/3] Lint Markdown..."
if command -v npx &>/dev/null; then
  npx --yes markdownlint-cli2 "**/*.md" "#node_modules" "#.pio" \
    || { echo "❌ Markdown inválido."; exit 1; }
  echo "✅ Markdown OK."
else
  echo "⚠️  npx não encontrado — pulando lint Markdown"
fi

echo ""
echo "✅ Todos os checks passaram!"
echo ""
'@
# Escrever com LF puro
$githookBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($githook -replace "`r`n","`n"))
[System.IO.File]::WriteAllBytes(".githooks\pre-commit", $githookBytes)
Write-Host "    ✅ .githooks/pre-commit corrigido (sem pio, sem COMMIT_EDITMSG ✅)" -ForegroundColor Green

# Garante que core.hooksPath aponta para .githooks
git config core.hooksPath .githooks 2>$null | Out-Null
Write-Host "    ✅ git config core.hooksPath = .githooks" -ForegroundColor Green

# Verifica que não tem CR no arquivo escrito
$hookCheck = [System.IO.File]::ReadAllText(".git\hooks\pre-commit")
if ($hookCheck -match "`r") {
    Write-Host "    ❌ ERRO: hook ainda contém CR! Abortar." -ForegroundColor Red
    exit 1
} else {
    Write-Host "    ✅ pre-commit hook escrito com LF puro (bash-safe ✅)" -ForegroundColor Green
    Write-Host "    ✅ Hook chama PowerShell — compatível com Windows ✅" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[Verificação final]" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$checks = @{
    ".gitignore"                             = "Gitignore"
    "src\rs50h_thermal\rs50h_thermal.ino"   = "Firmware principal"
    ".github\workflows\build.yml"           = "Workflow Build"
    ".github\workflows\release.yml"         = "Workflow Release"
    "include\config.h.example"              = "Config exemplo"
    "ci\libraries.txt"                      = "Bibliotecas CI"
    "include\config.h"                      = "Config local (gitignored)"
    "scripts\ps\pre_commit_validate.ps1"    = "Validador do hook"
    "CHANGELOG.md"                          = "Changelog"
    ".githooks\pre-commit"                  = "Hook rastreado (.githooks)"
}
$checks.GetEnumerator() | ForEach-Object {
    if (Test-Path $_.Key) { Write-Host "    ✅ $($_.Value): $($_.Key)" -ForegroundColor Green }
    else { Write-Host "    ❌ FALTANDO: $($_.Key)" -ForegroundColor Red }
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  01_fix_scaffold.ps1 CONCLUÍDO                                  ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Próximo passo:"
Write-Host "  .\scripts\ps\02_commit_history.ps1"
Write-Host ""
