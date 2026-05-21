#Requires -Version 5.1
<# ═══════════════════════════════════════════════════════════════════════════════
   RS50H · Monitor de CI  (arduino-cli edition)
   Monitora Actions em tempo real via GitHub CLI (gh)
═══════════════════════════════════════════════════════════════════════════════ #>
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Split-Path $PSScriptRoot -Parent | Split-Path -Parent)

$REPO = "Jean-DrEaD/rs50h-thermal-controller"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RS50H · Monitor de CI                                          ║" -ForegroundColor Cyan
Write-Host "║  Repo: $REPO                         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verifica se gh (GitHub CLI) está disponível
$ghPath = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghPath) {
    Write-Host "  ⚠️  GitHub CLI (gh) não encontrado." -ForegroundColor Yellow
    Write-Host "  Instale em: https://cli.github.com/" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Acompanhe manualmente:"
    Write-Host "  https://github.com/$REPO/actions" -ForegroundColor Cyan
    exit 0
}

# Verifica autenticação
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ⚠️  gh não autenticado. Execute: gh auth login" -ForegroundColor Yellow
    Write-Host "  https://github.com/$REPO/actions" -ForegroundColor Cyan
    exit 0
}

Write-Host "  Monitorando runs em tempo real (Ctrl+C para parar)..." -ForegroundColor DarkGray
Write-Host ""

$pollInterval = 15   # segundos
$maxMinutes   = 20
$elapsed      = 0

while ($elapsed -lt ($maxMinutes * 60)) {
    $runs = gh run list --repo $REPO --limit 5 --json status,conclusion,name,headBranch,createdAt 2>$null |
            ConvertFrom-Json -ErrorAction SilentlyContinue

    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] ─────────────────────────────────────────────" -ForegroundColor DarkGray

    if ($runs) {
        foreach ($run in $runs) {
            $icon = switch ($run.status) {
                "completed" {
                    switch ($run.conclusion) {
                        "success"  { "✅" }
                        "failure"  { "❌" }
                        "cancelled"{ "🚫" }
                        default    { "❓" }
                    }
                }
                "in_progress" { "🔄" }
                "queued"      { "⏳" }
                default       { "❓" }
            }
            $branch = $run.headBranch
            $name   = $run.name
            Write-Host "  $icon  [$($run.status.PadRight(12))]  $name  ($branch)"
        }
    } else {
        Write-Host "  ℹ️  Nenhum run encontrado ainda — aguardando trigger..." -ForegroundColor Yellow
    }

    $allDone = $runs | Where-Object { $_.status -ne "completed" }
    if (-not $allDone -and $runs -and $runs.Count -gt 0) {
        Write-Host ""
        Write-Host "  ✅ Todos os runs concluídos." -ForegroundColor Green
        Write-Host "  https://github.com/$REPO/actions" -ForegroundColor Cyan
        break
    }

    Start-Sleep -Seconds $pollInterval
    $elapsed += $pollInterval
}

if ($elapsed -ge ($maxMinutes * 60)) {
    Write-Host "  ⚠️  Timeout após $maxMinutes minutos." -ForegroundColor Yellow
    Write-Host "  Verifique: https://github.com/$REPO/actions" -ForegroundColor Cyan
}
Write-Host ""
