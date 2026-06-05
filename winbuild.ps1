# winbuild.ps1
# Run from the repository root: .\winbuild.ps1

param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

function Write-Step($message) {
    Write-Host "[STEP] $message" -ForegroundColor Cyan
}

function Write-Ok($message) {
    Write-Host "[OK]   $message" -ForegroundColor Green
}

function Write-Fail($message) {
    Write-Host "[FAIL] $message" -ForegroundColor Red
}

function Ensure-DotNet10Sdk {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw 'dotnet is not on PATH. Install the .NET 10 SDK first.'
    }

    $sdkList = & dotnet --list-sdks
    $sdk10 = $sdkList | Where-Object { $_ -match '^10\.' }
    if (-not $sdk10) {
        throw "No .NET 10 SDK found. This project targets net10.0. Installed SDKs: $($sdkList -join '; ')"
    }
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $repoRoot 'src\opc-plc.csproj'
$publishDir = Join-Path $repoRoot 'artifacts\publish\fake-plc'

Write-Host "fake-plc Windows build"
Write-Host "Repo root: $repoRoot"
Write-Host "Configuration: $Configuration"
Write-Host "Publish dir: $publishDir"
Write-Host ""

if (-not (Test-Path $projectPath)) {
    Write-Fail "Missing project file: $projectPath"
    exit 1
}

try {
    Ensure-DotNet10Sdk

    if ($Clean) {
        Write-Step 'Cleaning bin/obj and published artifacts'
        $pathsToRemove = @(
            (Join-Path $repoRoot 'src\bin'),
            (Join-Path $repoRoot 'src\obj'),
            $publishDir
        )

        foreach ($path in $pathsToRemove) {
            if (Test-Path $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
                Write-Ok "Removed $path"
            }
        }
    }

    Write-Step 'Restoring NuGet packages'
    & dotnet restore $projectPath
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed with exit code $LASTEXITCODE" }

    Write-Step 'Building project'
    & dotnet build $projectPath --configuration $Configuration --no-restore
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }

    Write-Step 'Publishing runnable output'
    & dotnet publish $projectPath --configuration $Configuration --no-build --output $publishDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

    $outputDll = Join-Path $publishDir 'opcplc.dll'
    if (-not (Test-Path $outputDll)) {
        throw "Publish completed, but expected output was not found: $outputDll"
    }

    Write-Host ""
    Write-Ok "Build complete: $outputDll"
    Write-Ok "Next: .\winlaunch.ps1"
    exit 0
} catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    exit 1
}
