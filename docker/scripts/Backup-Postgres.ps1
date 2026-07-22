[CmdletBinding()]
param(
    [ValidateSet('misvales_dev', 'misvales_test')]
    [string] $Database = 'misvales_dev'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

$projectRoot = Get-MisvalesProjectRoot
$backupDirectory = Join-Path $projectRoot 'docker\backups'
[System.IO.Directory]::CreateDirectory($backupDirectory) | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$fileName = "${Database}-${timestamp}.dump"
$hostPath = Join-Path $backupDirectory $fileName
$containerPath = "/tmp/$fileName"

if ($Database -eq 'misvales_test') {
    $dumpCommand = 'PGPASSWORD="$MISVALES_TEST_PASSWORD" pg_dump -U "$MISVALES_TEST_USER" -d "$MISVALES_TEST_DB" --format=custom --no-owner --no-acl --file="$1"'
}
else {
    $dumpCommand = 'PGPASSWORD="$MISVALES_DEV_PASSWORD" pg_dump -U "$MISVALES_DEV_USER" -d "$MISVALES_DEV_DB" --format=custom --no-owner --no-acl --file="$1"'
}

try {
    Invoke-MisvalesCompose -Arguments @('exec', '-T', 'postgres', 'sh', '-ec', $dumpCommand, 'sh', $containerPath)
    Invoke-MisvalesCompose -Arguments @('cp', "postgres:$containerPath", $hostPath)
}
finally {
    & docker compose -f (Get-MisvalesComposeFile) exec -T postgres rm -f -- $containerPath *> $null
}

if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
    throw 'pg_dump terminó sin producir el archivo local esperado.'
}

Write-Host "Respaldo creado: $hostPath"
