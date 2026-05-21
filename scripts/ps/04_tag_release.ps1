#Requires -Version 5.1
<# ═══════════════════════════════════════════════════════════════════════════════
   RS50H · Tag + Release  (arduino-cli edition)
   Versão alvo: 1.0.0

   CORREÇÕES:
   · Verifica commits no remote ANTES de criar tag
   · -Retag deleta e recria tag local + remote sem travar
   · Push da tag verificado separadamente do push do branch
   · Git user lido do git config existente (não sobrescrito)
═══════════════════════════════════════════════════════════════════════════════ #>
param(
    [switch]$Retag   # força recriação da tag mesmo se já existir
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent | Split-Path -Parent)

$TAG     = "v1.0.0"
$remote  = git remote get-url origin 2>$null

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RS50H · Tag + Release                                          ║" -ForegroundColor Cyan
Write-Host "║  Tag alvo: $TAG                                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Email/name lidos do git config existente — não sobrescrever

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[1/5] Verificando sincronização com remote" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
git fetch origin main --quiet 2>$null
$ahead = [int](git rev-list "origin/main..HEAD" --count 2>$null)

if ($ahead -gt 0) {
    Write-Host "    ⚠️  $ahead commit(s) local(is) não enviados. Fazendo push agora..." -ForegroundColor Yellow
    git push -u origin main 2>&1
    if ($LASTEXITCODE -ne 0) {
        git push --force-with-lease -u origin main 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ❌ Push falhou — não é possível criar tag sem sincronizar." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "    ✅ Push feito." -ForegroundColor Green
} else {
    Write-Host "    ✅ Remote já sincronizado (0 commits pendentes)." -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[2/5] Verificando se tag $TAG já existe" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$tagLocalExists  = (git tag -l $TAG 2>$null) -ne ""
$tagRemoteExists = $false
try {
    $remoteTagRaw = git ls-remote --tags origin "refs/tags/$TAG" 2>$null
    $tagRemoteExists = $remoteTagRaw -ne ""
} catch {}

if ($tagLocalExists -or $tagRemoteExists) {
    if (-not $Retag) {
        Write-Host "    ⚠️  Tag $TAG já existe ($( ($tagLocalExists ? 'local' : '') + ($tagRemoteExists ? ' remote' : '') ).Trim())." -ForegroundColor Yellow
        Write-Host "    Para recriar: execute com -Retag" -ForegroundColor Yellow
        Write-Host "    .\scripts\ps\04_tag_release.ps1 -Retag" -ForegroundColor Cyan
        exit 0
    }
    Write-Host "    🔧 -Retag: removendo tag existente..." -ForegroundColor Yellow
    if ($tagLocalExists)  { git tag -d $TAG 2>$null | Out-Null }
    if ($tagRemoteExists) { git push origin ":refs/tags/$TAG" 2>$null | Out-Null }
    Write-Host "    ✅ Tag antiga removida." -ForegroundColor Green
} else {
    Write-Host "    ✅ Tag $TAG ainda não existe — criação limpa." -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[3/5] Lendo FW_VERSION de config.h.example" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
if (Test-Path "include\config.h.example") {
    $cfg = [System.IO.File]::ReadAllText("include\config.h.example")
    if ($cfg -match 'FW_VERSION\s+"?([\d.]+)"?') {
        $fwVer = $Matches[1]
        Write-Host "    ✅ FW_VERSION = $fwVer" -ForegroundColor Green
        if ("v$fwVer" -ne $TAG) {
            Write-Host "    ⚠️  FW_VERSION ($fwVer) difere do TAG ($TAG) — verifique config.h.example" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    ⚠️  FW_VERSION não encontrado — continuando mesmo assim" -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[4/5] Criando tag anotada $TAG" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
git tag -a $TAG -m "RS50H Thermal Controller $TAG — ESP32-S3" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "    ❌ Falha ao criar tag $TAG" -ForegroundColor Red
    exit 1
}
Write-Host "    ✅ Tag $TAG criada localmente." -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[5/5] Push da tag → origin" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
git push origin $TAG 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "    ❌ Push da tag falhou." -ForegroundColor Red
    exit 1
}
Write-Host "    ✅ Tag $TAG enviada para o remote." -ForegroundColor Green

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  04_tag_release.ps1 CONCLUÍDO                                   ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  ✅ GitHub Actions deve iniciar o release.yml agora."
Write-Host "  Acompanhe em:"
Write-Host "  https://github.com/Jean-DrEaD/rs50h-thermal-controller/actions"
Write-Host ""
Write-Host "  .\scripts\ps\05_ci_watch.ps1   ← monitorar em tempo real"
Write-Host ""
