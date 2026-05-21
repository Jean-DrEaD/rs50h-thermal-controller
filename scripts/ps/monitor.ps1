#Requires -Version 5.1
<#
.SYNOPSIS
    Monitor serial RS50H via arduino-cli.

.DESCRIPTION
    Conecta ao ESP32-S3 via arduino-cli monitor e exibe o output com
    destaque de estados FSM. Detecta automaticamente a porta COM/ttyACM.

.PARAMETER Port
    Porta serial (ex: COM3, /dev/ttyACM0). Se omitida, detecta automaticamente.

.PARAMETER Baud
    Baud rate (padrão: 115200 — deve coincidir com SERIAL_BAUD em config.h).

.PARAMETER Filter
    String de filtro — exibe apenas linhas que contenham este texto.
    Ex: -Filter "FSM" mostra apenas transições de estado.

.EXAMPLE
    # Detecta porta automaticamente
    pwsh scripts/ps/monitor.ps1

    # Porta específica
    pwsh scripts/ps/monitor.ps1 -Port COM4

    # Somente transições FSM
    pwsh scripts/ps/monitor.ps1 -Filter "[FSM]"

.NOTES
    Pré-requisito: arduino-cli no PATH.
    Execute sempre na raiz do repositório.
#>
[CmdletBinding()]
param(
    [string] $Port  = "",
    [int]    $Baud  = 115200,
    [string] $Filter = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Banner ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "║  RS50H · Monitor Serial                  ║" -ForegroundColor DarkCyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""

# ── Verificar arduino-cli ─────────────────────────────────────────────────────
if (-not (Get-Command arduino-cli -ErrorAction SilentlyContinue)) {
    Write-Host "❌ arduino-cli não encontrado no PATH." -ForegroundColor Red
    Write-Host "   Instale em: https://arduino.github.io/arduino-cli/latest/installation/"
    exit 1
}

# ── Detectar porta ────────────────────────────────────────────────────────────
if (-not $Port) {
    Write-Host "🔍 Detectando porta..." -ForegroundColor Yellow
    $boardList = arduino-cli board list 2>&1
    $match = $boardList | Select-String -Pattern "(COM\d+|/dev/tty\w+)" | Select-Object -First 1
    if ($match) {
        $Port = $match.Matches[0].Value
        Write-Host "   Encontrada: $Port" -ForegroundColor Green
    } else {
        Write-Host "❌ Nenhuma porta detectada. Especifique com -Port." -ForegroundColor Red
        Write-Host ""
        Write-Host "Portas disponíveis:" -ForegroundColor Yellow
        arduino-cli board list
        exit 1
    }
}

# ── Cabeçalho de sessão ───────────────────────────────────────────────────────
Write-Host "📡 Conectando a $Port @ $Baud baud..." -ForegroundColor Cyan
if ($Filter) {
    Write-Host "🔎 Filtro ativo: '$Filter'" -ForegroundColor Yellow
}
Write-Host "   Ctrl+C para encerrar." -ForegroundColor DarkGray
Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Mapeamento de cores por prefixo ──────────────────────────────────────────
# [RS50H] → Cyan    [FSM] → Magenta    [RELAY] → Red/Green
# [WiFi]  → Yellow  [OTA] → Blue       [NTC]   → DarkYellow
# [WS]    → DarkCyan
function Get-LineColor {
    param([string]$line)
    if ($line -match '\[FSM\]')    { return 'Magenta' }
    if ($line -match '\[RELAY\].*ABERTO')  { return 'Red' }
    if ($line -match '\[RELAY\].*FECHADO') { return 'Green' }
    if ($line -match '\[RELAY\]')  { return 'DarkGray' }
    if ($line -match '\[WiFi\]')   { return 'Yellow' }
    if ($line -match '\[OTA\]')    { return 'Blue' }
    if ($line -match '\[NTC\].*⚠') { return 'DarkYellow' }
    if ($line -match '\[WS\]')     { return 'DarkCyan' }
    if ($line -match '\[RS50H\]')  { return 'Cyan' }
    return 'Gray'
}

# ── Monitor ───────────────────────────────────────────────────────────────────
try {
    $proc = Start-Process arduino-cli `
        -ArgumentList "monitor -p $Port -c baudrate=$Baud" `
        -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\rs50h_serial.tmp"

    # Ler output em loop (arduino-cli monitor é interativo; lemos o pipe)
    # Fallback: ler o arquivo temporário em loop (cross-platform)
    $reader = [System.IO.StreamReader]::new("$env:TEMP\rs50h_serial.tmp")

    while (-not $proc.HasExited) {
        $line = $reader.ReadLine()
        if ($null -ne $line) {
            if ($Filter -and $line -notmatch [regex]::Escape($Filter)) { continue }
            $ts  = "[{0:HH:mm:ss}] " -f (Get-Date)
            $col = Get-LineColor $line
            Write-Host "$ts$line" -ForegroundColor $col
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
    $reader.Dispose()
}
catch [System.OperationCanceledException] {
    Write-Host ""
    Write-Host "⏹  Monitor encerrado." -ForegroundColor DarkGray
}
catch {
    # arduino-cli monitor é interativo — redirecionar stdout é limitado no Windows.
    # Fallback: invocar diretamente sem captura (output vai direto ao terminal).
    Write-Host "⚠️  Modo direto (sem filtro de cores)." -ForegroundColor Yellow
    Write-Host ""
    & arduino-cli monitor -p $Port -c baudrate=$Baud
}
finally {
    if (Test-Path "$env:TEMP\rs50h_serial.tmp") {
        Remove-Item "$env:TEMP\rs50h_serial.tmp" -ErrorAction SilentlyContinue
    }
    Write-Host ""
    Write-Host "Sessão encerrada." -ForegroundColor DarkGray
}
