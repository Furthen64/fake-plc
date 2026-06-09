# winlaunch.ps1
# Run from the repository root after .\winbuild.ps1: .\winlaunch.ps1

param(
    [int]$Port = 50000,
    [int]$WebPort = 8080,
    [int]$SlowNodes = 5,
    [int]$SlowRateSeconds = 10,
    [ValidateSet('UInt', 'Double', 'Bool', 'UIntArray')]
    [string]$SlowType = 'Double',
    [int]$FastNodes = 5,
    [int]$FastRateSeconds = 1,
    [ValidateSet('UInt', 'Double', 'Bool', 'UIntArray')]
    [string]$FastType = 'Double',
    [switch]$Stacklight,
    [switch]$PublisherJson,
    [switch]$NoAutoAccept,
    [switch]$Unsecure = $true,
    [string]$NodesFile,
    [string[]]$ExtraOpcPlcArgs = @()
)

$ErrorActionPreference = 'Stop'

function Write-Ok($message) {
    Write-Host "[OK]   $message" -ForegroundColor Green
}

function Write-Warn($message) {
    Write-Host "[WARN] $message" -ForegroundColor Yellow
}

function Write-Fail($message) {
    Write-Host "[FAIL] $message" -ForegroundColor Red
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$publishDir = Join-Path $repoRoot 'artifacts\publish\fake-plc'
$appDll = Join-Path $publishDir 'opcplc.dll'
$userStorePath = Join-Path $repoRoot 'artifacts\fake-plc-users.json'

Write-Host "fake-plc Windows launch"
Write-Host "Repo root: $repoRoot"
Write-Host "App: $appDll"
Write-Host ""

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Fail 'dotnet is not on PATH. Run .\checkreqs.ps1 first.'
    exit 1
}

if (-not (Test-Path $appDll)) {
    Write-Fail "Published app not found: $appDll"
    Write-Host "Run .\winbuild.ps1 first."
    exit 1
}

$portListeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($portListeners) {
    $owners = $portListeners | Select-Object -ExpandProperty OwningProcess -Unique
    Write-Fail "TCP port $Port is already listening. Owning PID(s): $($owners -join ', ')"
    exit 1
}

$launchArgs = @(
    $appDll,
    "--pn=$Port",
    "--wp=$WebPort",
    '--at=X509Store',
    "--sn=$SlowNodes",
    "--sr=$SlowRateSeconds",
    "--st=$SlowType",
    "--fn=$FastNodes",
    "--fr=$FastRateSeconds",
    "--ft=$FastType"
)

if (-not $NoAutoAccept) {
    $launchArgs += '--autoaccept'
}

if ($PublisherJson) {
    $launchArgs += '--sph'
}

if ($Stacklight) {
    $launchArgs += '--sl'
}

if ($Unsecure) {
    $launchArgs += '--unsecuretransport'
}

if ($NodesFile) {
    $resolvedNodesFile = Resolve-Path -LiteralPath $NodesFile -ErrorAction Stop
    $launchArgs += "--nodesfile=$resolvedNodesFile"
}

if (Test-Path $userStorePath) {
    $resolvedUserStorePath = Resolve-Path -LiteralPath $userStorePath -ErrorAction Stop
    $launchArgs += "--usersfile=$resolvedUserStorePath"
    Write-Ok "Loading persisted users from $resolvedUserStorePath"
} else {
    Write-Warn "No persisted user store found at $userStorePath; built-in username/password users remain active."
}

if ($ExtraOpcPlcArgs.Count -gt 0) {
    $launchArgs += $ExtraOpcPlcArgs
}

Write-Ok "Starting OPC UA fake PLC on opc.tcp://localhost:$Port"
Write-Host ""
Write-Host "Useful client settings:"
if ($Unsecure) {
    Write-Host "  Security policy: None"
    Write-Host "  Message mode: None"
} else {
    Write-Host "  Security policy: Basic256Sha256"
    Write-Host "  Message mode: Sign & Encrypt"
    Write-Host "  First client certificate should be auto-accepted unless -NoAutoAccept is used."
}
Write-Host ""
Write-Host "Press Ctrl+C to stop."
Write-Host ""

Push-Location $publishDir
try {
    & dotnet @launchArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
