# Turistack Asesor: hardening y evidencia para el piloto

Fecha: 25/10/2026 (Argentina). Base: `dbd0f0199032a65d3fcf583c0a3f35b40aebb6d7`. Rama: `fix/reseller-launch-hardening`.

Complementa [el recorrido del MVP](turistack-revendedor-lanzamiento.md) y [el runbook de dominios](despliegue-dominios.md). No acredita un despliegue remoto ni una aprobación para producción.

## Problemas confirmados y correcciones

- **CI:** el primer curl se ejecutaba apenas Compose iniciaba web, antes de readiness de Puma. El run `40253913760` falló con error 56, no cubierto por `--retry-connrefused`; sus logs todavía no mostraban Puma atendiendo. Ahora `up --wait --wait-timeout 180` espera `/up`, PostgreSQL, Redis y el heartbeat del worker. Curl reintenta errores transitorios con plazos acotados. En fallo se muestran estado y logs. Required checks sigue exigiendo los cinco jobs. CI también corre con pushes de ramas para verificar cambios antes de abrir un PR.
- **Worker:** ejecutar otro proceso Ruby no demostraba que Sidekiq funcionara. Su healthcheck exige el heartbeat reciente del hostname de ese contenedor. Despliegue y restauración esperan web y worker. `agent:operations` comprueba BD, migraciones, Redis y Sidekiq.
- **IA:** reiniciar manualmente los intentos permitía consumo indefinido. `Agent::AiRequests` limita solicitudes nuevas y ejecuciones diarias; el job reserva cada ejecución dentro del bloqueo del workspace. Reintentos automáticos, manuales y recuperaciones consumen el mismo presupuesto. Un replay conserva identidad. Se registran tokens informados también si falla el contrato o la salida se trunca, sin registrar cuerpos comerciales ni claves.
- **Errores:** importes/archivos inválidos, nombres duplicados y conflictos devolvían texto plano. Los formularios prioritarios conservan campos, precio original, correcciones y flyer validado, y presentan errores Cadence editables. Un conflicto mantiene el token de revisión anterior para impedir sobrescribir otra edición. Publicar una ficha incompleta lleva a su formulario. La identidad comercial también conserva el formulario ante errores.
- **Archivo conservado:** blob validado con token firmado, ligado al workspace y válido durante 48 horas. No tiene ruta pública de Active Storage. Otro workspace recibe 404. La corrección posterior adjunta el mismo blob o lo reemplaza. Una importación limitada puede continuar manualmente con su flyer. El token se filtra de los logs de parámetros.
- **Compartir:** se conserva la precarga y el archivo original. Se impiden solicitudes nativas simultáneas y archivos vacíos, y se comprueba también archivo + texto antes de invocar el selector. Cancelar permite repetir. El texto contiene el enlace incluso si se omite el atributo `url`.
- **Backup:** dump y tar tomados con escrituras activas podían discrepar. Ahora se detienen brevemente web/worker, se verifican dump, compresión y checksums, y se reanudan solo los servicios originalmente activos. Las copias incompletas quedan identificadas. Restaurar reemplaza los archivos locales y espera healthchecks. Ambos scripts rechazan S3 para evitar una falsa garantía de respaldo.

No se sustituyeron modelos del MVP ni se agregaron migraciones. Revisiones y slugs conservan su contrato.

## Gemini real opt-in

La [ficha oficial](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite) confirma imágenes, PDF y JSON estructurado. Se conserva `generateContent`, `inlineData`, `responseMimeType` y `responseJsonSchema`; ver [JSON estructurado](https://ai.google.dev/gemini-api/docs/generate-content/structured-output) y [PDF](https://ai.google.dev/gemini-api/docs/document-processing). Eso no acredita acceso/cuota de una cuenta ni la exactitud de una extracción concreta.

`bin/gemini-smoke` requiere **ambas** variables `AGENT_GEMINI_SMOKE=true` y `GEMINI_SMOKE_API_KEY`, exclusivamente en test. Nunca usa automáticamente la clave de la aplicación. Queda fuera de `*_test.rb` y del CI normal, no escribe viajes/workspaces y no reintenta automáticamente. Genera datos sintéticos con Prawn/Poppler y hace cinco solicitudes potencialmente pagas: JPG, PNG, PDF de una página, PDF con dos páginas/dos viajes y PDF ambiguo. Comprueba importes argentinos, fecha explícita, año ausente, moneda/unidad, hotel ausente y advertencias; falla ante información inventada en esos campos. Informa modelo, contrato y tokens, sin cuerpos ni claves.

```bash
# Configurar DB_* solo para una base de test descartable.
# Cargar GEMINI_SMOKE_API_KEY desde el gestor de secretos, sin pegarla en el historial.
RAILS_ENV=test AGENT_GEMINI_SMOKE=true bin/gemini-smoke
```

Requiere `pdftoppm`. Guardar el resultado de las cinco comprobaciones y revisar un flyer comercial autorizado real antes de habilitar IA para pilotos.

## Smoke reproducible de staging

`bin/smoke-staging` construye la imagen de despliegue y crea un proyecto Compose con nombre aleatorio, base, volúmenes y credenciales sintéticas. No admite seleccionar un despliegue existente. Se ejecuta también en CI. Usa un modelo inválido deliberadamente para impedir llamadas a Gemini.

Comprueba migraciones desde el historial anterior a Asesor con una agencia/destino ya cargados, finalización de hosts, convivencia, worker real procesando un PDF, publicación manual con fallback, HTML público y canonical/og:image HTTPS, descarga anónima de JPEG, persistencia tras reiniciar web/worker y backup/restauración de BD/archivos. Al terminar elimina exclusivamente su proyecto y volúmenes descartables. No emite certificados ACME ni prueba OAuth/SMTP externos.

```bash
bin/smoke-staging
```

Rails 8.1 carga automáticamente el último schema en una BD nueva al ejecutar db:migrate. Para reconstruir la versión anterior, el smoke usa MigrationContext directamente; no intenta bajar una BD nueva que ya cargó el schema finalizado. Un ensayo descartable confirmó que el rollback pre-MVP tras `agent:finalize_hosts` está bloqueado por el FK `fk_company_domain_registered_host` y puede además encontrar propietarios invitados sin asignar. No usar CASCADE ni borrar datos para sortearlo; conservar la BD y corregir hacia adelante o restaurar una copia aprobada.

## Variables y operación

- `AGENT_IMPORTS_PER_DAY=25`, `AGENT_SEARCHES_PER_DAY=100`: por workspace, día calendario en su zona horaria. Cada intento consume una unidad aunque falle. Las solicitudes nuevas también se limitan para evitar una cola ilimitada. Los reintentos pueden agotar el cupo antes de completar ese número de documentos. El acceso manual sigue disponible.
- Se mantienen los límites por minuto/concurrencia, `GEMINI_MODEL`, `GEMINI_API_KEY` y `AGENT_ENABLED`.
- Completar `deploy/env.staging.example`: PostgreSQL/Redis, `SECRET_KEY_BASE`, `ACTIVE_RECORD_ENCRYPTION_KEY`, Google OAuth, SMTP, hosts, `CADDY_ASK_SECRET` (mínimo 32 caracteres), almacenamiento y tag inmutable. Usar claves/volúmenes exclusivos de staging.
- `agent:operations` es de solo lectura: dependencias, colas, reintentos/dead jobs, fallos IA y tokens reportados en 24 h. Sale con error ante dependencias caídas, migraciones pendientes, tareas de cuentas activas trabadas más de diez minutos o dead jobs. Los tokens son consumo aproximado: si no se reportan, no se puede calcular un costo exacto.

Ejemplos de cron en el servidor, después de configurar archivos, permisos y un canal de alertas:

```cron
*/5 * * * * cd /opt/turistack-staging && ENV_FILE=.env.staging docker compose --env-file .env.staging -f compose.staging.yml exec -T web bin/rails agent:operations >> /var/log/turistack-staging-health.log 2>&1
0 4 * * * cd /opt/turistack-staging && DEPLOY_ENVIRONMENT=staging ENV_FILE=.env.staging BACKUP_ROOT=/srv/backups/turistack bin/backup-turistack >> /var/log/turistack-staging-backup.log 2>&1
```

Configurar entrega de errores y rotación de logs; no se instala cron automáticamente. Vigilar espacio libre, último backup completo (<26 h), Sidekiq y cola muerta. Copiar backups fuera del servidor, cifrados, y ensayar restauraciones periódicas. Conservar por separado en un gestor de secretos `SECRET_KEY_BASE`, `ACTIVE_RECORD_ENCRYPTION_KEY` y `RAILS_MASTER_KEY` si se usa; restaurar datos cifrados exige los mismos valores. Para S3, implementar y verificar versionado/replicación y recuperación en un bucket aislado antes de cambiar el servicio.

## Staging externo: comandos

Ejecutar **después de autorizar la intervención remota**, dentro del checkout del servidor con `.env.staging` completo y Compose/Caddy/scripts del mismo commit. No se ejecutaron sobre infraestructura remota.

```bash
export ENV_FILE=.env.staging
export TURISTACK_IMAGE=ghcr.io/mauroponce/travel_agencies:SHA_VALIDADO
stage=(docker compose --env-file "$ENV_FILE" -f compose.staging.yml)
"${stage[@]}" config --quiet
"${stage[@]}" pull
"${stage[@]}" run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
# Solo en instalación existente: guardar backup y claves con la versión vigente.
DEPLOY_ENVIRONMENT=staging BACKUP_ROOT=/srv/backups/turistack bin/backup-turistack
"${stage[@]}" up -d --wait --wait-timeout 120 db redis
"${stage[@]}" run --rm migrate
"${stage[@]}" up -d --no-deps --wait --wait-timeout 180 web worker
# Solo al reemplazar TODOS los web/worker por código registry-aware.
"${stage[@]}" exec -T web bin/rails agent:finalize_hosts
"${stage[@]}" exec -T web bin/rails tenant_integrity:audit agent:audit agent:operations
"${stage[@]}" up -d --no-deps caddy
"${stage[@]}" ps --all
curl --fail --connect-timeout 5 --max-time 20 https://HOST_STAGING/up
```

Instalación limpia: omitir el backup previo, no cargar seeds demo. Instalación de agencias: conservar BD, volúmenes, claves y datos; finalizar hosts solo después de retirar procesos anteriores. Ante un fallo, recoger `ps --all` y `logs --tail=150`; no seguir habilitando asesores. `bin/deploy-hetzner` aplica esta secuencia para un stack en un host, además de construir/subir imagen.

Conservar tag previo y backup. No hacer `db:rollback` automático: no hay migraciones nuevas en este hardening, pero revertir migraciones originales del MVP elimina campos/tablas de Asesor. Con datos reales, preferir corregir hacia adelante. Restaurar una copia anterior pierde datos posteriores a esa copia y requiere ventana y autorización explícitas.

## DNS, OAuth y previews externas

- A/AAAA de plataforma/autenticación y wildcard de asesores. `*.turistack.com` no cubre el apex; publicar AAAA solo si IPv6 llega al mismo proxy. Puertos 80/443 disponibles.
- `CADDY_SITE_ADDRESSES` incluye plataforma, autenticación y hosts de agencias existentes. TLS bajo demanda para asesores autoriza solo hosts registrados activos con secreto correcto. Bloquear `/internal/*` desde el proxy. Conservar `caddy_data` y salida ACME para emisión/renovación. Probar host desconocido y cuenta suspendida.
- Callback Google exacto: `https://AUTH_HOST/auth/google_oauth2/callback`. Invitar una casilla real autorizada, comprobar correo verificado y regreso al subdominio. Probar cuenta ajena, identidad distinta con mismo email y callback repetido. Cookies Secure, HttpOnly, SameSite=Lax, sin Domain.
- Catálogo/ficha sin sesión: título, precio, organizador, WhatsApp del asesor, consulta con URL. Obtener `og:image` sin cookies y comprobar bytes. Solo la revisión publicada es accesible; antigua/privada devuelven 404 tras nueva publicación. Despublicar revoca ficha e imagen. Canonical HTTPS absoluto y sin notas privadas.
- WhatsApp puede retener previews ya descargadas. El servidor revoca rutas y emite `no-store`; no puede borrar copias de terceros. Registrar resultado real del crawler y de WhatsApp.

## Matriz manual WhatsApp

Pendiente en dispositivos reales. Registrar fecha, versiones de SO/navegador/WhatsApp, flyer, URL y resultado. Usar HTTPS válido y staging autorizado.

| Caso | Chrome/Android | Safari/iPhone | Resultado requerido |
| --- | --- | --- | --- |
| JPG, PNG, WebP | Pendiente por formato | Pendiente por formato | Imagen correcta o alternativas si el sistema no admite formato |
| PDF de una/varias páginas | Pendiente | Pendiente | JPEG de primera página; original privado intacto |
| Toque durante preparación | Pendiente | Pendiente | Botón ocupado hasta terminar; descarga/copia disponibles |
| Compartir a conversación | Pendiente | Pendiente | Selector, imagen y enlace; verificar lo que recibe WhatsApp |
| Compartir a Mi estado | Pendiente | Pendiente | Selección por la persona; pegar texto/enlace si hace falta |
| Cancelar y repetir | Pendiente | Pendiente | Mensaje y segundo intento funcional |
| Permisos/combinación rechazada | Pendiente | Pendiente | Error claro y alternativas disponibles |
| Sin Web Share / contexto inseguro | Pendiente | Pendiente | Alternativas; nunca anunciar publicación |
| Portapapeles bloqueado | Pendiente | Pendiente | Texto seleccionable para copiar |
| Descarga y consulta pública | Pendiente | Pendiente | Imagen correcta; wa.me consulta al asesor con URL |
| Preview tras revisión/despublicar | Pendiente | Pendiente | Solo revisión publicada; registrar caché del tercero |

`wa.me` no adjunta archivos. El selector no confirma la publicación de un Estado. Las pruebas automatizadas simulan esas APIs y no sustituyen esta matriz.

## Protección de main

Ruleset activo dirigido a `main`: PR obligatorio, una aprobación independiente, conversaciones resueltas, rama actualizada, check **Required checks** obligatorio emitido por GitHub Actions, prohibir force push/borrado y sin bypass rutinario. No se modificó la política. Requiere autorización del administrador y comprobar que CI fallando impide integrar.

## Resultados y decisión

| Comprobación | Resultado observado |
| --- | --- |
| `bin/rails test` | Local: 169 tests, 1053 aserciones, 0 fallos/errores/omisiones; confirmado también en CI |
| `bin/rails zeitwerk:check` | Correcto local y CI |
| `bin/rubocop` | 226 archivos, sin infracciones |
| `bin/brakeman --no-pager` | 0 errores, 0 advertencias; local y CI |
| `bin/bundler-audit` | Sin vulnerabilidades |
| `bin/importmap audit` | Sin paquetes vulnerables |
| `bin/rails tenant_integrity:audit` | Correcto local y CI |
| `bin/rails agent:audit` | Correcto local y CI |
| `git diff --check` | Correcto |
| Caddy 2.10-alpine | Sintaxis validada local y CI |
| Docker development boot | Readiness corregido, aprobado en GitHub |
| `npm run test:e2e` | 26 recorridos aprobados en GitHub (escritorio y móvil Chromium; Gemini/Web Share simulados) |
| `bin/smoke-staging` | Aprobado en GitHub: upgrade de agencia anterior, PDF/worker, metadata HTTPS, persistencia y backup/restauración real de datos sintéticos |
| Required checks | Aprobado junto a los cinco jobs en [run 40259243275](https://github.com/mauroponce/travel_agencies/actions/runs/40259243275), SHA `0b006e6` |
| Gemini real | No ejecutado: falta GEMINI_SMOKE_API_KEY. El guard opt-in devuelve 64 y no usa la clave de la aplicación |
| Dominio público solicitado | curl devuelve error 6: no resuelve silvinamartinez.turistack.com; ficha/crawler remotos pendientes |

Se usaron DB_* explícitos hacia PostgreSQL descartable, sin ejecutar tests contra la base de desarrollo. La primera corrida local de Rails tuvo tres fallos por haber heredado el puerto/dominio de desarrollo; se corrigió el entorno de pruebas y la suite completa pasó. Playwright local agotó el arranque de su BD por espera de checkpoint/IO; un segundo stack descartable no llegó a crearse y devolvió conexión rechazada. El build local de staging falló con BuildKit `lease does not exist`; esas ejecuciones no se cuentan como aprobadas. La evidencia de contenedores y navegador en GitHub se registra separadamente.

El conector de GitHub rechazó crear el PR con HTTP 403. La rama sí se publicó por SSH; puede abrirse el PR desde la comparación de ramas. Main sigue sin protección, verificado por la API; no se modificó su política. CI/local verde no acredita DNS, SMTP, OAuth, Gemini real ni WhatsApp móvil.

Go/No-Go del piloto: **No-Go hasta completar las comprobaciones externas obligatorias**.

- [x] Workflow completo verde sobre el código verificado; comprobar también el SHA final de la rama antes de integrar.
- [ ] Staging real, DNS/HTTPS y rechazo de hosts desconocidos.
- [ ] Invitación SMTP/Google real, regreso y aislamiento de dos cuentas.
- [ ] Cinco smoke checks de Gemini y flyer comercial autorizado.
- [ ] WhatsApp real Android/iPhone.
- [ ] Backup fuera del host, claves persistentes y restauración ensayada.
- [ ] Alertas y responsable operativo.
- [ ] Protección de main por administrador autorizado.

## Archivos modificados

Sin migraciones nuevas. Inventario de esta rama frente a `dbd0f019`:

```text
.env.example
.github/workflows/ci.yml
app/controllers/agent/base_controller.rb
app/controllers/agent/import_items_controller.rb
app/controllers/agent/imports_controller.rb
app/controllers/agent/searches_controller.rb
app/controllers/agent/trips_controller.rb
app/controllers/agent/website_controller.rb
app/helpers/agent_helper.rb
app/javascript/controllers/flyer_share_controller.js
app/jobs/agent_ai_job.rb
app/services/agent/ai_requests.rb
app/services/agent/flyer.rb
app/services/agent/gemini_client.rb
app/views/agent/error.html.erb
app/views/agent/import_items/edit.html.erb
app/views/agent/imports/index.html.erb
app/views/agent/searches/index.html.erb
app/views/agent/trips/_form.html.erb
app/views/agent/website/show.html.erb
bin/backup-turistack
bin/deploy-hetzner
bin/gemini-smoke
bin/restore-turistack
bin/smoke-staging
bin/worker-healthcheck
compose.production.yml
compose.staging.yml
compose.yml
config/initializers/filter_parameter_logging.rb
deploy/env.production.example
deploy/env.staging.example
docs/despliegue-dominios.md
docs/turistack-revendedor-hardening.md
docs/turistack-revendedor-lanzamiento.md
lib/tasks/agent.rake
playwright.config.js
test/e2e/reseller.spec.js
test/fixtures/files/agent.jpg
test/fixtures/files/agent.pdf
test/fixtures/files/agent.webp
test/integration/reseller_hardening_test.rb
test/models/agent_ai_budget_concurrency_test.rb
test/models/agent_ai_budget_test.rb
test/smoke/gemini_live.rb
test/smoke/staging_legacy_seed.rb
test/smoke/staging_seed.rb
test/smoke/staging_verify.rb
```

## Riesgos restantes por severidad

- **Alta:** faltan staging externo equivalente, DNS/HTTPS del dominio solicitado, invitación SMTP/Google real y acceso/cuota/contrato de Gemini con la credencial de pruebas. El piloto comercial no está habilitado por esta entrega.
- **Alta si se usa S3:** los scripts verifican almacenamiento local; S3 exige su propio versionado, recuperación y ensayo antes de habilitarlo.
- **Media:** matriz de WhatsApp real, incluyendo iOS/Android y su caché de previews; las simulaciones no prueban el destino nativo.
- **Media:** main sin protección y revisión independiente pendiente. Hay configuración concreta recomendada; el administrador debe autorizar su aplicación.
- **Media:** backups locales requieren una ventana breve sin web/worker, copia cifrada fuera del host y claves recuperables. Debe comprobarse la recuperación en el servidor real.
- **Baja:** los uploads conservados que se abandonan pueden quedar sin adjuntar. Para mantenimiento, revisar blobs no adjuntos de más de tres días y purgarlos solo después de vencer los tokens de 48 h; no purgar blobs adjuntos a revisiones/importaciones.

Para revisar e integrar: [comparar main con la rama de hardening](https://github.com/mauroponce/travel_agencies/compare/main...fix/reseller-launch-hardening?expand=1). No se creó PR por el 403 del conector. Verificar los checks del último SHA y realizar revisión independiente antes de integrar.
