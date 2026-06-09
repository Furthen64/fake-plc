# adduser.ps1
# Run from the repository root: .\adduser.ps1

param(
    [ValidateSet('default', 'admin')]
    [string]$Role = 'default',
    [string]$Username,
    [string]$Password,
    [int]$PasswordLength = 20,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Show-AddUserHelp {
    Write-Host 'fake-plc adduser helper'
    Write-Host
    Write-Host 'Create fake-plc username/password startup arguments.'
    Write-Host 'Provide -Username and -Password to use explicit credentials, or omit -Password to generate one.'
    Write-Host
    Write-Host 'Parameters:'
    Write-Host '  -Role <default|admin>     Credential role to create. Default: default'
    Write-Host '  -Username <name>          Explicit username to use instead of a generated one'
    Write-Host '  -Password <value>         Explicit password to use instead of a generated one'
    Write-Host '  -PasswordLength <n>       Generated password length. Minimum: 12. Default: 20'
    Write-Host '  -Json                     Emit JSON output'
    Write-Host
    Write-Host 'Examples:'
    Write-Host '  .\adduser.ps1'
    Write-Host '      Show this help text.'
    Write-Host
    Write-Host '  .\adduser.ps1 -Role admin'
    Write-Host '      Generate random admin credentials and matching opcplc arguments.'
    Write-Host
    Write-Host '  .\adduser.ps1 -Username operator1 -Password changeme'
    Write-Host '      Create credentials for operator1 using the explicit password changeme.'
    Write-Host
    Write-Host '  .\adduser.ps1 -Username operator1 -PasswordLength 24'
    Write-Host '      Create credentials for operator1 with a 24-character generated password.'
}

if ($PSBoundParameters.Count -eq 0) {
    Show-AddUserHelp
    exit 0
}

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

if ($null -ne $Password) {
    $arguments += "--password=$Password"
}

if ($Json) {
    $arguments += '--json'
}

& dotnet @arguments
exit $LASTEXITCODE
