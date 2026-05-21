# scripts/commit.ps1 — RS50H Thermal Controller
# Helper interativo de commit convencional com output colorido.
# Uso: pwsh scripts/commit.ps1
# Uso com mensagem direta: pwsh scripts/commit.ps1 -m "feat(sensor): ajuste NTC"
#
# Cores do tema RS50H (fundo escuro + acento âmbar):
#   Âmbar  → DarkYellow  (títulos, prompts)
#   Verde  → Green       (sucesso, OK)
#   Vermelho → Red       (erros)
#   Cinza  → DarkGray    (info, secundário)

param(
  [Alias('m')][string]$Message = '',
  [switch]$Push,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Helpers de cor ────────────────────────────────────────────────────────────
function Write-Header { Write-Host "`n  RS50H · Commit" -ForegroundColor DarkYellow -NoNewline
  Write-Host " ──────────────────────────────" -ForegroundColor DarkGray }

function Write-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "  · $msg" -ForegroundColor DarkGray }
function Write-Amber($msg){ Write-Host "  $msg"   -ForegroundColor DarkYellow }

function Write-Sep { Write-Host "  ──────────────────────────────────────" -ForegroundColor DarkGray }

# ─── Verificações iniciais ─────────────────────────────────────────────────────
Write-Header
Write-Sep

# Confirma que está num repositório git
if (-not (Test-Path ".git")) {
  Write-Err "Não é um repositório git. Execute na raiz do projeto."
  exit 1
}

# Status
$status = git status --porcelain 2>&1
if (-not $status) {
  Write-Warn "Nada para commitar (working tree limpa)."
  exit 0
}

Write-Amber "Arquivos modificados:"
$status | ForEach-Object {
  $flag = $_.Substring(0, 2).Trim()
  $file = $_.Substring(3)
  $color = switch ($flag) {
    'M'  { 'Cyan' }
    'A'  { 'Green' }
    'D'  { 'Red' }
    '??' { 'DarkGray' }
    default { 'White' }
  }
  Write-Host "    $flag $file" -ForegroundColor $color
}
Write-Sep

# ─── Tipos de commit convencional ─────────────────────────────────────────────
$types = @(
  @{ key='feat';     desc='Nova funcionalidade' }
  @{ key='fix';      desc='Correção de bug' }
  @{ key='docs';     desc='Documentação apenas' }
  @{ key='style';    desc='Formatação / estilo (sem lógica)' }
  @{ key='refactor'; desc='Refatoração (sem feat/fix)' }
  @{ key='perf';     desc='Melhoria de performance' }
  @{ key='test';     desc='Testes' }
  @{ key='build';    desc='Build / CI / dependências' }
  @{ key='chore';    desc='Tarefas de manutenção' }
  @{ key='ci';       desc='Workflows GitHub Actions' }
)

$scopes = @('sensor','pwm','relay','web','ws','ota','ci','docs','config','build','')

# ─── Mensagem direta (modo não-interativo) ─────────────────────────────────────
if ($Message) {
  $commitMsg = $Message
} else {
  # Tipo
  Write-Amber "Tipo do commit:"
  for ($i = 0; $i -lt $types.Count; $i++) {
    $t = $types[$i]
    Write-Host ("    [{0,2}] " -f ($i + 1)) -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-12}" -f $t.key)         -ForegroundColor DarkYellow -NoNewline
    Write-Host $t.desc                        -ForegroundColor DarkGray
  }
  $typeIdx = Read-Host "`n  Escolha [1-$($types.Count)]"
  if ($typeIdx -notmatch '^\d+$' -or [int]$typeIdx -lt 1 -or [int]$typeIdx -gt $types.Count) {
    Write-Err "Opção inválida."; exit 1
  }
  $commitType = $types[[int]$typeIdx - 1].key

  # Escopo
  Write-Sep
  Write-Amber "Escopo (opcional):"
  for ($i = 0; $i -lt $scopes.Count; $i++) {
    $s = if ($scopes[$i]) { $scopes[$i] } else { '(nenhum)' }
    Write-Host ("    [{0,2}] $s" -f ($i + 1)) -ForegroundColor DarkGray
  }
  $scopeIdx = Read-Host "`n  Escolha [1-$($scopes.Count)]"
  $scope = ''
  if ($scopeIdx -match '^\d+$' -and [int]$scopeIdx -ge 1 -and [int]$scopeIdx -le $scopes.Count) {
    $scope = $scopes[[int]$scopeIdx - 1]
  }

  # Descrição
  Write-Sep
  $desc = Read-Host "  Descrição (imperativo, sem ponto final)"
  if (-not $desc) { Write-Err "Descrição obrigatória."; exit 1 }

  # Breaking change?
  $breaking = Read-Host "  Breaking change? [s/N]"
  $breakNote = ''
  if ($breaking -imatch '^s') {
    $breakNote = Read-Host "  Descrição do breaking change"
  }

  # Monta mensagem
  $prefix = if ($scope) { "${commitType}(${scope})" } else { $commitType }
  $commitMsg = "${prefix}: ${desc}"
  if ($breakNote) { $commitMsg += "`n`nBREAKING CHANGE: $breakNote" }
}

# ─── Preview ───────────────────────────────────────────────────────────────────
Write-Sep
Write-Amber "Mensagem do commit:"
Write-Host "`n    $commitMsg`n" -ForegroundColor White
Write-Sep

# ─── Pre-commit hook ───────────────────────────────────────────────────────────
if (Test-Path ".githooks/pre-commit") {
  Write-Info "Executando pre-commit hook..."
  try {
    & bash .githooks/pre-commit
    Write-Ok "pre-commit OK"
  } catch {
    Write-Err "pre-commit falhou. Corrija antes de commitar."
    exit 1
  }
}

# ─── Staging ───────────────────────────────────────────────────────────────────
$addAll = Read-Host "  git add -A? [S/n]"
if ($addAll -notmatch '^n') {
  if ($DryRun) { Write-Info "[DRY-RUN] git add -A" }
  else { git add -A }
  Write-Ok "Staged: todos os arquivos"
}

# ─── Commit ────────────────────────────────────────────────────────────────────
if ($DryRun) {
  Write-Info "[DRY-RUN] git commit -m `"$commitMsg`""
  Write-Ok "Dry run concluído — nenhum commit criado."
  exit 0
}

git commit -m $commitMsg
if ($LASTEXITCODE -ne 0) { Write-Err "git commit falhou."; exit 1 }
Write-Ok "Commit criado com sucesso."

# ─── Push ──────────────────────────────────────────────────────────────────────
if ($Push) {
  Write-Info "Enviando para origin main..."
  git push origin main
  if ($LASTEXITCODE -ne 0) { Write-Err "git push falhou."; exit 1 }
  Write-Ok "Push concluído."
}

# ─── Tag (opcional) ────────────────────────────────────────────────────────────
$tagNow = Read-Host "`n  Criar tag de release? [s/N]"
if ($tagNow -imatch '^s') {
  $tagVer = Read-Host "  Versão (ex: 1.0.1)"
  if ($tagVer -match '^\d+\.\d+\.\d+$') {
    $tagMsg = Read-Host "  Mensagem da tag"
    if (-not $tagMsg) { $tagMsg = "RS50H v$tagVer" }
    git tag -a "v$tagVer" -m $tagMsg
    Write-Ok "Tag v$tagVer criada."
    $pushTag = Read-Host "  Push da tag? [S/n]"
    if ($pushTag -notmatch '^n') {
      git push origin "v$tagVer"
      Write-Ok "Tag enviada → CI/CD vai criar o Release automaticamente."
    }
  } else {
    Write-Warn "Formato inválido. Use X.Y.Z. Tag não criada."
  }
}

Write-Sep
Write-Ok "Pronto."
Write-Host ""
