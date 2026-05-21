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