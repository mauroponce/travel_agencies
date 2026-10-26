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

Compose construye una imagen con las gemas de desarrollo para web, worker y migrador, y permite que el usuario `rails` actualice `db/schema.rb` al migrar; los builds de staging/producción siguen excluyendo `development:test`. Después de cambios al Dockerfile o las dependencias, usar `docker compose up --build` para reconstruir la imagen.

Compose espera la salud de PostgreSQL y Redis, ejecuta `db:migrate` una sola vez en el servicio `migrate` y luego inicia web y Sidekiq con la misma configuración de base. Los seeds nunca se cargan durante el arranque. Con el dominio local predeterminado, la plataforma se abre en `http://platform.lvh.me:3000` y los tenants en sus subdominios; `http://localhost:3000/up` verifica la salud. Compose habilita el dominio de desarrollo en la protección de hosts de Rails. Mailpit queda en en `http://localhost:8025`. Los volúmenes no se recrean durante una actualización normal.

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

## Turistack Revendedor

Piloto controlado para revendedores independientes. Incluye proveedores privados, catálogo versionado, importación de varias fichas por imagen/PDF con Gemini, comparador, sitio público y buscador privado. No incluye cobros de suscripción, reservas autónomas, sincronización con proveedores ni automatización de WhatsApp.

Para desarrollo, conservar el `.env` existente y completar `GEMINI_API_KEY` y `GEMINI_MODEL=gemini-3.5-flash-lite`; la clave real nunca va en `.env.example`. `bin/dev` carga `.env` mediante Foreman. Para comandos Rails aislados, cargar previamente las variables del archivo. Arrancar también Redis/Sidekiq para procesar IA; las pruebas usan respuestas simuladas y no necesitan una clave real.

Para desarrollo/test, después de `bin/rails db:migrate`, abrir `http://platform.lvh.me:3000/agente/alta`, ingresar con Google y elegir un subdominio. Iniciar sesión desde ese subdominio para entrar al panel. El callback local único sigue siendo `http://auth.lvh.me:3000/auth/google_oauth2/callback`. `bin/rails db:seed` agrega agentes de demostración solo en desarrollo/test; no crea datos de agente en staging/producción.

En staging/producción el operador crea la cuenta desde **Revendedores** e invita el correo verificado por Google; el alta autónoma se limita a development/test.

Configuración: `AGENT_ENABLED`, `GEMINI_API_KEY`, `GEMINI_MODEL`, `AGENT_IMPORTS_PER_MINUTE=5`, `AGENT_SEARCHES_PER_MINUTE=20` y `AGENT_AI_CONCURRENCY=2`. El piloto no tiene cuota mensual de IA. Los documentos admitidos son JPG/PNG/WebP/PDF de hasta 10 MB, con hasta 100 páginas por PDF y 50 candidatos por extracción. Un error de Gemini permite carga o búsqueda manual. Los límites de ráfaga y concurrencia son por espacio.

La producción queda preparada para **turistack.com**, con `auth.turistack.com`, redirección de `www` y subdominios de agentes. Ver el [procedimiento DNS y de activación](docs/despliegue-dominios.md#producción-turistackcom), incluida la finalización de hosts antes de habilitar Agente. Falta configurar el servidor Hetzner y los servicios externos; los archivos de ejemplo no contienen credenciales reales.

Verificación adicional: `bin/rails agent:audit`. Los recorridos Playwright usan `AGENT_E2E_FIXTURES=true` exclusivamente en test, con el cliente HTTP y los jobs reales pero respuestas Gemini simuladas. `E2E_PORT=3101 npm run test:e2e` permite usar otro puerto sin reutilizar servidores ajenos.

## Turistack Revendedor MVP

El piloto incorpora alta desde el operador con invitación Google, proveedores privados, fichas manuales o desde Gemini, conservación del flyer/PDF original, catálogo público y compartir archivo con enlace y alternativas manuales. Procedimiento de staging, variables, migraciones, seguridad, rollback y pruebas Android/iOS: [guía de lanzamiento](docs/turistack-revendedor-lanzamiento.md).
