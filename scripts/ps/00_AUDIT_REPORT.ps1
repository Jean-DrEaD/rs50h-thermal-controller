#Requires -Version 5.1
<# ═══════════════════════════════════════════════════════════════════════════════
   RS50H · Relatório de Auditoria  (arduino-cli edition)
   Versão alvo: 1.0.0
═══════════════════════════════════════════════════════════════════════════════ #>
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent | Split-Path -Parent)

$ok = 0; $err = 0; $warn = 0
function Pass([string]$msg) { Write-Host "  ✅ $msg" -ForegroundColor Green;  $script:ok++ }
function Fail([string]$msg) { Write-Host "  ❌ $msg" -ForegroundColor Red;    $script:err++ }
function Warn([string]$msg) { Write-Host "  ⚠️  $msg" -ForegroundColor Yellow; $script:warn++ }

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RS50H · Relatório de Auditoria                                 ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Arquivos do projeto ──────────────────────────────────────────────────────
Write-Host "[ Arquivos do Projeto ]"
if (Test-Path "src\rs50h_thermal\rs50h_thermal.ino") { Pass ".ino presente" }
  else { Fail ".ino ausente (src\rs50h_thermal\rs50h_thermal.ino)" }

if (Test-Path "include\config.h.example") { Pass "config.h.example presente" }
  else { Fail "config.h.example ausente" }

if (Test-Path ".gitignore") { Pass ".gitignore presente" }
  else { Fail ".gitignore ausente" }

if (Test-Path "ci\libraries.txt") { Pass "ci/libraries.txt presente" }
  else { Fail "ci/libraries.txt ausente" }

if (Test-Path ".github\workflows\build.yml") { Pass "build.yml presente" }
  else { Fail "build.yml ausente" }

if (Test-Path ".github\workflows\release.yml") { Pass "release.yml presente" }
  else { Fail "release.yml ausente" }

if (Test-Path "CHANGELOG.md") { Pass "CHANGELOG.md presente" }
  else { Warn "CHANGELOG.md ausente" }

if (-not (git ls-files --error-unmatch "platformio.ini" 2>$null)) {
    Pass "platformio.ini ausente do git (arduino-cli)"
} else { Warn "platformio.ini ainda rastreado pelo git" }

git check-ignore -q "include/config.h" 2>$null
$configHIgnored = ($LASTEXITCODE -eq 0)
if (-not (Test-Path "include\config.h") -or $configHIgnored) {
    Pass "config.h NÃO está no git (gitignored)"
} else { Fail "config.h está rastreado pelo git — risco de vazar credenciais!" }

Write-Host ""

# ── Firmware .ino ─────────────────────────────────────────────────────────────
Write-Host "[ Firmware .ino ]"
$ino = "src\rs50h_thermal\rs50h_thermal.ino"
if (Test-Path $ino) {
    $content = Get-Content $ino -Raw
    if ($content -notmatch '(?m)^\s*z\s*$') { Pass "Sem stray 'z'" } else { Fail "Stray 'z' encontrado no .ino" }
    if ($content -match 'config\.h') { Pass "Include path correto (config.h)" } else { Fail "Include de config.h ausente" }
    if ($content -match 'SAMPLE_INTERVAL_MS') { Pass "SAMPLE_INTERVAL_MS referenciado" } else { Warn "SAMPLE_INTERVAL_MS não encontrado" }
    if ($content -match 'TEMP_CRITICAL') { Pass "TEMP_CRITICAL referenciado" } else { Fail "TEMP_CRITICAL não encontrado em .ino (macro renomeada de TEMP_SHUTDOWN)" }
}

Write-Host ""

# ── Versão ───────────────────────────────────────────────────────────────────
Write-Host "[ Versão ]"
if (Test-Path "include\config.h.example") {
    $cfgContent = Get-Content "include\config.h.example" -Raw
    if ($cfgContent -match 'FW_VERSION\s+"?([\d]+\.[\d]+\.[\d]+)"?') {
        $ver = $Matches[1]
        Pass "FW_VERSION = $ver"
        if ($ver -match '^\d+\.\d+\.\d+$') { Pass "FW_VERSION é SemVer válido" }
        else { Fail "FW_VERSION não é SemVer válido" }
    } else { Fail "FW_VERSION não encontrado em config.h.example" }
}

Write-Host ""

# ── Pre-commit hook ───────────────────────────────────────────────────────────
Write-Host "[ Pre-commit Hook ]"
$hookPath = ".githooks\pre-commit"
$hookPathGit = ".git\hooks\pre-commit"
$coreHooksPath = git config core.hooksPath 2>$null

if ($coreHooksPath -eq '.githooks') {
    if (Test-Path $hookPath) {
        $hookBytes = [System.IO.File]::ReadAllBytes($hookPath)
        $hookText  = [System.Text.UTF8Encoding]::new($false).GetString($hookBytes)
        if ($hookText -match "`r") { Fail ".githooks/pre-commit tem CRLF — bash vai falhar!" }
        else { Pass ".githooks/pre-commit com LF (Unix) ✅" }
        if ($hookText -match 'pio\s+run') { Fail ".githooks/pre-commit ainda chama 'pio run'" }
        else { Pass ".githooks/pre-commit sem referência a PlatformIO ✅" }
        if ($hookText -match 'COMMIT_EDITMSG') { Fail ".githooks/pre-commit lê COMMIT_EDITMSG no hook errado (mover para commit-msg hook)" }
        else { Pass ".githooks/pre-commit sem bug COMMIT_EDITMSG ✅" }
    } else { Fail ".githooks/pre-commit não existe (core.hooksPath=.githooks mas hook ausente)" }
} elseif (Test-Path $hookPathGit) {
    $hookBytes = [System.IO.File]::ReadAllBytes($hookPathGit)
    $hookText  = [System.Text.UTF8Encoding]::new($false).GetString($hookBytes)
    if ($hookText -match "`r") { Fail ".git/hooks/pre-commit tem CRLF — bash vai falhar! Execute 01_fix_scaffold.ps1" }
    else { Pass ".git/hooks/pre-commit com LF (Unix) ✅" }
    if ($hookText -match 'powershell') { Pass "Hook chama PowerShell (compatível Windows)" }
    else { Warn "Hook não chama PowerShell — verificar compatibilidade" }
    Warn "core.hooksPath não definido — hook não rastreado no git (ok para local)"
} else { Warn "Nenhum pre-commit hook encontrado" }

Write-Host ""

# ── Git config ────────────────────────────────────────────────────────────────
Write-Host "[ Git Config ]"
$gitEmail = git config user.email 2>$null
if ($gitEmail) { Pass "user.email configurado: $gitEmail" }
else { Fail "user.email não configurado — execute: git config --global user.email <seu@email>" }

$gitName = git config user.name 2>$null
if ($gitName) { Pass "user.name: $gitName" } else { Warn "user.name não configurado" }

Write-Host ""

# ── Workflows ────────────────────────────────────────────────────────────────
Write-Host "[ Workflows ]"
foreach ($wf in @('build.yml','release.yml')) {
    $wfPath = ".github\workflows\$wf"
    if (Test-Path $wfPath) {
        $wfContent = Get-Content $wfPath -Raw
        if ($wfContent -notmatch 'platformio|pio\s') { Pass "$wf não usa PlatformIO" }
          else { Fail "$wf ainda referencia PlatformIO" }
        if ($wfContent -match 'arduino-cli') { Pass "$wf usa arduino-cli" }
          else { Fail "$wf não usa arduino-cli" }
        if ($wfContent -match 'esp32:esp32:esp32s3') { Pass "$wf tem FQBN correto (esp32:esp32:esp32s3)" }
          else { Fail "$wf sem FQBN esp32:esp32:esp32s3" }
    }
}

if (Test-Path ".github\workflows\release.yml") {
    $rel = Get-Content ".github\workflows\release.yml" -Raw
    if ($rel -match 'extract_dashboard\.py') { Pass "release.yml: extract_dashboard.py referenciado" }
      else { Warn "release.yml: extract_dashboard.py não encontrado" }
    if ($rel -match '\-\-header') { Pass "release.yml: extract_dashboard usa --header (correto)" }
      else { Fail "release.yml: extract_dashboard NÃO usa --header — vai falhar com exit 2!" }
}

Write-Host ""

# ── Git status ────────────────────────────────────────────────────────────────
Write-Host "[ Git ]"
$commitCount = (git rev-list --count HEAD 2>$null)
if ($commitCount -gt 0) { Pass "Tem commits ($commitCount)" } else { Fail "Nenhum commit!" }

$status = git status --porcelain 2>$null
if (-not $status) { Warn "Working tree limpa (nada para commitar)" }
  else { Pass "Working tree tem $($status.Count) arquivo(s) modificado(s)" }

$tags = git tag -l "v1.0*" 2>$null
if ($tags) { Pass "Tag $($tags -join ', ') existe localmente" }
  else { Warn "Tag v1.0.0 não existe localmente ainda" }

$remote = git remote get-url origin 2>$null
if ($remote -match 'rs50h-thermal-controller') { Pass "Remote origin apontando para rs50h-thermal-controller" }
  else { Fail "Remote origin incorreto: $remote" }

try {
    git ls-remote --heads origin main 2>$null | Out-Null
    $ahead = (git rev-list "origin/main..HEAD" --count 2>$null)
    if ($ahead -gt 0) { Warn "$ahead commit(s) locais ainda não enviados para o remote" }
    else { Pass "Branch main no remote sincronizado" }
} catch { Warn "Não foi possível verificar remote (sem internet?)" }

# ── Resultado ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host "  Resultado: $ok OK  |  $err ERRO(S)  |  $warn AVISO(S)"
Write-Host ""

if ($err -eq 0) {
    Write-Host "  ✅ Repositório pronto. Ordem de execução:" -ForegroundColor Green
} else {
    Write-Host "  ❌ Há $err erro(s) a corrigir. Execute:" -ForegroundColor Red
}
Write-Host ""
Write-Host "  1. .\scripts\ps\01_fix_scaffold.ps1    ← corrige tudo (hook, arquivos)"
Write-Host "  2. .\scripts\ps\02_commit_history.ps1  ← cria commits"
Write-Host "  3. .\scripts\ps\03_push.ps1            ← push main"
Write-Host "  4. (aguardar build verde em Actions)   ← build.yml"
Write-Host "  5. .\scripts\ps\04_tag_release.ps1     ← tag + release"
Write-Host "  6. .\scripts\ps\05_ci_watch.ps1        ← monitorar"
Write-Host ""
