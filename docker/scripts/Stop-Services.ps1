[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

$arguments = Get-MisvalesAllProfileArguments
$arguments += 'stop'
Invoke-MisvalesCompose -Arguments $arguments
Write-Host 'Servicios detenidos. Los volúmenes persistentes se conservaron.'
