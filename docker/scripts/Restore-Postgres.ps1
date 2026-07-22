[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $BackupPath,

    [ValidateSet('misvales_dev', 'misvales_test')]
    [string] $Database = 'misvales_dev'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

$resolvedBackup = Resolve-Path -LiteralPath $BackupPath -ErrorAction Stop
if (-not (Test-Path -LiteralPath $resolvedBackup.Path -PathType Leaf)) {
    throw "El respaldo no es un archivo: $BackupPath"
}

Write-Warning "La base local '$Database' será modificada y los objetos incluidos en el respaldo se reemplazarán."
Write-Host 'Este script solo permite misvales_dev o misvales_test; no admite destinos de producción.'
$confirmation = Read-Host "Escriba RESTAURAR para continuar"
if ($confirmation -cne 'RESTAURAR') {
    Write-Host 'Restauración cancelada. No se modificó la base de datos.'
    exit 0
}

$containerFileName = "restore-$([Guid]::NewGuid().ToString('N')).dump"
$containerPath = "/tmp/$containerFileName"

if ($Database -eq 'misvales_test') {
    $restoreCommand = 'PGPASSWORD="$MISVALES_TEST_PASSWORD" pg_restore -U "$MISVALES_TEST_USER" -d "$MISVALES_TEST_DB" --clean --if-exists --no-owner --no-acl --exit-on-error "$1"'
}
else {
    $restoreCommand = 'PGPASSWORD="$MISVALES_DEV_PASSWORD" pg_restore -U "$MISVALES_DEV_USER" -d "$MISVALES_DEV_DB" --clean --if-exists --no-owner --no-acl --exit-on-error "$1"'
}

try {
    Invoke-MisvalesCompose -Arguments @('cp', $resolvedBackup.Path, "postgres:$containerPath")
    Invoke-MisvalesCompose -Arguments @('exec', '-T', 'postgres', 'sh', '-ec', $restoreCommand, 'sh', $containerPath)
}
finally {
    & docker compose -f (Get-MisvalesComposeFile) exec -T postgres rm -f -- $containerPath *> $null
}

Write-Host "Restauración finalizada sobre la base local '$Database'."
