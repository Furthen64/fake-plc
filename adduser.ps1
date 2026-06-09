# adduser.ps1
# Run from the repository root: .\adduser.ps1

param(
    [ValidateSet('default', 'admin')]
    [string]$Role = 'default',
    [string]$Username,
    [int]$PasswordLength = 20,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $repoRoot 'tools\fake-plc-adduser\fake-plc-adduser.csproj'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error 'dotnet is not on PATH.'
}

if (-not (Test-Path $projectPath)) {
    Write-Error "Generator project not found: $projectPath"
}

$arguments = @(
    'run',
    '--project', $projectPath,
    '--framework', 'net10.0',
    '--'
)

$arguments += "--role=$Role"
$arguments += "--password-length=$PasswordLength"

if ($Username) {
    $arguments += "--username=$Username"
}

if ($Json) {
    $arguments += '--json'
}

& dotnet @arguments
exit $LASTEXITCODE
