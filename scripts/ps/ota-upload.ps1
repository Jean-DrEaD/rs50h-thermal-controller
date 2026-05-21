#Requires -Version 5.1
<#
.SYNOPSIS
    Compila e faz OTA upload do RS50H via arduino-cli + espota.py.
    Roda direto da raiz do projeto. Não depende do Arduino IDE GUI.

.PARAMETER Ip
    IP do dispositivo. Padrão: 192.168.1.23

.PARAMETER Port
    Porta OTA. Padrão: 3232

.PARAMETER Password
    Senha OTA (OTA_PASSWORD em config.h). Obrigatório.

.PARAMETER SkipCompile
    Pula a compilação e usa o .bin já existente em build\.

.PARAMETER EspotaPath
    Caminho manual para espota.py (opcional).

.EXAMPLE
    .\ota-upload.ps1 -Password "minha-senha-ota"

.EXAMPLE
    .\ota-upload.ps1 -Password "minha-senha-ota" -SkipCompile
#>

[CmdletBinding()]
param(
    [string]$Ip           = "192.168.1.23",
    [int]   $Port         = 3232,
    [Parameter(Mandatory)]
    [string]$Password,
    [switch]$SkipCompile,
    [string]$EspotaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param($m) Write-Host "  » $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  ✔ $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "`n  ✘ $m`n" -ForegroundColor Red; exit 1 }

# ─── Paths ────────────────────────────────────────────────────────────────────
$ProjectRoot = $PSScriptRoot
$SketchPath  = Join-Path $ProjectRoot "src\rs50h_thermal"
$BuildPath   = Join-Path $ProjectRoot "build"
$IncludePath = $ProjectRoot.Replace('\', '/')
$BinFile     = Join-Path $BuildPath "rs50h_thermal.ino.bin"

$Fqbn = "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled"

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
Write-Host "  RS50H  —  compile + OTA upload               " -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
Write-Host ""

# ─── Verificar config.h ───────────────────────────────────────────────────────
$ConfigH = Join-Path $ProjectRoot "include\config.h"
if (-not (Test-Path $ConfigH)) {
    Write-Warn "include\config.h não encontrado — criando a partir do exemplo..."
    $Example = Join-Path $ProjectRoot "include\config.h.example"
    if (-not (Test-Path $Example)) { Write-Fail "include\config.h.example também não encontrado." }
    Copy-Item $Example $ConfigH
    Write-Ok "include\config.h criado. Edite as credenciais antes de continuar."
    Write-Host ""
    Write-Host "  Abra:  notepad $ConfigH" -ForegroundColor Yellow
    Write-Host "  Preencha: WIFI_SSID, WIFI_PASS, OTA_PASSWORD, HTTP_AUTH_*" -ForegroundColor Yellow
    Write-Host ""
    Write-Fail "Edite o config.h e rode o script novamente."
}
Write-Ok "include\config.h presente."

# ─── Compilar ─────────────────────────────────────────────────────────────────
if (-not $SkipCompile) {
    Write-Step "Verificando arduino-cli..."
    try { $v = arduino-cli version 2>&1; Write-Ok "arduino-cli: $v" }
    catch { Write-Fail "arduino-cli não encontrado no PATH. Instale em https://arduino.github.io/arduino-cli/" }

    if (-not (Test-Path $BuildPath)) { New-Item -ItemType Directory -Path $BuildPath | Out-Null }

    Write-Step "Compilando sketch..."
    Write-Host ""

    $compileArgs = @(
        "compile",
        "--fqbn",           $Fqbn,
        "--build-path",     $BuildPath,
        "--build-property", "compiler.cpp.extra_flags=-I$IncludePath/include",
        $SketchPath
    )

    arduino-cli @compileArgs
    if ($LASTEXITCODE -ne 0) { Write-Fail "Compilação falhou (exit $LASTEXITCODE)." }

    Write-Host ""
    Write-Ok "Compilação concluída."
} else {
    Write-Warn "Compilação pulada (-SkipCompile)."
}

# ─── Verificar .bin ───────────────────────────────────────────────────────────
Write-Step "Verificando firmware .bin..."
if (-not (Test-Path $BinFile)) {
    Write-Fail ".bin não encontrado em $BinFile — rode sem -SkipCompile."
}
$binSize = [math]::Round((Get-Item $BinFile).Length / 1KB, 1)
$binAge  = [math]::Round(((Get-Date) - (Get-Item $BinFile).LastWriteTime).TotalSeconds)
Write-Ok "$([System.IO.Path]::GetFileName($BinFile))  (${binSize} KB, gerado há ${binAge}s)"

# ─── Localizar espota.py ──────────────────────────────────────────────────────
Write-Step "Localizando espota.py..."
if (-not ($EspotaPath -and (Test-Path $EspotaPath))) {
    $searchRoots = @(
        (Join-Path $env:LOCALAPPDATA "Arduino15\packages\esp32\hardware\esp32"),
        (Join-Path $env:APPDATA      "Arduino15\packages\esp32\hardware\esp32")
    )
    $found = $searchRoots | Where-Object { Test-Path $_ } | ForEach-Object {
        Get-ChildItem -Path $_ -Recurse -Filter "espota.py" -ErrorAction SilentlyContinue
    } | Sort-Object FullName -Descending | Select-Object -First 1

    if (-not $found) {
        Write-Warn "espota.py não encontrado no cache do Arduino IDE."
        Write-Host "  Baixe em: https://raw.githubusercontent.com/esp8266/Arduino/master/tools/espota.py" -ForegroundColor Yellow
        Write-Host "  Depois: .\ota-upload.ps1 -Password '...' -EspotaPath 'C:\path\espota.py'" -ForegroundColor Yellow
        Write-Fail "espota.py não localizado."
    }
    $EspotaPath = $found.FullName
}
Write-Ok "espota.py: $EspotaPath"

# ─── Python ───────────────────────────────────────────────────────────────────
Write-Step "Verificando Python..."
$python = @("python", "python3", "py") | Where-Object {
    try { (& $_ --version 2>&1) -match "Python \d" } catch { $false }
} | Select-Object -First 1
if (-not $python) { Write-Fail "Python não encontrado. Instale em https://python.org" }
Write-Ok "Python OK ($python)"

# ─── Conectividade ────────────────────────────────────────────────────────────
Write-Step "Testando ${Ip}:${Port}..."
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $ok  = $tcp.BeginConnect($Ip, $Port, $null, $null).AsyncWaitHandle.WaitOne(2000)
    $tcp.Close()
    if ($ok) { Write-Ok "Porta $Port alcançável." }
    else {
        Write-Warn "Porta $Port não respondeu. Device ligado e com WiFi ok?"
        $r = Read-Host "  Continuar mesmo assim? (s/N)"
        if ($r -notmatch '^[sS]') { exit 0 }
    }
} catch { Write-Warn "Não foi possível testar TCP: $_" }

# ─── Upload ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
Write-Step "Enviando OTA para ${Ip}:${Port}..."
Write-Host ""

& $python $EspotaPath --ip $Ip --port $Port --auth $Password --file $BinFile
$exit = $LASTEXITCODE

Write-Host ""
if ($exit -eq 0) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Ok  "Upload concluído! Device reiniciando..."
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
} else {
    Write-Fail "espota.py saiu com código $exit. Verifique senha, IP e se o device está pronto."
}
