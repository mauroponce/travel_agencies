# NexoViajes

SaaS multiempresa para agencias de turismo argentinas que venden viajes en micro mediante equipos propios y revendedores. Incluye catálogo comercial, salidas con inventario compartido, reservas, pasajeros cifrados, cobros declarados, rendiciones, comisiones, operación de embarque, PWA y notificaciones.

## Requisitos

- Ruby 3.4.1, PostgreSQL 14+ y Redis 7+
- Docker y Docker Compose, como alternativa al entorno Ruby local
- Credenciales OAuth 2.0 de Google para una aplicación web

## Puesta en marcha local

```bash
cp .env.example .env
bin/setup
bin/rails db:seed
bin/dev
```

La aplicación queda en `http://localhost:3000`. Sidekiq se inicia mediante `Procfile.dev`; PostgreSQL y Redis deben estar disponibles según `.env`. El correo local puede apuntar a Mailpit.

Con Docker:

```bash
cp .env.example .env
# completar SECRET_KEY_BASE y ACTIVE_RECORD_ENCRYPTION_KEY
docker compose up --build
```

Web: `http://localhost:3000`; Mailpit: `http://localhost:8025`.

## Autenticación y demo

La autenticación es exclusivamente por Google. Configure `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET`. Si `DEMO_GOOGLE_EMAIL` coincide con la cuenta que ingresa, se le vincula el workspace demostrativo **Sanzó Viajes**, con acceso a los tres perfiles. Los seeders también crean personas ficticias de equipo, viajes a Mendoza, Bariloche, Córdoba y Mar del Plata, paquetes que comparten micro, cobros y rendiciones.

Para generar claves:

```bash
bin/rails secret                         # SECRET_KEY_BASE
bin/rails secret                         # ACTIVE_RECORD_ENCRYPTION_KEY, diferente
bundle exec webpush generate_key         # VAPID
```

No cambie `ACTIVE_RECORD_ENCRYPTION_KEY` después de guardar DNI o endpoints Push: perdería acceso al contenido cifrado.

## Pruebas y calidad

```bash
bin/rails test
npm run test:e2e
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
```

Las pruebas cubren las reglas críticas de cupos, precios, acceso multiempresa, formularios privados, rendiciones y comisiones. Playwright valida los recorridos públicos y autenticados en viewport desktop y móvil. La integración continua está en `.github/workflows/ci.yml`.

## Procesos

- Web: `bundle exec puma -C config/puma.rb`
- Colas: `bundle exec sidekiq -C config/sidekiq.yml`
- Tareas periódicas: `sidekiq-cron` carga `config/sidekiq_schedule.yml`
- Health check: `GET /up`

## Archivos y despliegue

Active Storage usa disco local por defecto y puede cambiarse a cualquier S3 compatible con `ACTIVE_STORAGE_SERVICE=s3`. En producción deben respaldarse PostgreSQL y el volumen `storage_data`, o utilizar almacenamiento S3.

`compose.production.yml`, `deploy/Caddyfile` y `bin/deploy-hetzner` forman el despliegue manual previsto para Hetzner. En el servidor copie el compose, Caddyfile y un `.env` seguro a `/opt/nexoviajes`, autentique el registry y ejecute:

```bash
DEPLOY_HOST=IP_O_HOST \
NEXOVIAJES_IMAGE=ghcr.io/organizacion/nexoviajes:sha \
bin/deploy-hetzner
```

El script construye/publica la imagen, actualiza web y worker, aplica migraciones desde un único contenedor y verifica el arranque. Revise [arquitectura](docs/arquitectura.md), [reglas de negocio](docs/reglas-negocio.md) y [estado de implementación](docs/estado-implementacion.md) antes de operar.
