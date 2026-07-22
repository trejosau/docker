[CmdletBinding()]
param(
    [switch] $Tools,
    [switch] $Observability
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

$arguments = @()
if ($Tools) {
    $arguments += @('--profile', 'tools')
}
if ($Observability) {
    $arguments += @('--profile', 'observability')
}
$arguments += @('up', '-d')

Invoke-MisvalesCompose -Arguments $arguments
Write-Host 'Servicios solicitados iniciados. Estado actual:'
$statusArguments = @()
if ($Tools) { $statusArguments += @('--profile', 'tools') }
if ($Observability) { $statusArguments += @('--profile', 'observability') }
$statusArguments += @('ps')
Invoke-MisvalesCompose -Arguments $statusArguments
