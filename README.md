# Turistack

Turistack Pro organiza el negocio de un asesor de viajes independiente: proveedores privados, importaciones revisadas, viajes, web personal, enlaces a WhatsApp y clientes con notas privadas. Cuesta USD 19 por mes, con activación y renovación manual, sin débito automático.

La operación anterior de agencias (salidas, inventario, reservas, pasajeros, pagos y rendiciones) conserva sus rutas, tablas y permisos. Es un producto separado de Pro. Se utiliza PostgreSQL compartido con aislamiento por empresa o espacio personal, según el módulo.

## Requisitos

- Ruby 3.4.12, PostgreSQL 14+ y Redis 7+
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
bin/rails agent:audit
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

## Turistack Pro

Con `AGENT_ENABLED=true`, una persona entra con Google desde `/agente/alta`, configura su nombre/marca, WhatsApp y slug y obtiene una única prueba de 14 días. El alta autónoma funciona también en staging/producción después de finalizar la integridad de hosts existente. Reintentar onboarding o ingresar nuevamente no reinicia la prueba. La invitación manual por operador sigue disponible.

URLs canónicas: `https://PLATFORM_HOST/:agent_slug` y `/:agent_slug/viajes/:slug`. El panel sigue en `/agente`. Se conservan los hosts antiguos de asesores; no se exige subdominio ni dominio propio. Google usa el callback único en `AUTH_HOST`. Las cookies siguen limitadas a cada host.

El login general del dominio principal permite abrir `/context` y ver **Mi espacio** y **Empresas que me dan acceso**. Tener varias membresías no requiere Pro. Cada host empresarial valida su propia sesión; si aún no existe, se ingresa con Google usando el intercambio efímero existente. Cancelar o vencer Pro nunca elimina la identidad ni modifica membresías.

**Mi plan** muestra precio, vencimiento, unidades mensuales y solicitud de activación manual. Un operador autorizado en `PLATFORM_ADMIN_GOOGLE_EMAILS` activa o renueva un mes desde `/platform/agent_workspaces`. No hay cobro ni débito automático. `AgentSubscription` es la fuente de permisos comerciales; la columna histórica `AgentWorkspace.plan` se ignora y se conserva solo para compatibilidad de rollback.

Al vencer se conservan viajes, archivos, revisiones, clientes y notas. El dueño puede leer y exportar en privado (`/agente/export.json` y CSV de contactos/notas), solicitar reactivación y acceder a sus empresas. Se bloquean escrituras comerciales y jobs de IA; web, búsquedas e imágenes públicas responden 404. Reactivar restaura la última revisión publicada, sin publicar borradores. La suspensión administrativa sigue siendo independiente y bloquea el espacio.

La IA conserva Gemini y su modelo configurado, idempotencia, límites diarios/por minuto y concurrencia. El presupuesto inicial es **200 unidades por mes calendario de la zona del espacio**, sin acumulación: una búsqueda o una imagen cuesta una unidad por intento; un PDF cuesta una por página por intento. Errores del proveedor y reintentos consumen; una repetición idempotente sin ejecución adicional no consume. Los límites se comprueban bajo el lock del espacio al reservar `AgentAiExecution`. Máximo inicial: 10 MB, 10 páginas de PDF, 50 fichas por extracción. La IA no publica y no recibe clientes ni notas. Con cuota agotada y Pro vigente siguen funcionando la carga y los filtros manuales.

Para desarrollo, conservar el `.env` existente y completar `GEMINI_API_KEY` y el modelo actual `GEMINI_MODEL=gemini-3.5-flash-lite`. Web y worker usan la misma configuración. Para comandos aislados, cargar el entorno previamente; no versionar secretos. Redis/Sidekiq procesa los jobs. Los tests simulan OAuth/Gemini sin llamadas facturables.

Variables nuevas, transición finita del piloto, activación manual, actualización y reversión: [guía de lanzamiento](docs/turistack-revendedor-lanzamiento.md). Contrato breve para futuras tareas: [alcance de Pro](docs/turistack-pro-alcance.md).

Playwright crea una base nueva `turistack_e2e_<marca-de-tiempo>_test` con `db:prepare db:seed`, exclusivamente local/test; no resetea bases existentes. `E2E_DB_NAME` permite elegir una base de prueba vacía. `E2E_PORT=3101 npm run test:e2e` usa otro puerto. Los fixtures HTTP y jobs simulados se activan solo con `AGENT_E2E_FIXTURES=true` en test. Las pruebas de escritorio y Pixel 7 incluyen alta → proveedor → viaje → publicación → enlace WhatsApp → cliente → nota. No prueban el selector nativo ni el envío real de WhatsApp.
