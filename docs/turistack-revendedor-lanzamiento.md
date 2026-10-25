# Turistack Revendedor: piloto y lanzamiento

## Producto y arquitectura

El recorrido es: operador crea una cuenta → invitación por correo → Google verifica el correo invitado → proveedor → carga manual o flyer → revisión humana → publicación → ficha pública → compartir archivo y enlace.

Se reutiliza `AgentWorkspace`, ya presente en el árbol de trabajo, como tenant del revendedor. `Company` conserva la operación de agencias. Proveedores son `AgentSupplier` privados de un espacio, nunca tenants. La tabla `hostname_registrations` comparte la reserva de hosts entre ambos productos, y `TenantResolver` resuelve el propietario. Se conserva el contrato existente de OAuth, dominios propios, inventario y reservas de agencias. Los nombres internos `Agent*` y `AGENT_*` se conservan para evitar una migración de identidad innecesaria.

En staging/producción el piloto se provisiona desde `/platform/agent_workspaces`, accesible desde **Revendedores** en el panel del operador. El alta autónoma queda disponible únicamente en development/test. El operador completa nombre comercial/público, subdominio, WhatsApp y correo de Google. No se crean usuarios con identidades ficticias: el propietario se asigna al confirmar ese correo con Google. El WhatsApp de demostración del formulario es `+541160347665`; debe sustituirse por el número real del revendedor.

Un viaje tiene revisiones inmutables y un slug permanente. Editar un borrador conserva la versión pública anterior hasta publicar la nueva revisión. Solo se publican datos revisados; IA nunca publica. Un título omitido se completa con el destino informado por la persona. ARS y precio por persona son las opciones iniciales de carga manual; una extracción ambigua conserva `null` para revisión. No hay inventario ni cupos supuestos. Viajes vencidos, proveedores pausados y cuentas suspendidas se ocultan del catálogo.

## Archivos, extracción y privacidad

- JPG/JPEG, PNG, WebP y PDF: hasta 10 MB; validación MIME y firma, PDF sin cifrado/corrupción y hasta 100 páginas. Gemini recibe el documento completo y puede devolver hasta 50 candidatos. Salida limitada a 16000 tokens; hasta tres intentos automáticos por fallos transitorios. Timeout HTTP de conexión 10 s, lectura 60 s y escritura 30 s. Límites de ráfaga y concurrencia por cuenta.
- `AgentImport.source` conserva el archivo recibido; `preview` conserva su imagen compartible. Al confirmar, `AgentTripRevision.flyer_source` y `cover` mantienen la relación con esos blobs. Para imágenes se reutiliza exactamente el mismo blob y los mismos bytes. No hay rediseño, sobreimpresión ni marca de agua.
- Para PDF se conserva el documento original privado y se crea un JPEG de la primera página, máximo 1600 px, mediante Poppler (`pdftoppm`). La extracción sigue incluyendo todas las páginas admitidas. Un documento de varios viajes puede requerir que la persona suba un flyer específico para cada ficha; la imagen compartida representa la primera página del documento.
- Poppler está instalado en la etapa base de Docker. Se ejecuta sin shell, sin usar el nombre aportado por el usuario, con directorio temporal, límites de CPU/memoria/tamaño y timeout de 15 s. No procesa enlaces externos ni ejecuta instrucciones del documento.
- El cliente Gemini y la validación JSON están desacoplados (`Agent::GeminiClient`, `Agent::AiContract`). Solo se aceptan los campos comerciales del contrato; IDs de tenant/permisos no forman parte de la respuesta admitida. No se envían reservas, pasajeros ni notas privadas de proveedores.
- Las rutas globales de Active Storage permanecen desactivadas. El original solo se descarga desde rutas privadas autorizadas. La imagen pública se sirve por una ruta estable que vuelve a comprobar tenant, publicación y revisión; al despublicar devuelve 404. No hay enlaces firmados de descarga que venzan. Una copia ya descargada o almacenada por terceros no puede revocarse desde Turistack.
- Si Gemini falla o no tiene credenciales, **Cargar viaje manualmente** conserva el archivo recibido. Los códigos de error y estados se guardan sin almacenar respuestas HTTP sensibles ni claves.

Gemini utiliza JSON estructurado ([documentación oficial](https://ai.google.dev/gemini-api/docs/generate-content/structured-output)). La selección final del modelo depende de su disponibilidad en la cuenta y región. La configuración inicial conserva `gemini-3.5-flash-lite`; no se hicieron llamadas pagas con credenciales reales.

## Compartir y prueba manual obligatoria

**Compartir flyer en WhatsApp** prepara un `File` desde los bytes descargados de una ruta privada. La descarga anticipada evita perder la activación del toque antes de abrir `navigator.share`. Se comprueba HTTPS, disponibilidad de `navigator.canShare`, compatibilidad de archivo y tipo MIME. Se intenta compartir archivo, texto y URL; cuando la comprobación lo requiere se omite el campo URL porque el texto ya contiene el enlace.

La API abre el selector del sistema; la persona elige WhatsApp y, si corresponde, **Mi estado**. No existe confirmación de publicación de un Estado. El destino puede omitir texto, URL o combinaciones de contenido. La interfaz nunca anuncia que publicó nada. Siempre ofrece **Descargar flyer**, **Copiar enlace** y **Copiar texto para estado**, con selección manual del texto si el portapapeles no está disponible. Cancelaciones y errores conservan esas alternativas. `wa.me` solo se usa para contactar al revendedor, incluyendo nombre y URL del viaje.

Ver [Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API) y [activación de usuario en WebKit](https://webkit.org/blog/13862/the-user-activation-api/).

Antes de producción, registrar resultados reales con fecha, versión de OS, navegador y WhatsApp:

1. Android con Chrome sobre HTTPS: cargar JPG recibido de WhatsApp, importar, revisar, publicar y abrir la ficha sin sesión.
2. Compartir → WhatsApp → conversación y luego Mi estado. Verificar que sea el flyer original; comprobar por separado si llegaron texto y enlace. No interpretar el cierre del selector como publicación.
3. Safari en iPhone: repetir, incluida cancelación, segundo intento y destino que omita el texto. Copiar/pegar el enlace manualmente.
4. PDF de varias páginas: verificar vista previa de primera página, descarga del original intacto y JPEG compartido. Repetir con PNG y WebP; si el destino rechaza WebP, descargarlo y comprobar el comportamiento del teléfono.
5. Navegador sin compartir archivos y portapapeles denegado: descargar, seleccionar/copiar texto y publicar manualmente.
6. Despublicar y suspender la cuenta: fichas e imágenes deben responder 404; otro revendedor no puede acceder a originales ni modificar datos.

Playwright cubre escritorio y viewport móvil, Gemini simulado, bytes del archivo, descarga, texto/enlace, cancelación, errores y fallbacks. El selector del sistema, HTTPS del staging y WhatsApp real no quedan demostrados por esos mocks.

## Migraciones y preflight

La base preparada incluye `20261025120000` (espacios, proveedores, viajes, importaciones, registro de hosts y contexto OAuth), `20261025121000` (revisión humana), `20261025122000` (unaccent) y `20261025123000` (integridad adicional). Esta entrega agrega **`20261025130000_complete_reseller_catalog.rb`**: sitio/notas privadas de proveedores, índice único de nombre por cuenta, descripción/noches y restricciones de duración/moneda, correo invitado y propietario diferido.

Antes de migrar una instalación que ya probó Agente, comprobar duplicados. La migración aborta si encuentra nombres repetidos; no fusiona ni borra datos automáticamente:

```sql
SELECT agent_workspace_id, lower(btrim(name)), count(*)
FROM agent_suppliers GROUP BY 1, 2 HAVING count(*) > 1;
SELECT id FROM agent_trip_revisions
WHERE duration_days <= 0 OR currency NOT IN ('', 'ARS', 'USD', 'EUR', 'BRL');
```

Resolver los nombres con el dueño del catálogo, preservando sus relaciones. Si se parte de la versión de agencias y las tablas `agent_*` aún no existen, estas consultas no aplican hasta las migraciones iniciales. PostgreSQL debe permitir la extensión `unaccent`.

## Variables y servicios

| Configuración | Uso |
| --- | --- |
| `GEMINI_API_KEY` | Secreto de servidor, misma configuración en web/worker; no incluirlo en imagen ni Git. Sin clave, carga manual. |
| `GEMINI_MODEL` | Modelo Flash-Lite habilitado en la cuenta; inicial `gemini-3.5-flash-lite`. |
| `AGENT_ENABLED` | `false` durante migración/primera actualización, `true` después de finalizar registro de hosts. |
| `AGENT_IMPORTS_PER_MINUTE` | Predeterminado 5 por cuenta. |
| `AGENT_SEARCHES_PER_MINUTE` | Predeterminado 20, para el buscador ya existente. |
| `AGENT_AI_CONCURRENCY` | Predeterminado 2 por cuenta. |
| `ACTIVE_STORAGE_SERVICE` | `local` con volumen compartido por web/worker, o `s3` con bucket persistente privado y credenciales `S3_*`. |
| `REDIS_URL` | Redis del entorno; Sidekiq debe estar activo, con recuperación de trabajos de IA cada minuto. |
| `CADDY_ASK_SECRET` | Secreto compartido Caddy/web para autorizar TLS de subdominios registrados activos. |
| `PLATFORM_BASE_DOMAIN`, `PLATFORM_HOST`, `AUTH_HOST`, `CUSTOM_DOMAIN_CNAME_TARGET`, `APP_PROTOCOL=https`, `CADDY_SITE_ADDRESSES` | DNS, OAuth centralizado y HTTPS; usar dominios propios de staging. |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `PLATFORM_ADMIN_GOOGLE_EMAILS`, `SMTP_*`, `MAILER_FROM` | OAuth, operador e invitaciones por correo. |
| `SECRET_KEY_BASE`, `ACTIVE_RECORD_ENCRYPTION_KEY`, `POSTGRES_*` | Secretos y persistencia ya exigidos por la infraestructura actual. Nunca mezclar `DATABASE_URL` con `DB_*`. |

## Construcción segura

`.dockerignore` excluye `**/.env*`, salvo el ejemplo de la raíz, y `config/master.key`. `bin/check-docker-secrets` se ejecuta inmediatamente después de copiar el contexto y hace fallar la construcción si recibió un archivo de entorno o la clave maestra. Una prueba Rails comprueba las reglas, incluidos directorios anidados. Construir desde la raíz del repositorio usando ese Dockerfile; nunca pasar claves como `ARG`, `ENV` de build ni archivos copiados. Los secretos se inyectan únicamente al ejecutar contenedores mediante `env_file`.

```bash
docker build --pull -t ghcr.io/ORGANIZACION/turistack:SHA_INMUTABLE .
```

El tag debe identificar un commit completo y revisado. No construir desde un árbol con cambios sin incorporar. Verificar que `bin/check-docker-secrets` haya pasado en el log; no publicar imágenes si falla.

## Staging: procedimiento exacto

Este documento prepara acciones; no se ejecutó despliegue remoto ni se modificó infraestructura real.

1. Preparar el host aislado siguiendo [despliegue-dominios.md](despliegue-dominios.md). Configurar DNS `staging.turistack.com`, `auth.staging.turistack.com`, `tenants.staging.turistack.com` y `*.staging.turistack.com` hacia staging. Registrar en Google `https://auth.staging.turistack.com/auth/google_oauth2/callback`. No reutilizar bases, buckets, claves ni volúmenes productivos.
2. Copiar en el host `compose.staging.yml`, `deploy/Caddyfile` y `.env.staging` basado en `deploy/env.staging.example`, con permisos `chmod 600 .env.staging`. Reemplazar todos los ejemplos, completar SMTP, almacenamiento, Gemini y `CADDY_ASK_SECRET`; mantener `AGENT_ENABLED=false`. Conservar el mismo secreto en web y Caddy.
3. Respaldar PostgreSQL y storage/S3 y verificar una restauración en otro destino. Registrar tag/digest anterior. Para backup local en el host, con Compose configurado:

   ```bash
   export ENV_FILE=.env.staging
   docker compose --env-file .env.staging -f compose.staging.yml exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > backup-staging.dump
   ```

   Además respaldar el volumen `turistack-staging_storage_data` o el bucket, con un punto consistente respecto de la base. No usar `down -v`.

4. Incorporar y revisar la rama, publicar imagen inmutable y ejecutar desde el checkout autorizado:

   ```bash
   DEPLOY_HOST=HOST_STAGING \
   DEPLOY_USER=deploy \
   DEPLOY_ENVIRONMENT=staging \
   DEPLOY_PATH=/opt/turistack-staging \
   TURISTACK_IMAGE=ghcr.io/ORGANIZACION/turistack:SHA_INMUTABLE \
   bin/deploy-hetzner
   ```

   El script construye/publica imagen, valida Compose, espera PostgreSQL/Redis, migra una sola vez y actualiza web/worker/Caddy. Requiere Docker registry y SSH previamente configurados.

5. **Después de que todos los procesos web/worker estén en esta versión**, desde `/opt/turistack-staging` del host:

   ```bash
   export ENV_FILE=.env.staging
   docker compose --env-file .env.staging -f compose.staging.yml exec -T web bin/rails agent:finalize_hosts
   docker compose --env-file .env.staging -f compose.staging.yml exec -T web bin/rails tenant_integrity:audit
   docker compose --env-file .env.staging -f compose.staging.yml exec -T web bin/rails agent:audit
   ```

   Esa finalización agrega la restricción compartida de hosts y completa el propósito de transferencias OAuth antiguas. No ejecutarla mientras sigan procesos de la versión previa que no registra hosts.

6. Cambiar en `.env.staging` a `AGENT_ENABLED=true` y recrear web/worker/Caddy sin tocar volúmenes:

   ```bash
   docker compose --env-file .env.staging -f compose.staging.yml up -d --no-deps --force-recreate web worker caddy
   docker compose --env-file .env.staging -f compose.staging.yml ps
   docker compose --env-file .env.staging -f compose.staging.yml logs --tail=100 web worker caddy
   curl --fail --silent --show-error https://staging.turistack.com/up
   ```

7. Entrar como operador, abrir **Revendedores → Crear revendedor**, crear Silvina con `silvinamartinez` y su correo real. Confirmar entrega de invitación, inicio con Google y que el certificado HTTPS de `silvinamartinez.staging.turistack.com` se emita. Completar el recorrido de aceptación con un flyer sin datos personales, revisar errores/consumo de Gemini y ejecutar la matriz manual Android/iOS. Reiniciar web/worker y comprobar que original, JPEG y ficha sigan disponibles.

## Rollback y observabilidad

Primera respuesta ante una falla del piloto: cambiar `AGENT_ENABLED=false` y recrear web/worker. Se ocultan los catálogos y se detiene la extracción; no se eliminan archivos ni filas. Las agencias conservan su producto.

Preferir corrección hacia adelante. No ejecutar `db:rollback` a ciegas: revertir la migración exige no tener propietarios pendientes (`owner_id IS NULL`), y quitar migraciones iniciales borra catálogos. Tras `agent:finalize_hosts`, una versión previa que no conoce el registro compartido no es compatible para crear dominios. Si se necesita volver a esa versión, detener escrituras y restaurar el backup de base y archivos como un conjunto, con un procedimiento aprobado y reconciliando las escrituras posteriores. Para una versión compatible, fijar el tag anterior y repetir la actualización Compose, dejando el piloto deshabilitado hasta verificar compatibilidad de propietarios pendientes y trabajos en cola.

Monitorear salud web, worker y cola default, disco/bucket, errores `agent_ai.failed`, estados `AgentImport`/`AgentAiExecution`, duración/attempts y códigos seguros. No volcar claves, cuerpos de proveedor ni originales en logs. Verificar restauración de backups periódicamente y retención de archivos; no purgar blobs aún referenciados por revisiones/importaciones.

## CI y protección de main

CI incluye escaneo Ruby/JS, RuboCop, Rails, carga Zeitwerk, auditorías de integridad y Playwright. Instala Poppler para probar PDFs. El job agregado **Required checks** solo aprueba si los cuatro jobs base aprobaron. `crass` queda fijado por lockfile en 1.0.8, sin excepciones para su vulnerabilidad. El test de staging elimina explícitamente `DATABASE_URL` y otras variables de base/contenedor heredadas antes de definir `DB_*`; `RuntimeConfiguration` mantiene sus validaciones.

Para bloquear merges, un administrador debe crear/actualizar el ruleset de `main` en GitHub: requerir PR, revisión independiente, resolución de conversaciones y el status check **Required checks**, con rama actualizada, prohibiendo force push y borrado. El conector disponible no expone administración de protección de ramas y no hay `gh` autenticado en este entorno; la política remota no se cambió. Tras el primer CI de la rama, seleccionar el nombre exacto emitido por GitHub en el ruleset y probar que una ejecución fallida bloquee la integración. Un workflow por sí solo no configura protección remota.

## Límites pendientes y fuera de alcance

Pendientes de producción: staging real con DNS/TLS/OAuth/SMTP, confirmar modelo/cuota de Gemini con un flyer real, persistencia y restauración reales, matriz Android/iOS y activación remota del ruleset. Los tests simulados no sustituyen esas comprobaciones.

Se postergan reservas, cupos, pagos, rendiciones, comisiones automáticas, CRM, chatbots, automatizaciones y envío masivo de WhatsApp, suscripciones, cobros recurrentes, alta pública y generación creativa de flyers. El buscador/comparador que ya estaba preparado en el árbol se conserva sin ampliar su alcance.

## Verificación local de esta entrega

- `bin/rails test`: 156 pruebas, 945 aserciones, sin fallos, errores ni omisiones.
- `bin/rails zeitwerk:check`: correcto.
- `bin/rubocop`: 219 archivos, sin infracciones.
- `bin/brakeman --no-pager`: cero errores y advertencias de seguridad.
- `bin/bundler-audit`: sin vulnerabilidades; crass 1.0.8.
- `npm run test:e2e`: 18 recorridos correctos, escritorio y móvil Chromium, Gemini y selector del sistema simulados.
- `bin/rails tenant_integrity:audit` y `bin/rails agent:audit`: correctos. La base local emite una advertencia por el host demo de agencia ausente de `CADDY_SITE_ADDRESSES`; la configuración real del proxy debe completarse en staging.
- `git diff --check` y `git diff --cached --check`: correctos.
- Test de arranque staging ejecutado además con `DATABASE_URL` heredada: correcto, manteniendo SSL y cookies seguras.
- Construcción Docker local con assets y comprobación de ausencia de secretos: correcta. Conversión PDF probada dentro de la imagen como UID 1000, filesystem de solo lectura, sin red y sin capacidades adicionales: JPEG válido.
- Nueva migración revertida/reaplicada en una base descartable, seguida de `agent:finalize_hosts` y ambas auditorías: correcto. No se usaron bases remotas.

## Archivos de esta intervención

El árbol inicial ya contenía la implementación preparada de `Agent*`. Se conservó ese trabajo; el siguiente inventario distingue archivos agregados en esta intervención de archivos modificados sobre esa base.

Archivos nuevos:

- `app/javascript/controllers/flyer_share_controller.js`
- `app/mailers/agent_workspace_mailer.rb`
- `app/services/agent/flyer.rb`
- `app/services/agent/money_parser.rb`
- `app/views/agent/trips/_share.html.erb`
- `app/views/agent_workspace_mailer/invite.html.erb`
- `app/views/platform/agent_workspaces/new.html.erb`
- `bin/check-docker-secrets`
- `db/migrate/20261025130000_complete_reseller_catalog.rb`
- `docs/turistack-revendedor-lanzamiento.md`
- `test/e2e/reseller.spec.js`
- `test/integration/public_availability_test.rb`
- `test/integration/reseller_invitation_test.rb`
- `test/integration/reseller_mvp_test.rb`
- `test/lib/docker_build_safety_test.rb`
- `test/models/reseller_integrity_test.rb`

Archivos modificados sobre el árbol inicial:

- `.dockerignore`
- `.github/workflows/ci.yml`
- `Dockerfile`
- `Gemfile.lock`
- `README.md`
- `app/assets/stylesheets/agent.css`
- `app/controllers/agent/base_controller.rb`
- `app/controllers/agent/imports_controller.rb`
- `app/controllers/agent/public_catalog_controller.rb`
- `app/controllers/agent/suppliers_controller.rb`
- `app/controllers/agent/trips_controller.rb`
- `app/controllers/agent/website_controller.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/authentication_controller.rb`
- `app/controllers/platform/agent_workspaces_controller.rb`
- `app/controllers/sessions_controller.rb`
- `app/helpers/agent_helper.rb`
- `app/jobs/agent_ai_job.rb`
- `app/models/agent_import.rb`
- `app/models/agent_supplier.rb`
- `app/models/agent_trip.rb`
- `app/models/agent_trip_revision.rb`
- `app/models/agent_workspace.rb`
- `app/services/agent/ai_contract.rb`
- `app/services/agent/gemini_client.rb`
- `app/services/agent/save_trip.rb`
- `app/views/agent/dashboard/show.html.erb`
- `app/views/agent/import_items/edit.html.erb`
- `app/views/agent/imports/index.html.erb`
- `app/views/agent/imports/show.html.erb`
- `app/views/agent/onboarding/show.html.erb`
- `app/views/agent/public_catalog/index.html.erb`
- `app/views/agent/public_catalog/show.html.erb`
- `app/views/agent/suppliers/_form.html.erb`
- `app/views/agent/suppliers/show.html.erb`
- `app/views/agent/trips/_details.html.erb`
- `app/views/agent/trips/_filters.html.erb`
- `app/views/agent/trips/_form.html.erb`
- `app/views/agent/trips/new.html.erb`
- `app/views/agent/trips/show.html.erb`
- `app/views/landing/show.html.erb`
- `app/views/layouts/agent.html.erb`
- `app/views/platform/agent_workspaces/index.html.erb`
- `app/views/platform/companies/index.html.erb`
- `app/views/public_trips/show.html.erb`
- `config/routes.rb`
- `db/schema.rb`
- `docs/arquitectura.md`
- `docs/despliegue-dominios.md`
- `lib/tasks/tenant_integrity.rake`
- `test/integration/agent_workspace_test.rb`
- `test/lib/protected_environment_boot_test.rb`
- `test/support_agent_data.rb`
