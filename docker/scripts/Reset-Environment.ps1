[CmdletBinding()]
param(
    [switch] $StartAfterReset,
    [switch] $Tools,
    [switch] $Observability
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

Write-Warning 'Esta operación eliminará de forma irreversible todos los volúmenes persistentes de misvales-dev.'
Write-Host 'Se perderán PostgreSQL, Redis, MinIO, Mailpit, herramientas y observabilidad locales.'
$confirmation = Read-Host 'Escriba ELIMINAR DATOS DE DESARROLLO para continuar'
if ($confirmation -cne 'ELIMINAR DATOS DE DESARROLLO') {
    Write-Host 'Reinicio cancelado. No se eliminó ningún volumen.'
    exit 0
}

$arguments = Get-MisvalesAllProfileArguments
$arguments += @('down', '--volumes', '--remove-orphans')
Invoke-MisvalesCompose -Arguments $arguments
Write-Host 'Se eliminaron únicamente los contenedores, red y volúmenes administrados por el proyecto misvales-dev.'

if ($StartAfterReset) {
    $startScript = Join-Path $PSScriptRoot 'Start-Services.ps1'
    & $startScript -Tools:$Tools -Observability:$Observability
}
else {
    Write-Host 'Los servicios no se reiniciaron. Ejecute .\docker\scripts\Start-Services.ps1 cuando lo decida.'
}
