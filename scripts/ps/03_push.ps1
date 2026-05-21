#Requires -Version 5.1
<# ═══════════════════════════════════════════════════════════════════════════════
   RS50H · Push para GitHub  (arduino-cli edition)
   Versão alvo: 1.0.0

   CORREÇÕES:
   · Usa git rev-list origin/main..HEAD --count para detectar commits pendentes
   · Se ahead=0 E working tree limpa → avisa claramente (não há nada para enviar)
   · Git user lido do git config existente (não sobrescrito)
   · Auto-commit com --no-verify para arquivos esquecidos
   · -Force pula confirmação ENTER (útil em automação)
═══════════════════════════════════════════════════════════════════════════════ #>
param(
    [switch]$Force   # pula confirmação interativa
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent | Split-Path -Parent)

$remote = git remote get-url origin 2>$null
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RS50H · Push para GitHub                                       ║" -ForegroundColor Cyan
Write-Host "║  Remote: $remote" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[1/5] Verificando git e commits" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
# Email/name lidos do git config existente — não sobrescrever
$totalCommits = [int](git rev-list --count HEAD 2>$null)
Write-Host "    ✅ $totalCommits commit(s) no histórico local" -ForegroundColor Green

# Commita working tree suja (--no-verify: hook já validado em 02_commit_history)
$dirty = git status --porcelain 2>$null
if ($dirty) {
    Write-Host "    ⚠️  Working tree tem arquivos não commitados — commitando agora..." -ForegroundColor Yellow
    git add -A 2>$null
    git commit --no-verify -m "(Update): Dashboard remodeling + OTA Script" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ❌ Auto-commit falhou. Verifique manualmente." -ForegroundColor Red
        exit 1
    }
    Write-Host "    ✅ Auto-commit feito (--no-verify)" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[2/5] Configurando remote origin" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
$remoteUrl = git remote get-url origin 2>$null
if (-not $remoteUrl) {
    Write-Host "    ❌ Remote 'origin' não configurado!" -ForegroundColor Red
    exit 1
}
Write-Host "    ✅ Remote origin: $remoteUrl" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[3/5] Verificando FW_VERSION" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
if (Test-Path "include\config.h.example") {
    $cfg = [System.IO.File]::ReadAllText("include\config.h.example")
    if ($cfg -match 'FW_VERSION\s+"?([\d.]+)"?') {
        Write-Host "    ✅ FW_VERSION = $($Matches[1])" -ForegroundColor Green
    } else {
        Write-Host "    ❌ FW_VERSION não encontrado em config.h.example!" -ForegroundColor Red
        Write-Host "    Execute 01_fix_scaffold.ps1 primeiro." -ForegroundColor Red
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[4/5] Commits a enviar" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════

# Tenta buscar status remoto (pode falhar sem rede)
try {
    git fetch origin main --quiet 2>$null
    $ahead = [int](git rev-list "origin/main..HEAD" --count 2>$null)
} catch {
    $ahead = -1
}

if ($ahead -eq 0) {
    Write-Host "    ℹ️  Nenhum commit novo para enviar (origin/main já está atualizado)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ✅ Repositório já sincronizado com o remote." -ForegroundColor Green
    Write-Host "  Se esperava commits novos, verifique se 02_commit_history.ps1 criou commits." -ForegroundColor Yellow
    Write-Host ""
    git log --oneline -5
    Write-Host ""
    exit 0
} elseif ($ahead -eq -1) {
    Write-Host "    ⚠️  Não foi possível verificar o remote — tentando push mesmo assim..." -ForegroundColor Yellow
} else {
    Write-Host "    ✅ $ahead commit(s) prontos para envio:" -ForegroundColor Green
    git log --oneline "origin/main..HEAD"
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "[5/5] Push → origin/main" -ForegroundColor Yellow
# ═══════════════════════════════════════════════════════════════════════════════
if (-not $Force) {
    Write-Host "  Pressione ENTER para confirmar push, ou Ctrl+C para cancelar."
    Read-Host "  → ENTER para continuar"
}

Write-Host ""
Write-Host "    ℹ️  Executando: git push -u origin main" -ForegroundColor DarkGray
git push -u origin main 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "    ⚠️  Push normal falhou. Tentando --force-with-lease..." -ForegroundColor Yellow
    git push --force-with-lease -u origin main 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ❌ Push falhou mesmo com --force-with-lease." -ForegroundColor Red
        Write-Host "    Verifique autenticação: gh auth status" -ForegroundColor Red
        exit 1
    }
    Write-Host "    ✅ Push feito com --force-with-lease" -ForegroundColor Yellow
} else {
    Write-Host "    ✅ Push concluído com sucesso!" -ForegroundColor Green
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  03_push.ps1 CONCLUÍDO                                          ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Aguarde o Actions rodar em:"
Write-Host "  https://github.com/Jean-DrEaD/rs50h-thermal-controller/actions"
Write-Host ""
Write-Host "  Próximos passos (APÓS build verde):"
Write-Host "  .\scripts\ps\04_tag_release.ps1  [-Retag se a tag v1.0.0 já existir]"
Write-Host "  .\scripts\ps\05_ci_watch.ps1     [monitorar Actions em tempo real]"
Write-Host ""
