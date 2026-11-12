# Turistack Pro: guía de lanzamiento

Esta guía describe el comportamiento actual de Pro. El nombre de archivo se conserva por compatibilidad con enlaces anteriores. La evidencia histórica del piloto queda en [hardening anterior](turistack-revendedor-hardening.md); sus cifras no acreditan esta entrega.

## Producto y acceso

USD 19 al mes, activación y renovación manual, sin débito automático. Google es el único login. Desde el dominio principal se puede ingresar a membresías empresariales sin contratar Pro ni crear un negocio personal. `/context` muestra Mi espacio y Empresas que me dan acceso. El cambio valida una membresía activa de esa identidad y un dominio autorizado; el host elegido revalida sesión y permisos. Si no hay sesión en ese host, se usa su botón Google y el intercambio efímero existente, sin compartir cookies entre subdominios.

Alta autónoma: Google → nombre/marca, slug y WhatsApp → proveedor → importar o crear viaje → revisar → publicar → compartir → consulta → registro manual de cliente y nota. Disponible donde `AGENT_ENABLED` esté habilitado y la integridad de hosts finalizada. Una identidad solo tiene un espacio personal; reintentos no crean otra prueba.

El panel vive en `/agente`. La web canónica es `/:agent_slug` y la ficha `/:agent_slug/viajes/:slug`, en `PLATFORM_HOST`. Los hosts existentes se conservan. No configurar subdominios nuevos como requisito de alta. Las landings empresariales mantienen su contenido anterior; la landing de plataforma anuncia únicamente Pro.

`User` es identidad, `Company`/`Membership` son accesos empresariales y `AgentWorkspace` es el negocio personal. `AgentSupplier` es un contacto privado: no busca, crea ni enlaza empresas por coincidencias de nombre, email o teléfono. Empresas y asesores no acceden a datos ajenos. Los módulos operativos de agencias no forman parte de Pro.

## Suscripción y vencimiento

`AgentSubscription` es la única fuente de estado comercial. `AgentWorkspace.plan` es una columna histórica ignorada por el modelo, retenida para compatibilidad de esquema. `Agent::Access` se usa desde controllers, consultas públicas, servicios, modelos de escritura y jobs; los permisos se calculan con fechas en cada operación, sin job nocturno.

Nuevas altas: prueba de 14 días, creada en la misma transacción que el espacio. El estado `trialing` concede acceso entre inicio inclusive y fin exclusivo. `active` usa el período manual vigente; `inactive` no concede acceso. La cancelación al vencimiento conserva acceso hasta el final del período y excluye gracia. Por defecto no hay gracia. La suspensión administrativa en `AgentWorkspace.status` es independiente y bloquea el espacio aunque la suscripción esté vigente.

Al vencer se conservan todas las filas y archivos. El propietario mantiene lectura y exportación privada y puede solicitar activación. Se rechazan nuevas importaciones, ediciones, publicaciones y ejecuciones de IA. Web, búsqueda, fotos e imágenes públicas devuelven 404. No se cambian estados de viajes ni punteros de revisión. Reactivar restituye la última revisión publicada; los borradores siguen privados. Las membresías empresariales y la identidad no se modifican.

Activación manual:

1. El asesor abre **Mi plan → Solicitar activación o renovación manual**. No introduce datos de tarjetas ni paga en Turistack.
2. Un operador cuyo correo Google esté autorizado en `PLATFORM_ADMIN_GOOGLE_EMAILS` ingresa al dominio principal y abre `/platform/agent_workspaces`.
3. Revisa la solicitud y coordina el pago por fuera del producto. Pulsa **Activar / renovar un mes** una sola vez por período acordado. Cada pulsación agrega un mes calendario desde el fin futuro vigente o desde ahora si está vencido. No hay un webhook ni conciliación automática.
4. Comprueba estado, fin del período, auditoría `agent_subscription.month_granted` y web pública. La acción no levanta suspensiones administrativas. Se guarda actor, identificadores y cambios de estado/fechas/precio, sin contenido de clientes ni notas.

El precio se guarda en centavos enteros USD en la suscripción. Cambiar el precio por entorno afecta nuevas altas; no reescribe acuerdos existentes. Las rutas del asesor no admiten estado, precio, plan ni fechas comerciales mediante parámetros. La renovación manual no vuelve a crear una prueba.

## Migraciones y transición del piloto

Aplicar estas migraciones incrementales después de las existentes, sin editar las históricas:

- `20261112120000_add_agent_pro_subscriptions`: crea y completa suscripciones del piloto.
- `20261112121000_create_agent_clients`: agenda y notas con claves compuestas de espacio.
- `20261112122000_add_agent_ai_consumption_units`: consumo por intento e índice mensual.
- `20261112123000_allow_general_identity_authentication`: propósito de login general, separado de operador.

La primera asigna a cada piloto una transición gratuita explícita de **30 días desde el momento de migración**, con `origin=pilot_transition` y fin persistido, incluso si el espacio está suspendido. No altera propietarios, slugs, archivos, revisiones, estados ni membresías. No declara a nadie cliente pago. El `ON CONFLICT` impide reiniciar una transición si se repite el backfill; Rails registra la migración ejecutada. `AGENT_PILOT_TRANSITION_DAYS` permite definir de 1 a 90 días **antes de migrar**. Comunicar el vencimiento a los pilotos antes de habilitar la nueva versión; Mi plan lo muestra. Cambiar esa variable después no extiende períodos existentes.

Las ejecuciones históricas reciben una unidad por intento: no se puede reconstruir de forma fiable cuántas páginas se procesaron antes. Todas las nuevas ejecuciones computan páginas. No borrar consumo para reiniciar cuotas.

## Cuotas, archivos y privacidad

Presupuesto mensual de 200 unidades, compartido entre importaciones y búsquedas de un espacio. Se renueva el día 1 a medianoche en su zona horaria, sin acumulación ni reinicio al renovar Pro. Imagen o búsqueda: una unidad por intento; PDF: una por página y por intento. Cada llamada reservada consume incluso por errores de red/proveedor, respuesta inválida, reintento automático/manual, lease vencido o descarte posterior. Validaciones rechazadas antes de reservar no consumen. Repetir la misma solicitud idempotente no crea ejecución ni consumo adicional.

El job reserva `AgentAiExecution.consumption_units` bajo el mismo lock del espacio usado para límites diarios y concurrencia. Comprueba permisos antes de llamar a Gemini y antes de guardar el resultado. Los reintentos conservan el consumo histórico. El archivo y las correcciones se mantienen al agotar cuota; con Pro vigente se puede crear manualmente desde el mismo original. IA nunca publica ni recibe clientes/notas. Se conserva el proveedor y modelo Gemini existente; no se hicieron llamadas facturables reales en las verificaciones.

Archivos de hasta 10 MB. PDF inicialmente hasta 10 páginas, configurable hasta un máximo duro de 20; se valida cada página antes de enviar el documento completo, con timeout de parseo. Hasta 50 fichas por extracción y salida de proveedor acotada a 16000 tokens. Poppler convierte solo la primera página para vista previa, con límites de CPU, memoria, tiempo y tamaño. El original se conserva privado; una ficha puede necesitar un flyer propio si el PDF contiene varias propuestas.

La agenda requiere nombre y teléfono normalizado con código de país; email opcional. Los nombres/contactos del directorio de proveedores no se publican como datos estructurados; las fichas identifican al asesor. Las notas son privadas, fechadas, con referencia opcional a un viaje del mismo espacio. Archivar no borra notas. No hay creación automática por clic en WhatsApp ni lectura de conversaciones. Las exportaciones CSV de contactos y notas neutralizan fórmulas; `/agente/export.json` exporta datos del negocio autenticado. Los originales se descargan por las rutas privadas de importaciones/viajes; el JSON no empaqueta los archivos binarios. Lecturas y exportaciones usan `private, no-store`. Parámetros de contactos/notas se filtran de logs y las auditorías contienen identificadores, sin texto privado.

Las rutas globales de Active Storage siguen deshabilitadas. Cada imagen pública revalida permiso y revisión. Rack::Attack cubre fichas canónicas y antiguas, catálogos por slug, búsquedas, imágenes/fotos, altas, sugerencias e importaciones. Staging hereda producción: Rails cache Redis compartida por todas las instancias; usar el mismo `REDIS_URL` en web/worker. Memoria local no sirve como límite global multiinstancia.

## Variables

| Variable | Inicial | Aplicación |
| --- | --- | --- |
| `AGENT_PRO_PRICE_CENTS` | `1900` | Precio USD de nuevas suscripciones; entero, sin flotantes. |
| `AGENT_PRO_TRIAL_DAYS` | `14` | Prueba de nuevas altas, de 1 a 90 días. |
| `AGENT_PRO_GRACE_DAYS` | `0` | Gracia de períodos activos no cancelados, de 0 a 30 días. |
| `AGENT_PRO_MONTHLY_AI_UNITS` | `200` | Presupuesto mensual, de 0 a 100000 unidades por espacio. |
| `AGENT_PILOT_TRANSITION_DAYS` | `30` | Solo al migrar pilotos, de 1 a 90 días; no vuelve a correr. |
| `AGENT_MAX_PDF_PAGES` | `10` | Límite de documento, de 1 a 20 páginas. |
| `AGENT_IMPORTS_PER_DAY` / `AGENT_SEARCHES_PER_DAY` | `25` / `100` | Intentos y altas de solicitudes por día local. |
| `AGENT_IMPORTS_PER_MINUTE` / `AGENT_SEARCHES_PER_MINUTE` | `5` / `20` | Ráfagas por espacio. |
| `AGENT_AI_CONCURRENCY` | `2` | Ejecuciones simultáneas por espacio. |

Conservar `AGENT_ENABLED`, `GEMINI_API_KEY`, `GEMINI_MODEL=gemini-3.5-flash-lite`, `REDIS_URL`, almacenamiento privado compartido y las variables de OAuth/hosts/SMTP existentes. No rotar `ACTIVE_RECORD_ENCRYPTION_KEY` ni `SECRET_KEY_BASE` como parte de esta actualización. Los defaults se aplican sin añadir variables obligatorias.

## Actualización y reversión seguras

Esta entrega no ejecuta push, despliegues ni operaciones sobre datos productivos.

1. Revisar el diff completo, incluidos cambios locales previos. Tomar backup consistente de PostgreSQL y storage/bucket y probar restauración aislada. Registrar tag anterior, configuración y claves estables. Ver [procedimiento de infraestructura](despliegue-dominios.md).
2. Comunicar transición a pilotos y fijar configuración compartida. Mantener `AGENT_ENABLED=false` durante el cambio, detener/drenar jobs Agent y evitar mezclar workers antiguos sin permisos comerciales con nuevos. Las agencias conservan su operación.
3. En staging primero, ejecutar `bin/rails db:migrate` una sola vez con la nueva imagen. Sin resets, seeds ni cambios de claves. Reiniciar todos los procesos web/worker en la misma versión. Si la instalación nunca finalizó hosts, ejecutar su procedimiento existente `agent:finalize_hosts` en el orden documentado.
4. Ejecutar `tenant_integrity:audit` y `agent:audit`. Revisar que todos los espacios tengan suscripción con fin definido y que los suspendidos sigan suspendidos. Usar Redis compartido y storage accesible desde web/worker.
5. Habilitar `AGENT_ENABLED=true`; probar Google, dos empresas sin Pro, prueba nueva, vencimiento, imágenes/búsqueda, reactivación, clientes y exportación con identidades separadas. Verificar precio y fechas del piloto en Mi plan. Activar manualmente solo períodos acordados.
6. Monitorear jobs, consumo/unidades, errores seguros, disco, almacenamiento y auditorías. Probar compartir en Android/Chrome y Safari/iPhone sobre HTTPS real. Playwright con Pixel 7 no valida envío real de WhatsApp ni selector nativo.

Reversión preferida: deshabilitar `AGENT_ENABLED` en web y worker, conservar todas las migraciones/datos y corregir hacia adelante. Si se revierte código, mantener Agent deshabilitado: una versión anterior no aplica vencimiento ni cuotas mensuales. No hacer `db:rollback` sobre una base con suscripciones/clientes/notas: perdería historia de pruebas y agenda. Una restauración completa requiere un destino aislado, base y archivos del mismo punto y reconciliación de escrituras posteriores. No borrar volúmenes ni bajar las tablas de agencias.

## Verificación

Comandos requeridos: `bin/rails test`, `bin/rails zeitwerk:check`, `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `npm run test:e2e`, `bin/rails tenant_integrity:audit`, `bin/rails agent:audit`, `git diff --check`. Ejecutar Rails y auditorías con una base local/test, nunca inferir infraestructura remota.

Playwright usa por defecto una base nueva `turistack_e2e_<timestamp>_test`, que puede eliminarse después de revisar evidencias, solo identificándola explícitamente como descartable. `E2E_DB_NAME` permite elegir una base vacía terminada en `_test`. OAuth/Gemini se simulan. No se debilitan los checks de CI.

## Evidencia local de esta entrega — 12/11/2026

Base de referencia `0e649269b215da640f79c19a3ed1c5e57d9c372a`, conservando los cambios locales previos. Verificación final sobre código actualizado, PostgreSQL local y respuestas OAuth/Gemini simuladas:

| Verificación | Resultado real |
| --- | --- |
| `PARALLEL_WORKERS=2 bin/rails test` | 230 pruebas, 2898 aserciones, 0 fallos, 0 errores, 0 omisiones. |
| `RAILS_ENV=test bin/rails zeitwerk:check` | Carga completa correcta. |
| `bin/rubocop` | 258 archivos, sin infracciones. |
| `bin/brakeman --no-pager` | 79 controles, 0 errores, 0 advertencias de seguridad. |
| `bin/bundler-audit` | Sin vulnerabilidades conocidas. |
| `npm run test:e2e` | 46 recorridos correctos en Chromium de escritorio y Pixel 7; incluye alta → proveedor → publicación → WhatsApp → cliente → nota. |
| `RAILS_ENV=test bin/rails tenant_integrity:audit` | OK; avisos por hosts y CNAME de fixtures locales que no corresponden al proxy de prueba. |
| `RAILS_ENV=test bin/rails agent:audit` | OK, incluidas suscripciones y referencias de notas. |
| `git diff --check` y `git diff --cached --check` | Correctos. |

Se verificó además con dos clientes de caché independientes sobre un Redis local descartable que el contador de Rack::Attack se comparte atómicamente (lecturas sucesivas 1 y 2). Las pruebas de middleware ejercitan los límites reales de las rutas canónicas, búsquedas, imágenes, alta y exclusión de assets. Las migraciones se aplicaron en test y el backfill de pilotos se probó dos veces sin reiniciar fechas ni levantar suspensiones.

El comando original de Brakeman fallaba al cargar `timeout` 0.6 en Ruby 3.4 por su prueba protegida de Ractor. `bin/brakeman` ahora carga esa misma dependencia antes de la trampa de excepciones del escáner. Se mantiene `--ensure-latest`, sin ignorar controles ni advertencias; el comando solicitado terminó correctamente. Los fallos detectados durante las primeras corridas se corrigieron antes de la verificación final.

La revisión visual móvil comprobó contraste, menú, agenda y ausencia de desbordamiento. No se validaron DNS/TLS, Google/SMTP/Gemini de cuentas reales ni el selector/envío real de WhatsApp en Android/iOS. No se hizo push, despliegue ni acceso a datos productivos. Los logs locales quedan en `tmp/pro-verification/` y los artefactos de Playwright en `test-results/` (ambos fuera de Git).
