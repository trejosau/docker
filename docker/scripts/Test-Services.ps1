[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-MisvalesEnvironment
Assert-DockerEngine
Import-MisvalesComposeVariables

$results = [ordered]@{}
$details = New-Object System.Collections.Generic.List[string]

function Invoke-ServiceCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Action
    )

    try {
        $null = & $Action
        $script:results[$Name] = 'correcto'
    }
    catch {
        $script:results[$Name] = 'FALLÓ'
        $script:details.Add("${Name}: $($_.Exception.Message)")
    }
}

Invoke-ServiceCheck -Name 'PostgreSQL' -Action {
    Invoke-MisvalesCompose -Arguments @(
        'exec', '-T', 'postgres', 'sh', '-ec',
        'PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT 1" | grep -qx 1'
    )
}

Invoke-ServiceCheck -Name 'Bases PostgreSQL' -Action {
    Invoke-MisvalesCompose -Arguments @(
        'exec', '-T', 'postgres', 'sh', '-ec',
        'test "$(PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT count(*) FROM pg_database WHERE datname IN (''misvales_dev'',''misvales_test'')")" = "2"'
    )
}

Invoke-ServiceCheck -Name 'Usuario PostgreSQL desarrollo' -Action {
    Invoke-MisvalesCompose -Arguments @(
        'exec', '-T', 'postgres', 'sh', '-ec',
        'PGPASSWORD="$MISVALES_DEV_PASSWORD" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$MISVALES_DEV_USER" -d "$MISVALES_DEV_DB" -tAc "SELECT current_user" | grep -qx "$MISVALES_DEV_USER" && test "$(PGPASSWORD="$MISVALES_DEV_PASSWORD" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$MISVALES_DEV_USER" -d "$MISVALES_DEV_DB" -tAc "SELECT (NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls)::int FROM pg_roles WHERE rolname = current_user")" = "1" && PGPASSWORD="$MISVALES_DEV_PASSWORD" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$MISVALES_DEV_USER" -d "$MISVALES_DEV_DB" -c "BEGIN; CREATE TABLE docker_permission_check (id bigserial PRIMARY KEY); CREATE INDEX docker_permission_check_id_idx ON docker_permission_check (id); INSERT INTO docker_permission_check DEFAULT VALUES; ROLLBACK;" >/dev/null'
    )
}

Invoke-ServiceCheck -Name 'Usuario PostgreSQL pruebas' -Action {
    Invoke-MisvalesCompose -Arguments @(
        'exec', '-T', 'postgres', 'sh', '-ec',
        'PGPASSWORD="$MISVALES_TEST_PASSWORD" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$MISVALES_TEST_USER" -d "$MISVALES_TEST_DB" -tAc "SELECT current_user" | grep -qx "$MISVALES_TEST_USER" && test "$(PGPASSWORD="$MISVALES_TEST_PASSWORD" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$MISVALES_TEST_USER" -d "$MISVALES_TEST_DB" -tAc "SELECT (NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls)::int FROM pg_roles WHERE rolname = current_user")" = "1" && PGPASSWORD="$MISVALES_TEST_PASSWORD" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$MISVALES_TEST_USER" -d "$MISVALES_TEST_DB" -c "BEGIN; CREATE TABLE docker_permission_check (id bigserial PRIMARY KEY); CREATE INDEX docker_permission_check_id_idx ON docker_permission_check (id); INSERT INTO docker_permission_check DEFAULT VALUES; ROLLBACK;" >/dev/null'
    )
}

Invoke-ServiceCheck -Name 'Redis' -Action {
    Invoke-MisvalesCompose -Arguments @(
        'exec', '-T', 'redis', 'sh', '-ec',
        'redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping | grep -qx PONG'
    )
}

Invoke-ServiceCheck -Name 'MinIO' -Action {
    $port = Get-MisvalesEnvValue -FileName 'minio.env' -Name 'MINIO_API_PORT'
    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/minio/health/ready" -TimeoutSec 5
    if ($response.StatusCode -ne 200) {
        throw "respuesta HTTP inesperada: $($response.StatusCode)"
    }
}

Invoke-ServiceCheck -Name 'Buckets' -Action {
    Invoke-MisvalesCompose -Arguments @(
        'run', '--rm', '--no-deps', '--entrypoint', '/bin/sh', 'minio-init', '-ec',
        'mc alias set check http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && for bucket in "$MINIO_PRIVATE_BUCKET" "$MINIO_BACKUPS_BUCKET"; do mc stat "check/$bucket" >/dev/null; mc anonymous get "check/$bucket" 2>&1 | grep -qi private; done'
    )
}

Invoke-ServiceCheck -Name 'Cuenta MinIO aplicación' -Action {
    Invoke-MisvalesCompose -Arguments @(
        'run', '--rm', '--no-deps', '--entrypoint', '/bin/sh', 'minio-init', '-ec',
        'mc alias set appcheck http://minio:9000 "$MINIO_APP_ACCESS_KEY" "$MINIO_APP_SECRET_KEY" >/dev/null && mc ls "appcheck/$MINIO_PRIVATE_BUCKET" >/dev/null && mc ls "appcheck/$MINIO_BACKUPS_BUCKET" >/dev/null && object_name=".docker-permission-check-$$" && printf test >/tmp/object-check && mc cp /tmp/object-check "appcheck/$MINIO_PRIVATE_BUCKET/$object_name" >/dev/null && mc stat "appcheck/$MINIO_PRIVATE_BUCKET/$object_name" >/dev/null && mc rm "appcheck/$MINIO_PRIVATE_BUCKET/$object_name" >/dev/null && if mc ls appcheck >/dev/null 2>&1; then exit 1; fi'
    )
}

Invoke-ServiceCheck -Name 'Mailpit SMTP' -Action {
    $port = [int](Get-MisvalesEnvValue -FileName 'mailpit.env' -Name 'MAILPIT_SMTP_PORT')
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connectTask = $client.ConnectAsync('127.0.0.1', $port)
        if (-not $connectTask.Wait(5000)) {
            throw 'tiempo de espera agotado al conectar'
        }
        $client.ReceiveTimeout = 5000
        $reader = New-Object System.IO.StreamReader($client.GetStream())
        $banner = $reader.ReadLine()
        if (-not $banner.StartsWith('220')) {
            throw "banner SMTP inesperado: $banner"
        }
    }
    finally {
        $client.Dispose()
    }
}

Invoke-ServiceCheck -Name 'Mailpit Web' -Action {
    $port = Get-MisvalesEnvValue -FileName 'mailpit.env' -Name 'MAILPIT_WEB_PORT'
    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/livez" -TimeoutSec 5
    if ($response.StatusCode -ne 200) {
        throw "respuesta HTTP inesperada: $($response.StatusCode)"
    }
}

$allProfiles = Get-MisvalesAllProfileArguments
$runningArguments = $allProfiles + @('ps', '--services', '--status', 'running')
$runningServices = @(& docker compose -f (Get-MisvalesComposeFile) @runningArguments)
if ($LASTEXITCODE -ne 0) {
    throw 'No fue posible consultar los servicios opcionales activos.'
}

$optionalWebChecks = [ordered]@{
    pgadmin      = @{ Name = 'pgAdmin'; File = 'pgadmin.env'; Variable = 'PGADMIN_PORT'; Path = '/misc/ping' }
    redisinsight = @{ Name = 'RedisInsight'; File = 'redisinsight.env'; Variable = 'REDISINSIGHT_PORT'; Path = '/api/health/' }
    grafana      = @{ Name = 'Grafana'; File = 'observability.env'; Variable = 'GRAFANA_PORT'; Path = '/api/health' }
}

foreach ($service in $optionalWebChecks.Keys) {
    if ($runningServices -contains $service) {
        $check = $optionalWebChecks[$service]
        Invoke-ServiceCheck -Name $check.Name -Action {
            $port = Get-MisvalesEnvValue -FileName $check.File -Name $check.Variable
            $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port$($check.Path)" -TimeoutSec 5
            if ($response.StatusCode -ne 200) {
                throw "respuesta HTTP inesperada: $($response.StatusCode)"
            }
        }
    }
}

foreach ($service in @('prometheus', 'loki', 'tempo', 'alloy')) {
    if ($runningServices -contains $service) {
        Invoke-ServiceCheck -Name $service -Action {
            $containerId = & docker compose -f (Get-MisvalesComposeFile) @allProfiles ps -q $service
            if ($LASTEXITCODE -ne 0 -or -not $containerId) {
                throw 'no se encontró el contenedor activo'
            }
            $health = & docker inspect --format '{{.State.Health.Status}}' $containerId
            if ($LASTEXITCODE -ne 0 -or $health -ne 'healthy') {
                throw "estado de salud: $health"
            }
        }
    }
}

if ($runningServices -contains 'alloy') {
    foreach ($entry in @(
        @{ Name = 'OTLP gRPC'; Variable = 'OTLP_GRPC_PORT' },
        @{ Name = 'OTLP HTTP'; Variable = 'OTLP_HTTP_PORT' }
    )) {
        Invoke-ServiceCheck -Name $entry.Name -Action {
            $port = [int](Get-MisvalesEnvValue -FileName 'observability.env' -Name $entry.Variable)
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $task = $client.ConnectAsync('127.0.0.1', $port)
                if (-not $task.Wait(5000)) {
                    throw 'tiempo de espera agotado al conectar'
                }
            }
            finally {
                $client.Dispose()
            }
        }
    }
}

Write-Host ''
Write-Host 'Resumen de validación:'
foreach ($result in $results.GetEnumerator()) {
    Write-Host ("{0}: {1}" -f $result.Key, $result.Value)
}

if ($details.Count -gt 0) {
    Write-Host ''
    Write-Host 'Detalles de errores:'
    foreach ($detail in $details) {
        Write-Host "- $detail"
    }
    exit 1
}
