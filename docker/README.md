# Entorno Docker de desarrollo de MisVales

Este entorno ejecuta únicamente dependencias externas de `misvales-backend`. Laravel, PHP, Composer, Artisan, Node.js y Angular se ejecutan directamente en Windows y no tienen contenedores en este proyecto.

## Requisitos

- Windows con PowerShell 5.1 o posterior.
- Docker Desktop iniciado.
- Docker Compose V2 (`docker compose`, no `docker-compose`).
- Puertos locales libres: `5432`, `6379`, `9000`, `9001`, `1025` y `8025` para los servicios principales.
- Para perfiles opcionales: `5050`, `5540`, `3000`, `4317` y `4318`.

Todos los puertos publicados están ligados a `127.0.0.1`; no son accesibles desde otras interfaces del equipo. Si un puerto predeterminado está ocupado, edite su variable en `docker/env/<servicio>.env` y use los scripts PowerShell, que importan las variables de puertos antes de llamar a Compose. Los comandos directos de Compose usan los valores predeterminados salvo que las variables estén presentes en la sesión de PowerShell.

## Primera ejecución

Desde la raíz de `misvales-backend`:

```powershell
.\docker\scripts\Initialize-Environment.ps1
.\docker\scripts\Start-Services.ps1
.\docker\scripts\Test-Services.ps1
```

El inicializador comprueba Docker, Docker Desktop y Compose V2; copia cada `*.env.example` solo cuando falta su archivo real; genera secretos aleatorios diferentes; no muestra secretos completos; y valida Compose con `config --quiet`. Nunca sobrescribe un archivo `.env` existente.

Si la política de ejecución corporativa bloquea scripts locales, use el alcance de un solo proceso (no cambia la política permanente del equipo):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\docker\scripts\Initialize-Environment.ps1
```

Los archivos reales `docker/env/*.env` son locales y están ignorados por Git. No contienen credenciales de producción y no deben confirmarse. Los ejemplos contienen marcadores `CHANGE_ME_*`, no secretos utilizables.

## Servicios

| Servicio | Finalidad | Dirección local | Puerto inicial | Perfil | Persistencia |
|---|---|---|---:|---|---|
| PostgreSQL | Base de desarrollo y pruebas | `127.0.0.1` | 5432 | predeterminado | `postgres_data` |
| Redis | Caché, sesiones, colas, límites y locks | `127.0.0.1` | 6379 | predeterminado | `redis_data` (AOF) |
| MinIO | API S3 privada | `http://127.0.0.1:9000` | 9000 | predeterminado | `minio_data` |
| MinIO Console | Administración local de MinIO | `http://127.0.0.1:9001` | 9001 | predeterminado | `minio_data` |
| Mailpit SMTP | Captura de correo local | `127.0.0.1` | 1025 | predeterminado | `mailpit_data` |
| Mailpit Web | Visualización del correo capturado | `http://127.0.0.1:8025` | 8025 | predeterminado | `mailpit_data` |
| pgAdmin | Administración visual de PostgreSQL | `http://127.0.0.1:5050` | 5050 | `tools` | `pgadmin_data` |
| RedisInsight | Administración visual de Redis | `http://127.0.0.1:5540` | 5540 | `tools` | `redisinsight_data` |
| Grafana | Consulta de métricas, logs y trazas | `http://127.0.0.1:3000` | 3000 | `observability` | `grafana_data` |
| Alloy OTLP gRPC | Recepción de telemetría | `127.0.0.1` | 4317 | `observability` | no aplica |
| Alloy OTLP HTTP | Recepción de telemetría | `http://127.0.0.1:4318` | 4318 | `observability` | no aplica |
| Prometheus | Métricas, accesible internamente por Grafana | `prometheus:9090` | interno | `observability` | `prometheus_data` |
| Loki | Logs, accesible internamente por Grafana | `loki:3100` | interno | `observability` | `loki_data` |
| Tempo | Trazas, accesible internamente por Grafana | `tempo:3200` | interno | `observability` | `tempo_data` |

`minio-init` es un contenedor auxiliar de una sola ejecución. Espera la salud de MinIO, crea o verifica los buckets, activa versionado, elimina acceso anónimo, crea la política restringida y termina con código cero. Es normal verlo como `Exited (0)`.

## Inicio y perfiles

Solo dependencias principales:

```powershell
.\docker\scripts\Start-Services.ps1
docker compose -f compose.dev.yml up -d
```

Herramientas:

```powershell
.\docker\scripts\Start-Services.ps1 -Tools
docker compose -f compose.dev.yml --profile tools up -d
```

Observabilidad:

```powershell
.\docker\scripts\Start-Services.ps1 -Observability
docker compose -f compose.dev.yml --profile observability up -d
```

Ambos perfiles:

```powershell
.\docker\scripts\Start-Services.ps1 -Tools -Observability
docker compose -f compose.dev.yml --profile tools --profile observability up -d
```

El comando predeterminado no inicia pgAdmin, RedisInsight, Prometheus, Loki, Tempo, Alloy ni Grafana.

## Comandos directos de Compose

```powershell
docker compose -f compose.dev.yml config
docker compose -f compose.dev.yml up -d
docker compose -f compose.dev.yml ps
docker compose -f compose.dev.yml logs -f
docker compose -f compose.dev.yml stop
docker compose -f compose.dev.yml down
```

`stop` conserva contenedores y volúmenes. `down` elimina contenedores y la red del proyecto, pero conserva los volúmenes nombrados. El siguiente comando destruye **todos los datos persistentes de este entorno de desarrollo**:

```powershell
docker compose -f compose.dev.yml down -v
```

Use preferentemente `Reset-Environment.ps1`, que exige escribir una confirmación explícita. No use `down -v` si necesita conservar bases, objetos, mensajes o datos de observabilidad.

## Scripts operativos

```powershell
.\docker\scripts\Show-Status.ps1
.\docker\scripts\Show-Logs.ps1
.\docker\scripts\Show-Logs.ps1 -Service postgres -Follow
.\docker\scripts\Stop-Services.ps1
.\docker\scripts\Test-Services.ps1
.\docker\scripts\Backup-Postgres.ps1
.\docker\scripts\Backup-Postgres.ps1 -Database misvales_test
.\docker\scripts\Restore-Postgres.ps1 -BackupPath .\docker\backups\misvales_dev-AAAAMMDD-HHMMSS.dump
.\docker\scripts\Reset-Environment.ps1
```

Los respaldos se guardan en `docker/backups/`, una carpeta ignorada por Git. La restauración solo admite `misvales_dev` y `misvales_test`, muestra el destino y exige escribir `RESTAURAR`. El reset exige escribir `ELIMINAR DATOS DE DESARROLLO` y no reinicia servicios salvo que se pase `-StartAfterReset`.

## PostgreSQL

La primera inicialización del volumen crea:

- `misvales_dev`, propiedad de `misvales_dev_user`.
- `misvales_test`, propiedad de `misvales_test_user`.
- `misvales_admin` como cuenta exclusiva de mantenimiento del servidor.

Los usuarios de aplicación tienen login y control de su propia base y esquema para migraciones, tablas, índices y secuencias; no tienen `SUPERUSER`, `CREATEDB`, `CREATEROLE`, replicación ni bypass de RLS. Laravel no debe usar `misvales_admin`.

El script `docker/postgres/init/01-create-databases.sh` es idempotente, pero la imagen oficial solo ejecuta `/docker-entrypoint-initdb.d` al inicializar un volumen vacío. Para aplicar cambios de identidad a un volumen existente se requiere una operación manual o reiniciar conscientemente el entorno.

Cada base de aplicación fija la zona de sesión de PostgreSQL en UTC para conservar instantes consistentes. Laravel es responsable de presentar y operar fechas en `America/Monterrey`; el sistema operativo de los contenedores usa esa zona cuando la imagen la admite.

pgAdmin recibe un registro de servidor para `postgres:5432`, sin guardar la contraseña. Para tareas habituales use `misvales_dev_user` y obtenga su contraseña de `docker/env/postgres.env`.

## Redis

La instancia usa autenticación, AOF con `appendfsync everysec` y `maxmemory-policy noeviction`, de modo que Redis rechaza escrituras bajo presión en lugar de expulsar silenciosamente trabajos pendientes. Una sola instancia es suficiente para desarrollo.

Separación lógica sugerida:

- datos generales/sesiones/colas/locks: DB `0`, con nombres de cola explícitos;
- caché: DB `1`, prefijo `misvales_dev_cache_`;
- pruebas: DB `2` y caché de pruebas DB `3`, prefijo `misvales_test_`;
- sesiones: cookie `misvales_dev_session`;
- rate limiting y locks: prefijos propios cuando la configuración del proyecto los exponga.

Laravel suele aplicar `REDIS_PREFIX` al cliente y `CACHE_PREFIX` al almacén de caché. Las colas se aíslan además mediante el nombre de cola. No copie variables de prefijo que el proyecto no haya conectado aún a sus archivos `config/*.php`.

En RedisInsight cree una conexión con host `redis`, puerto `6379`, sin TLS, y la contraseña de `docker/env/redis.env`. `127.0.0.1` no funciona desde RedisInsight porque allí apuntaría al propio contenedor.

## MinIO

Los buckets iniciales son privados y tienen versionado habilitado:

- `misvales-private`: identificaciones, comprobantes, fotografías, evidencias y documentos privados.
- `misvales-backups`: pruebas locales de respaldo y restauración.

La cuenta raíz de `docker/env/minio.env` se reserva para mantenimiento. Laravel usa `MINIO_APP_ACCESS_KEY` y `MINIO_APP_SECRET_KEY`; su política se limita a listar y operar objetos dentro de estos dos buckets. No hay políticas anónimas ni buckets públicos.

## Laravel fuera de Docker

No se modifica automáticamente el `.env` de Laravel. Copie manualmente el bloque necesario desde `docker/laravel.env.example` y complete secretos con estos archivos locales:

- `DB_PASSWORD` ← `MISVALES_DEV_PASSWORD` de `docker/env/postgres.env`.
- `DB_TEST_PASSWORD` ← `MISVALES_TEST_PASSWORD` de `docker/env/postgres.env`.
- `REDIS_PASSWORD` ← `REDIS_PASSWORD` de `docker/env/redis.env`.
- `AWS_ACCESS_KEY_ID` ← `MINIO_APP_ACCESS_KEY` de `docker/env/minio.env`.
- `AWS_SECRET_ACCESS_KEY` ← `MINIO_APP_SECRET_KEY` de `docker/env/minio.env`.

Laravel se ejecuta en Windows y por ello usa `127.0.0.1`, nunca los nombres internos `postgres`, `redis`, `minio` o `mailpit`:

```powershell
php artisan serve
php artisan queue:work
php artisan schedule:work
```

Estos comandos son manuales y ningún script Docker los ejecuta. Ejecute migraciones y seeders manualmente cuando corresponda; el entorno Docker nunca los lanza.

Para integrar Angular posteriormente, contemple los orígenes `http://localhost:4200` y `http://localhost:8000` en la configuración de autenticación/CORS elegida por el proyecto. Este entorno no inventa ni modifica esa configuración.

## Angular fuera de Docker

Angular también se ejecuta en Windows:

```powershell
ng serve
```

Angular consume exclusivamente la API de Laravel. Nunca debe conectarse directamente a PostgreSQL, Redis, SMTP de Mailpit ni a MinIO con credenciales administrativas.

## Mailpit

Laravel envía por SMTP a `127.0.0.1:1025`. Mailpit conserva los mensajes capturados en su volumen y no tiene configurado ningún relay, webhook ni salida SMTP hacia Internet.

## Observabilidad local

Grafana aprovisiona automáticamente Prometheus, Loki y Tempo. Alloy recibe OTLP por gRPC (`127.0.0.1:4317`) y HTTP (`127.0.0.1:4318`), envía métricas a Prometheus, logs a Loki y trazas a Tempo. La pila inicia sin que Laravel esté instrumentado y no envía telemetría fuera del equipo.

El bloque OpenTelemetry de `docker/laravel.env.example` es un punto de conexión para una integración posterior; no instala paquetes ni modifica Laravel. No hay alertas ni configuración de producción.

## Diagnóstico

```powershell
.\docker\scripts\Show-Status.ps1
.\docker\scripts\Show-Logs.ps1 -Service minio minio-init
.\docker\scripts\Test-Services.ps1
```

Si Docker Desktop está detenido, los scripts operativos terminan con un mensaje explícito. Si se modifican credenciales de PostgreSQL o MinIO después de crear los volúmenes, el cambio no reescribe automáticamente las identidades existentes; restaure los valores anteriores o reinicie voluntariamente el entorno después de respaldar datos.
