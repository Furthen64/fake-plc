# checkreqs.ps1
# Run from the repository root: .\checkreqs.ps1

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

function Test-Command($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $repoRoot 'src\opc-plc.csproj'
$solutionPath = Join-Path $repoRoot 'opcplc.sln'

Write-Host "fake-plc Windows requirement check"
Write-Host "Repo root: $repoRoot"
Write-Host ""

$hadError = $false

if (Test-Path $projectPath) {
    Write-Ok "Found main project: src\opc-plc.csproj"
} else {
    Write-Fail "Missing main project: src\opc-plc.csproj"
    $hadError = $true
}

if (Test-Path $solutionPath) {
    Write-Ok "Found solution: opcplc.sln"
} else {
    Write-Warn "Missing solution: opcplc.sln"
}

if (Test-Command git) {
    $gitVersion = (& git --version) -join ' '
    Write-Ok "Git available: $gitVersion"
} else {
    Write-Warn "Git is not on PATH. Build can still work if the repo is already downloaded."
}

if (-not (Test-Command dotnet)) {
    Write-Fail "dotnet is not on PATH. Install the .NET 10 SDK."
    $hadError = $true
} else {
    $dotnetInfo = & dotnet --info
    $sdkList = & dotnet --list-sdks
    $sdk10 = $sdkList | Where-Object { $_ -match '^10\.' }

    $dotnetVersion = (& dotnet --version).Trim()
    Write-Ok "dotnet available: $dotnetVersion"

    if ($sdk10) {
        Write-Ok ".NET 10 SDK found: $($sdk10 -join ', ')"
    } else {
        Write-Fail "No .NET 10 SDK found. This project targets net10.0. Installed SDKs: $($sdkList -join '; ')"
        $hadError = $true
    }
}

$portsToCheck = @(50000, 8080)
foreach ($port in $portsToCheck) {
    $listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($listeners) {
        $owners = $listeners | Select-Object -ExpandProperty OwningProcess -Unique
        Write-Warn "TCP port $port is already listening. Owning PID(s): $($owners -join ', ')"
    } else {
        Write-Ok "TCP port $port appears free"
    }
}

$publishDir = Join-Path $repoRoot 'artifacts\publish\fake-plc'
if (Test-Path (Join-Path $publishDir 'opcplc.dll')) {
    Write-Ok "Existing published build found: artifacts\publish\fake-plc\opcplc.dll"
} else {
    Write-Warn "No published build yet. Run .\winbuild.ps1 next."
}

Write-Host ""
if ($hadError) {
    Write-Fail "Requirement check failed. Fix the failed items above, then run this script again."
    exit 1
}

Write-Ok "Requirement check passed. Next: .\winbuild.ps1"
exit 0
