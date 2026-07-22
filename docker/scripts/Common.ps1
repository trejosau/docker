Set-StrictMode -Version Latest

function Get-MisvalesProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-MisvalesComposeFile {
    return (Join-Path (Get-MisvalesProjectRoot) 'compose.dev.yml')
}

function Get-MisvalesEnvDirectory {
    return (Join-Path (Get-MisvalesProjectRoot) 'docker\env')
}

function Get-MisvalesRequiredEnvFiles {
    return @(
        'postgres.env',
        'redis.env',
        'minio.env',
        'mailpit.env',
        'pgadmin.env',
        'redisinsight.env',
        'observability.env'
    )
}

function Assert-MisvalesEnvironment {
    $missingFiles = @()
    $environmentDirectory = Get-MisvalesEnvDirectory

    foreach ($fileName in Get-MisvalesRequiredEnvFiles) {
        $path = Join-Path $environmentDirectory $fileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missingFiles += $path
        }
    }

    if ($missingFiles.Count -gt 0) {
        throw "Faltan archivos de entorno. Ejecute .\docker\scripts\Initialize-Environment.ps1 primero.`n$($missingFiles -join "`n")"
    }
}

function Get-MisvalesEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FileName,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $path = Join-Path (Get-MisvalesEnvDirectory) $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "No existe el archivo de entorno: $path"
    }

    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line -match '^\s*([^#][^=]*?)\s*=\s*(.*)\s*$') {
            $variableName = $Matches[1].Trim()
            if ($variableName -eq $Name) {
                $value = $Matches[2].Trim()
                if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                    ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                    return $value.Substring(1, $value.Length - 2)
                }
                return $value
            }
        }
    }

    throw "No se encontró $Name en $path"
}

function Import-MisvalesComposeVariables {
    $variableSources = [ordered]@{
        POSTGRES_PORT        = 'postgres.env'
        REDIS_PORT           = 'redis.env'
        MINIO_API_PORT       = 'minio.env'
        MINIO_CONSOLE_PORT   = 'minio.env'
        MAILPIT_SMTP_PORT    = 'mailpit.env'
        MAILPIT_WEB_PORT     = 'mailpit.env'
        PGADMIN_PORT         = 'pgadmin.env'
        REDISINSIGHT_PORT    = 'redisinsight.env'
        GRAFANA_PORT         = 'observability.env'
        OTLP_GRPC_PORT       = 'observability.env'
        OTLP_HTTP_PORT       = 'observability.env'
    }

    foreach ($entry in $variableSources.GetEnumerator()) {
        $value = Get-MisvalesEnvValue -FileName $entry.Value -Name $entry.Key
        [Environment]::SetEnvironmentVariable($entry.Key, $value, 'Process')
    }
}

function Test-DockerEngineAvailable {
    param([ValidateRange(1, 60)][int] $TimeoutSeconds = 15)

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCommand) {
        return $false
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerCommand.Source
    $startInfo.Arguments = 'info --format "{{.ServerVersion}}"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return $false
        }
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            return $false
        }
        return ($process.ExitCode -eq 0)
    }
    finally {
        $process.Dispose()
    }
}

function Assert-DockerEngine {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker no está instalado o no está disponible en PATH.'
    }

    if (-not (Test-DockerEngineAvailable)) {
        throw 'Docker Desktop no está ejecutándose o el motor Docker no responde.'
    }

    & docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose V2 no está disponible.'
    }
}

function Invoke-MisvalesCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $composeFile = Get-MisvalesComposeFile
    & docker compose -f $composeFile @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose terminó con código $LASTEXITCODE."
    }
}

function Get-MisvalesAllProfileArguments {
    return @('--profile', 'tools', '--profile', 'observability')
}
