# adduser.ps1
# Run from the repository root: .\adduser.ps1

param(
    [Parameter(Position = 0)]
    [string]$Username,
    [Parameter(Position = 1)]
    [string]$Password,
    [Parameter(Position = 2)]
    [ValidateSet('default', 'admin')]
    [string]$Role = 'default',
    [int]$PasswordLength = 20,
    [switch]$Json,
    [string]$StorePath
)

$ErrorActionPreference = 'Stop'

function Show-AddUserHelp {
    Write-Host 'fake-plc adduser manager'
    Write-Host
    Write-Host 'Create or update persisted fake-plc username/password users.'
    Write-Host 'Provide Username and Password explicitly, or omit Password to generate one.'
    Write-Host
    Write-Host 'Parameters:'
    Write-Host '  [Username]                Username to create or update'
    Write-Host '  [Password]                Password to store; omit to generate one'
    Write-Host '  -Role <default|admin>     Credential role to store. Default: default'
    Write-Host '  -PasswordLength <n>       Generated password length. Minimum: 12. Default: 20'
    Write-Host '  -StorePath <path>         Persisted user store path. Default: .\artifacts\fake-plc-users.json'
    Write-Host '  -Json                     Emit JSON output'
    Write-Host
    Write-Host 'Examples:'
    Write-Host '  .\adduser.ps1'
    Write-Host '      Show this help text.'
    Write-Host
    Write-Host '  .\adduser.ps1 oper1 pass1'
    Write-Host '      Persist a default user named oper1 with password pass1.'
    Write-Host
    Write-Host '  .\adduser.ps1 admin1 pass2 -Role admin'
    Write-Host '      Persist an admin user named admin1 with password pass2.'
    Write-Host
    Write-Host '  .\adduser.ps1 operator1 -PasswordLength 24'
    Write-Host '      Persist operator1 with a generated 24-character password.'
    Write-Host
    Write-Host 'Users saved by this script are loaded automatically by .\winlaunch.ps1.'
}

if ($PSBoundParameters.Count -eq 0) {
    Show-AddUserHelp
    exit 0
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $repoRoot 'tools\fake-plc-adduser\fake-plc-adduser.csproj'

if (-not $StorePath) {
    $StorePath = Join-Path $repoRoot 'artifacts\fake-plc-users.json'
}

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
$arguments += "--store=$StorePath"

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
