[CmdletBinding()]
param(
    [string[]] $Service,
    [switch] $Follow,
    [ValidateRange(1, 10000)]
    [int] $Tail = 200
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

$arguments = Get-MisvalesAllProfileArguments
$arguments += @('logs', '--tail', $Tail.ToString())
if ($Follow) {
    $arguments += '--follow'
}
if ($Service) {
    $arguments += $Service
}

Invoke-MisvalesCompose -Arguments $arguments
