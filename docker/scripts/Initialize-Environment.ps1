[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

function New-DevelopmentSecret {
    param([int] $ByteCount = 36)

    $bytes = New-Object byte[] $ByteCount
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return ([Convert]::ToBase64String($bytes).TrimEnd([char[]]'=') -replace '\+', '-' -replace '/', '_')
}

Write-Host 'Comprobando Docker, Docker Desktop y Docker Compose V2...'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker no está instalado o no está disponible en PATH. Instale Docker Desktop manualmente.'
}

$dockerEngineAvailable = $true
if (-not (Test-DockerEngineAvailable)) {
    $dockerEngineAvailable = $false
    Write-Warning 'Docker Desktop no está ejecutándose o el motor no responde. Se crearán los archivos locales y se validará Compose, pero el script terminará con error.'
}

$composeVersion = & docker compose version --short 2>$null
if ($LASTEXITCODE -ne 0 -or -not $composeVersion) {
    throw 'Docker Compose V2 no está disponible.'
}

$environmentDirectory = Get-MisvalesEnvDirectory
$createdFiles = @()
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

$secretReplacements = @{
    'CHANGE_ME_POSTGRES_ADMIN_PASSWORD' = (New-DevelopmentSecret)
    'CHANGE_ME_POSTGRES_DEV_PASSWORD'   = (New-DevelopmentSecret)
    'CHANGE_ME_POSTGRES_TEST_PASSWORD'  = (New-DevelopmentSecret)
    'CHANGE_ME_REDIS_PASSWORD'          = (New-DevelopmentSecret)
    'CHANGE_ME_MINIO_ROOT_PASSWORD'     = (New-DevelopmentSecret)
    'CHANGE_ME_MINIO_APP_SECRET_KEY'    = (New-DevelopmentSecret)
    'CHANGE_ME_PGADMIN_PASSWORD'        = (New-DevelopmentSecret)
    'CHANGE_ME_GRAFANA_PASSWORD'        = (New-DevelopmentSecret)
}

foreach ($examplePath in Get-ChildItem -LiteralPath $environmentDirectory -Filter '*.env.example' -File | Sort-Object Name) {
    $destinationName = $examplePath.Name -replace '\.example$', ''
    $destinationPath = Join-Path $environmentDirectory $destinationName

    if (Test-Path -LiteralPath $destinationPath) {
        Write-Host "Conservado: docker/env/$destinationName"
        continue
    }

    $content = [System.IO.File]::ReadAllText($examplePath.FullName)
    foreach ($placeholder in $secretReplacements.Keys) {
        $content = $content.Replace($placeholder, $secretReplacements[$placeholder])
    }

    [System.IO.File]::WriteAllText($destinationPath, $content, $utf8WithoutBom)
    $createdFiles += "docker/env/$destinationName"
    Write-Host "Creado: docker/env/$destinationName (secretos generados y ocultos)"
}

Assert-MisvalesEnvironment
Import-MisvalesComposeVariables

Write-Host 'Validando compose.dev.yml sin imprimir variables sensibles...'
Invoke-MisvalesCompose -Arguments @('config', '--quiet')

if ($createdFiles.Count -eq 0) {
    Write-Host 'No se creó ningún archivo; todos los archivos locales ya existían.'
}
else {
    Write-Host "Archivos creados: $($createdFiles.Count)"
}

Write-Host "Docker Compose V2 detectado: $composeVersion"
if (-not $dockerEngineAvailable) {
    throw 'El entorno local quedó inicializado y Compose es válido, pero Docker Desktop debe estar operativo antes de iniciar servicios.'
}
Write-Host 'Siguiente comando: .\docker\scripts\Start-Services.ps1'
