# Turistack

SaaS multiempresa para agencias de turismo argentinas. Incluye catálogo, salidas e inventario compartido, reservas, pasajeros cifrados, pagos, rendiciones, comisiones, embarque, PWA y notificaciones. El tenant se resuelve por hostname sobre una base PostgreSQL compartida.

## Requisitos

- Ruby 3.4.1, PostgreSQL 14+ y Redis 7+
- Docker y Docker Compose para el flujo en contenedores
- Credenciales OAuth 2.0 de Google para una aplicación web

## Entornos y PostgreSQL

Turistack admite dos estrategias exclusivas de conexión: una `DATABASE_URL` completa o las variables `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD` y `DB_NAME`. Nunca deben mezclarse. Una validación de arranque rechaza combinaciones ambiguas, localhost dentro de Docker y nombres de base incompatibles con el entorno sin incluir contraseñas en el error.

| Entorno | Configuración | Datos |
| --- | --- | --- |
| `development` | `.env.example`; PostgreSQL local o `compose.yml` | desarrollo, volumen `turistack-development` |
| `test` | base terminada en `_test`; puede usar `DATABASE_URL` en CI | descartable |
| `staging` | `deploy/env.staging.example` + `compose.staging.yml` | aislados de producción |
| `production` | `deploy/env.production.example` + `compose.production.yml` | volúmenes propios y backups obligatorios |

`POSTGRES_*` inicializa el contenedor PostgreSQL vacío y Compose deriva de esos mismos valores los `DB_*` de Rails. Cambiar `POSTGRES_USER` o `POSTGRES_DB` no renombra una instalación existente: conserve sus valores actuales y migre nombres solamente mediante un procedimiento explícito respaldado.

## Desarrollo local

Ejecución nativa:

```bash
cp .env.example .env
set -a
. ./.env
set +a
bin/setup
bin/rails db:seed
bin/dev
```

Con Docker:

```bash
cp .env.example .env
# Reemplazar SECRET_KEY_BASE y ACTIVE_RECORD_ENCRYPTION_KEY.
docker compose up --build
```

Compose espera la salud de PostgreSQL y Redis, ejecuta `db:migrate` una sola vez en el servicio `migrate` y luego inicia web y Sidekiq con la misma configuración de base. Los seeds nunca se cargan durante el arranque. Web queda en `http://localhost:3000` y Mailpit en `http://localhost:8025`. Los volúmenes no se recrean durante una actualización normal.

## Autenticación

Google es el único método de autenticación. El callback se registra una sola vez en `AUTH_HOST`; un código efímero devuelve la sesión al hostname original autorizado. Las cookies son host-only, `HttpOnly` y `SameSite=Lax`; staging y producción además fuerzan HTTPS y `Secure`.

`PLATFORM_ADMIN_GOOGLE_EMAILS` controla el panel global. `ACTIVE_RECORD_ENCRYPTION_KEY` debe ser estable y diferente de `SECRET_KEY_BASE`; cambiarla impide descifrar DNI y endpoints Push.

```bash
bin/rails secret
bin/rails secret
bundle exec webpush generate_key
```

## Staging y despliegue

El despliegue manual para Hetzner usa tags de imagen inmutables y requiere indicar explícitamente el entorno:

```bash
DEPLOY_HOST=staging.example.net \
DEPLOY_ENVIRONMENT=staging \
TURISTACK_IMAGE=ghcr.io/organizacion/turistack:git-sha \
bin/deploy-hetzner
```

El script construye y publica la imagen, valida Compose, espera dependencias, ejecuta un único migrador, actualiza web/worker/Caddy y comprueba los procesos. No se conecta ni despliega por sí solo. El alta inicial, staging, dominios, backups, restauración, rollback y checklist productiva están en [docs/despliegue-dominios.md](docs/despliegue-dominios.md).

## Pruebas y calidad

```bash
bin/rails test
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
npm run test:e2e
bin/rails tenant_integrity:audit
git diff --check
```

Los listados administrativos usan orden total (criterio funcional más `id`) para evitar saltos por empates. La paginación por offset sigue pudiendo reflejar inserciones o eliminaciones concurrentes; ese compromiso es intencional para el volumen actual.

## Procesos

- Web: `bundle exec puma -C config/puma.rb`
- Worker: `bundle exec sidekiq -C config/sidekiq.yml`
- Migraciones: servicio Compose `migrate`, nunca desde web/worker
- Health check: `GET /up`
- Integridad: `bin/rails tenant_integrity:audit` y `bin/rails company_domains:audit`

La arquitectura funcional se documenta en [docs/arquitectura.md](docs/arquitectura.md) y [docs/reglas-negocio.md](docs/reglas-negocio.md).
