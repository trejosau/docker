# Docker local de MisVales

Infraestructura local administrada únicamente con Docker Compose. No requiere scripts auxiliares.

## Primera ejecución

Docker Compose necesita un `.env` local con las credenciales y puertos:

```powershell
Copy-Item .env.example .env
```

Cambie en `.env` todos los valores `CHANGE_ME_*`. El archivo `.env` está ignorado por Git y `.env.example` es la plantilla versionable.

Después, levante los servicios principales:

```powershell
docker compose up -d
```

El archivo se llama `compose.yml`, por lo que no es necesario indicar `-f`.

## Servicios principales

| Servicio | Acceso local | Persistencia |
|---|---|---|
| PostgreSQL | `127.0.0.1:5432` | `postgres_data` |
| Redis | `127.0.0.1:6379` | `redis_data` |
| MinIO API | `http://127.0.0.1:9000` | `minio_data` |
| MinIO Console | `http://127.0.0.1:9001` | `minio_data` |
| Mailpit SMTP | `127.0.0.1:1025` | `mailpit_data` |
| Mailpit Web | `http://127.0.0.1:8025` | `mailpit_data` |

`minio-init` es un contenedor de una sola ejecución. Configura los buckets, el versionado, la privacidad y la cuenta restringida; es normal que termine con estado `Exited (0)`.

## Levantar únicamente algunos servicios

PostgreSQL y Redis:

```powershell
docker compose up -d postgres redis
```

Mailpit:

```powershell
docker compose up -d mailpit
```

MinIO con su inicialización:

```powershell
docker compose up -d minio-init
```

Detener un servicio concreto:

```powershell
docker compose stop redis
```

## Perfiles opcionales

Herramientas de administración:

```powershell
docker compose --profile tools up -d
```

- pgAdmin: `http://127.0.0.1:5050`
- RedisInsight: `http://127.0.0.1:5540`

Observabilidad:

```powershell
docker compose --profile observability up -d
```

- Grafana: `http://127.0.0.1:3000`
- Alloy OTLP gRPC: `127.0.0.1:4317`
- Alloy OTLP HTTP: `127.0.0.1:4318`
- Prometheus, Loki y Tempo permanecen en la red interna de Compose.

Todos los perfiles:

```powershell
docker compose --profile tools --profile observability up -d
```

## Estado, salud y logs

```powershell
docker compose ps
docker compose ps --all
docker compose logs --tail 200
docker compose logs -f
docker compose logs -f postgres
```

Comprobar PostgreSQL:

```powershell
docker compose exec postgres sh -ec 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\l"'
```

Comprobar Redis autenticado:

```powershell
docker compose exec redis sh -ec 'redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping'
```

Reejecutar y verificar la inicialización de MinIO:

```powershell
docker compose run --rm minio-init
```

Validar Compose sin mostrar los secretos resueltos:

```powershell
docker compose config --quiet
docker compose --profile tools config --quiet
docker compose --profile observability config --quiet
```

## Detención y eliminación

Detener sin eliminar contenedores ni datos:

```powershell
docker compose stop
```

Eliminar contenedores y red, conservando volúmenes:

```powershell
docker compose down
```

Eliminar también todos los datos persistentes del entorno:

```powershell
docker compose --profile tools --profile observability down -v
```

El último comando elimina PostgreSQL, Redis, MinIO, Mailpit y los datos de herramientas y observabilidad.

## Seguridad local

- Todos los puertos publicados usan `127.0.0.1`.
- No se utilizan imágenes `latest`.
- No se monta el socket Docker.
- No hay contenedores privilegiados.
- Las credenciales viven únicamente en `.env`.
- Se aplica rotación de logs y `no-new-privileges`.
- Los buckets MinIO no tienen acceso anónimo.
- Mailpit no retransmite correo a Internet.
