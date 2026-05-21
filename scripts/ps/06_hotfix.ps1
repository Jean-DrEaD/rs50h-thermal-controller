#Requires -Version 5.1
<# ═══════════════════════════════════════════════════════════════════════════════
   RS50H · Hotfix Helper v1.0.1
   Uso: .\scripts\ps\06_hotfix.ps1 -Version 1.0.1 -Message "fix: descrição"
═══════════════════════════════════════════════════════════════════════════════ #>
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')]   # [M6] SemVer estrito
    [string]$Version,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(5, 200)]
    [string]$Message
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent | Split-Path -Parent)

# [M6] Validação extra (defesa em profundidade — ValidatePattern já cobre,
# mas mantemos mensagem amigável)
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    Write-Host "❌ -Version deve ser SemVer X.Y.Z (ou X.Y.Z-prerelease). Ex: 1.0.1" -ForegroundColor Red
    exit 1
}

# [M6] Bloqueia mensagens vazias ou triviais
if ($Message.Trim().Length -lt 5) {
    Write-Host "❌ -Message muito curto (mín. 5 chars úteis)" -ForegroundColor Red
    exit 1
}
if ($Message -notmatch '^(fix|feat|chore|docs|refactor|test|perf|build|ci)(\(.+\))?:\s') {
    Write-Host "⚠️  -Message não segue Conventional Commits (fix:, feat:, chore:, RS50H, ...)" -ForegroundColor Yellow
    Write-Host "    Continuando, mas recomenda-se padronizar." -ForegroundColor Yellow
}

$TAG = "v$Version"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RS50H · Hotfix Helper                                          ║" -ForegroundColor Cyan
Write-Host "║  Nova versão: $TAG" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# [M6] Verifica se a tag já existe no remoto
$remoteTag = git ls-remote --tags origin "refs/tags/$TAG" 2>$null
if ($remoteTag) {
    Write-Host "⚠️  Tag $TAG já existe no remoto. Será sobrescrita (force)." -ForegroundColor Yellow
    $confirm = Read-Host "    Continuar? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "❌ Abortado pelo usuário." -ForegroundColor Red
        exit 1
    }
}

# Git identity defensiva
$existingName = git config user.name 2>$null
if (-not $existingName) { git config user.name "Jean-DrEaD" }

# ── 1. Atualiza FW_VERSION ───────────────────────────────────────────────────
Write-Host "[1/4] Atualizando FW_VERSION para $Version..." -ForegroundColor Yellow
$cfgPath = "include\config.h.example"
if (-not (Test-Path $cfgPath)) {
    Write-Host "    ❌ $cfgPath não encontrado!" -ForegroundColor Red; exit 1
}
$cfg = [System.IO.File]::ReadAllText($cfgPath)
$cfgNew = $cfg -replace '#define FW_VERSION\s+"[\d.\-A-Za-z]+"', "#define FW_VERSION `"$Version`""
if ($cfg -eq $cfgNew) {
    Write-Host "    ⚠️  FW_VERSION não foi alterado (já era $Version?)" -ForegroundColor Yellow
}
$lf = $cfgNew -replace "`r`n", "`n"
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($lf)
[System.IO.File]::WriteAllBytes($cfgPath, $bytes)

if (Test-Path "include\config.h") {
    $cfgLocal = [System.IO.File]::ReadAllText("include\config.h")
    $cfgLocal = $cfgLocal -replace '#define FW_VERSION\s+"[\d.\-A-Za-z]+"', "#define FW_VERSION `"$Version`""
    $lfLocal = $cfgLocal -replace "`r`n", "`n"
    $bytesLocal = [System.Text.UTF8Encoding]::new($false).GetBytes($lfLocal)
    [System.IO.File]::WriteAllBytes("include\config.h", $bytesLocal)
}
Write-Host "    ✅ FW_VERSION = $Version" -ForegroundColor Green

# ── 2. Commit ────────────────────────────────────────────────────────────────
Write-Host "[2/4] Commit..." -ForegroundColor Yellow
git add -A 2>$null
git commit --no-verify -m $Message 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "    ❌ Commit falhou." -ForegroundColor Red; exit 1 }
Write-Host "    ✅ Commit: $Message" -ForegroundColor Green

# ── 3. Push ──────────────────────────────────────────────────────────────────
Write-Host "[3/4] Push → origin/main..." -ForegroundColor Yellow
git push -u origin main 2>&1
if ($LASTEXITCODE -ne 0) {
    git push --force-with-lease -u origin main 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "    ❌ Push falhou." -ForegroundColor Red; exit 1 }
}
Write-Host "    ✅ Push concluído." -ForegroundColor Green

# ── 4. Tag ───────────────────────────────────────────────────────────────────
Write-Host "[4/4] Tag $TAG..." -ForegroundColor Yellow
$existing = git tag -l $TAG 2>$null
if ($existing) { git tag -d $TAG 2>$null | Out-Null }
try { git push origin ":refs/tags/$TAG" 2>$null | Out-Null } catch {}

git tag -a $TAG -m "RS50H Thermal Controller $TAG"
git push origin $TAG 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "    ❌ Push da tag falhou." -ForegroundColor Red; exit 1 }
Write-Host "    ✅ Tag $TAG enviada." -ForegroundColor Green

Write-Host ""
Write-Host "  ✅ Hotfix $TAG publicado!" -ForegroundColor Green
Write-Host "  https://github.com/Jean-DrEaD/rs50h-thermal-controller/releases" -ForegroundColor Cyan
Write-Host ""
