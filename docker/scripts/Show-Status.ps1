[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

Write-Host 'Estado, salud y puertos publicados:'
$arguments = Get-MisvalesAllProfileArguments
$arguments += @('ps', '--all')
Invoke-MisvalesCompose -Arguments $arguments
