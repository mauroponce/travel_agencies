# Turistack Pro: guía de lanzamiento

Esta guía describe el comportamiento actual de Pro. El nombre de archivo se conserva por compatibilidad con enlaces anteriores. La evidencia histórica del piloto queda en [hardening anterior](turistack-revendedor-hardening.md); sus cifras no acreditan esta entrega.

## Producto y acceso

USD 19 al mes, activación y renovación manual, sin débito automático. Google es el único login. Desde el dominio principal se puede ingresar a membresías empresariales sin contratar Pro ni crear un negocio personal. `/contexto` muestra Mi espacio y Empresas que me dan acceso. El cambio valida una membresía activa de esa identidad y un dominio autorizado; el host elegido revalida sesión y permisos. Si no hay sesión en ese host, se usa su botón Google y el intercambio efímero existente, sin compartir cookies entre subdominios.

Alta autónoma: Google → nombre/marca, slug y WhatsApp → proveedor → importar o crear viaje → revisar → publicar → compartir → consulta → registro manual de cliente y nota. Disponible donde `AGENT_ENABLED` esté habilitado y la integridad de hosts finalizada. Una identidad solo tiene un espacio personal; reintentos no crean otra prueba.

El panel vive en `/asesor`. La web canónica es `/:agent_slug` y la ficha `/:agent_slug/viajes/:slug`, en `PLATFORM_HOST`. Los hosts existentes se conservan. No configurar subdominios nuevos como requisito de alta. Las landings empresariales mantienen su contenido anterior; la landing de plataforma anuncia únicamente Pro.

La URL del asesor es una decisión de producto independiente del aislamiento empresarial por subdominios. En staging/producción los metadatos canónicos y `og:url` usan HTTPS y el dominio principal; `og:image` se sirve en el mismo origen de la página, también para hosts históricos. No cambiar la estrategia para acomodar pruebas antiguas.

`User` es identidad, `Company`/`Membership` son accesos empresariales y `AgentWorkspace` es el negocio personal. `AgentSupplier` es un contacto privado: no busca, crea ni enlaza empresas por coincidencias de nombre, email o teléfono. Empresas y asesores no acceden a datos ajenos. Los módulos operativos de agencias no forman parte de Pro.

## Suscripción y vencimiento

`AgentSubscription` es la única fuente de estado comercial. `AgentWorkspace.plan` es una columna histórica ignorada por el modelo, retenida para compatibilidad de esquema. `Agent::Access` se usa desde controllers, consultas públicas, servicios, modelos de escritura y jobs; los permisos se calculan con fechas en cada operación, sin job nocturno.

Nuevas altas: prueba de 14 días, creada en la misma transacción que el espacio. El estado `trialing` concede acceso entre inicio inclusive y fin exclusivo. `active` usa el período manual vigente; `inactive` no concede acceso. La cancelación al vencimiento conserva acceso hasta el final del período y excluye gracia. Por defecto no hay gracia. La suspensión administrativa en `AgentWorkspace.status` es independiente y bloquea el espacio aunque la suscripción esté vigente.

Al vencer se conservan todas las filas y archivos. El propietario mantiene lectura y exportación privada y puede solicitar activación. Se rechazan nuevas importaciones, ediciones, publicaciones y ejecuciones de IA. Web, búsqueda, fotos e imágenes públicas devuelven 404. No se cambian estados de viajes ni punteros de revisión. Reactivar restituye la última revisión publicada; los borradores siguen privados. Las membresías empresariales y la identidad no se modifican.

Activación manual:

1. El asesor abre **Mi plan → Solicitar activación o renovación manual**. No introduce datos de tarjetas ni paga en Turistack.
2. Un operador cuyo correo Google esté autorizado en `PLATFORM_ADMIN_GOOGLE_EMAILS` ingresa al dominio principal y abre `/plataforma/asesores`.
3. Revisa la solicitud y coordina el pago por fuera del producto. Pulsa **Activar / renovar un mes** una sola vez por período acordado. Cada pulsación agrega un mes calendario desde el fin futuro vigente o desde ahora si está vencido. No hay un webhook ni conciliación automática.
4. Comprueba estado, fin del período, auditoría `agent_subscription.month_granted` y web pública. La acción no levanta suspensiones administrativas. Se guarda actor, identificadores y cambios de estado/fechas/precio, sin contenido de clientes ni notas.

El precio se guarda en centavos enteros USD en la suscripción. Cambiar el precio por entorno afecta nuevas altas; no reescribe acuerdos existentes. Las rutas del asesor no admiten estado, precio, plan ni fechas comerciales mediante parámetros. La renovación manual no vuelve a crear una prueba.

## Migraciones y transición del piloto

Aplicar estas migraciones incrementales después de las existentes, sin editar las históricas:

- `20261112120000_add_agent_pro_subscriptions`: crea y completa suscripciones del piloto.
- `20261112121000_create_agent_clients`: agenda y notas con claves compuestas de espacio.
- `20261112122000_add_agent_ai_consumption_units`: consumo por intento e índice mensual.
- `20261112123000_allow_general_identity_authentication`: propósito de login general, separado de operador.
- `20261112124000_encrypt_agent_contacts`: cifra contactos y notas existentes, incluidos espacios vencidos/suspendidos, sin cambiar IDs, referencias, fechas ni acuerdos. Reemplaza el índice de nombres por espacio/archivo/ID.

La primera asigna a cada piloto una transición gratuita explícita de **30 días desde el momento de migración**, con `origin=pilot_transition` y fin persistido, incluso si el espacio está suspendido. No altera propietarios, slugs, archivos, revisiones, estados ni membresías. No declara a nadie cliente pago. El `ON CONFLICT` impide reiniciar una transición si se repite el backfill; Rails registra la migración ejecutada. `AGENT_PILOT_TRANSITION_DAYS` permite definir de 1 a 90 días **antes de migrar**. Comunicar el vencimiento a los pilotos antes de habilitar la nueva versión; Mi plan lo muestra. Cambiar esa variable después no extiende períodos existentes.

Las ejecuciones históricas reciben una unidad por intento: no se puede reconstruir de forma fiable cuántas páginas se procesaron antes. Todas las nuevas ejecuciones computan páginas. No borrar consumo para reiniciar cuotas.

## Cuotas, archivos y privacidad

Presupuesto mensual de 200 unidades, compartido entre importaciones y búsquedas de un espacio. Se renueva el día 1 a medianoche en su zona horaria, sin acumulación ni reinicio al renovar Pro. Imagen o búsqueda: una unidad por intento; PDF: una por página y por intento. Cada llamada reservada consume incluso por errores de red/proveedor, respuesta inválida, reintento automático/manual, lease vencido o descarte posterior. Validaciones rechazadas antes de reservar no consumen. Repetir la misma solicitud idempotente no crea ejecución ni consumo adicional.

El job reserva `AgentAiExecution.consumption_units` bajo el mismo lock del espacio usado para límites diarios y concurrencia. Comprueba permisos antes de llamar a Gemini y antes de guardar el resultado. Los reintentos conservan el consumo histórico. El archivo y las correcciones se mantienen al agotar cuota; con Pro vigente se puede crear manualmente desde el mismo original. IA nunca publica ni recibe clientes/notas. Se conserva el proveedor y modelo Gemini existente; no se hicieron llamadas facturables reales en las verificaciones.

Archivos de hasta 10 MB. PDF inicialmente hasta 10 páginas, configurable hasta un máximo duro de 20; se valida cada página antes de enviar el documento completo, con timeout de parseo. Hasta 50 fichas por extracción y salida de proveedor acotada a 16000 tokens. Poppler convierte solo la primera página para vista previa, con límites de CPU, memoria, tiempo y tamaño. El original se conserva privado; una ficha puede necesitar un flyer propio si el PDF contiene varias propuestas.

La agenda requiere nombre y teléfono normalizado con código de país; email opcional. Los nombres/contactos del directorio de proveedores no se publican como datos estructurados; las fichas identifican al asesor. Las notas son privadas, fechadas, con referencia opcional a un viaje del mismo espacio. Archivar no borra notas. No hay creación automática por clic en WhatsApp ni lectura de conversaciones. Las exportaciones CSV de contactos y notas neutralizan fórmulas; `/asesor/exportar.json` exporta datos del negocio autenticado. Los originales se descargan por las rutas privadas de importaciones/viajes; el JSON no empaqueta los archivos binarios. Lecturas y exportaciones usan `private, no-store`. Parámetros de contactos/notas se filtran de logs y las auditorías contienen identificadores, sin texto privado.

`AgentClient.name`, `phone`, `email` y `AgentClientNote.body` usan Active Record Encryption no determinista con las mismas claves estables de pasajeros. PostgreSQL/backups nuevos contienen ciphertext; IDs, relaciones de viajes y fechas siguen visibles para mantener integridad. La aplicación descifra solo para el propietario autorizado, incluidos CSV/JSON, que contienen información privada legible y deben guardarse con acceso restringido. El cifrado de aplicación no reemplaza TLS, permisos de base/storage ni protección de claves/backups.

La búsqueda conserva coincidencias parciales literales de nombre/teléfono/email, sin distinguir mayúsculas. Recorre por lotes de 100 únicamente el espacio autorizado y filtra archivados antes de descifrar; ordena en memoria y pagina por IDs. No guarda índices con nombres, fragmentos, hashes de teléfonos ni términos de búsqueda. Costo O(N) por directorio: adecuado para el piloto; medir latencia/volumen antes de escalar. Las notas no se consultan durante la búsqueda.

La migración acepta texto plano exclusivamente en sus lectores internos, cifra por fila bajo lock y es reanudable: no vuelve a cifrar filas ya completas. Verifica que los sobres existentes sean descifrables antes de escribir; una clave incorrecta aborta. La aplicación normal rechaza texto plano y `agent:audit` detecta campos sin cifrar o ilegibles sin imprimir contenido. No habilitar Pro hasta completar y auditar. `down` es irreversible para evitar devolver datos privados a texto plano.

Política inicial de retención: vencer, suspender o archivar conserva contactos, notas, referencias y originales; no hay borrado automático. El propietario puede exportarlos desde agenda y exportación JSON aun con plan vencido. Una solicitud de eliminación se atiende manualmente, verificando identidad y alcance, revisando referencias y obligaciones aplicables antes de ejecutar un procedimiento específico autorizado; esta entrega no borra filas ni incorpora una purga. Registrar la atención sin copiar contenido privado. Backups previos pueden conservar texto plano: restringir acceso, cifrar el soporte, inventariar retención y acordar su vencimiento antes del piloto. No eliminarlos como parte de esta actualización. Conservar las claves necesarias durante toda la vida de los backups.

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

Runtime único: Ruby **3.4.12**, fijado en `.ruby-version` (leído por `ruby/setup-ruby`), Docker y documentación. Rails **8.1.4.1**, Rack 3.2.8, Nokogiri 1.19.7, Addressable 2.9.2, Loofah 2.25.3 y rails-html-sanitizer 1.7.2 incorporan los parches de seguridad detectados por la auditoría actualizada; no se cambian versiones mayores. Reconstruir imágenes web/worker; no reutilizar imágenes con Ruby 3.4.1 ni el lockfile anterior.

Esta entrega prepara una rama/PR; no despliega ni opera sobre datos productivos.

1. Revisar el diff completo, incluidos cambios locales previos. Tomar backup consistente de PostgreSQL y storage/bucket y probar restauración aislada. Registrar tag anterior, configuración y claves estables. Ver [procedimiento de infraestructura](despliegue-dominios.md).
2. Comunicar transición a pilotos y fijar configuración compartida. Mantener `AGENT_ENABLED=false` en todos los procesos durante el cambio, drenar/detener workers y cerrar procesos web antiguos antes de cifrar: el código anterior no puede leer ciphertext. Usar una ventana de mantenimiento coordinada para esta actualización compartida. No mezclar lectores/escritores antiguos con nuevos.
3. En staging primero, ejecutar `bin/rails db:migrate` una sola vez con la nueva imagen. Sin resets, seeds ni cambios de claves. Reiniciar todos los procesos web/worker en la misma versión. Si la instalación nunca finalizó hosts, ejecutar su procedimiento existente `agent:finalize_hosts` en el orden documentado.
4. Ejecutar `tenant_integrity:audit` y `agent:audit`. Revisar que todos los espacios tengan suscripción con fin definido y que los suspendidos sigan suspendidos. Usar Redis compartido y storage accesible desde web/worker.
5. Habilitar `AGENT_ENABLED=true`; probar Google, dos empresas sin Pro, prueba nueva, vencimiento, imágenes/búsqueda, reactivación, clientes y exportación con identidades separadas. Verificar precio y fechas del piloto en Mi plan. Activar manualmente solo períodos acordados.
6. Monitorear jobs, consumo/unidades, errores seguros, disco, almacenamiento y auditorías. Probar compartir en Android/Chrome y Safari/iPhone sobre HTTPS real. Playwright con Pixel 7 no valida envío real de WhatsApp ni selector nativo.

Reversión preferida: deshabilitar `AGENT_ENABLED` en web y worker, conservar todas las migraciones/datos y corregir hacia adelante. Si se revierte código, mantener Agent deshabilitado: una versión anterior no aplica vencimiento ni cuotas mensuales. No hacer `db:rollback` sobre una base con suscripciones/clientes/notas: perdería historia de pruebas y agenda. Una restauración completa requiere un destino aislado, base y archivos del mismo punto y reconciliación de escrituras posteriores. No borrar volúmenes ni bajar las tablas de agencias.

Tras cifrar, conservar además los lectores cifrados y `ACTIVE_RECORD_ENCRYPTION_KEY` original en cualquier versión de recuperación. Si la migración se interrumpe, mantener Pro cerrado y volver a ejecutar con la misma clave; algunas filas ya estarán cifradas. No intentar resolver errores cambiando claves ni activando lectura global de texto plano.

## Verificación

Comandos requeridos: `bin/rails test`, `bin/rails zeitwerk:check`, `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `npm run test:e2e`, `bin/rails tenant_integrity:audit`, `bin/rails agent:audit`, `git diff --check`. Ejecutar Rails y auditorías con una base local/test, nunca inferir infraestructura remota.

Playwright usa por defecto una base nueva `turistack_e2e_<timestamp>_test`, que puede eliminarse después de revisar evidencias, solo identificándola explícitamente como descartable. `E2E_DB_NAME` permite elegir una base vacía terminada en `_test`. OAuth/Gemini se simulan. No se debilitan los checks de CI.

## Evidencia de estabilización — 12/11/2026

Referencia: `efe5be3b22d2a22cd95714100d16dcf57203a63b`, último `main` comprobado antes de crear `fix/pilot-stabilization-privacy`. La [CI anterior](https://github.com/mauroponce/travel_agencies/actions/runs/43154881424) fallaba realmente al instalar Ruby 3.4.1 en Ubuntu 26.04 y al exigir en staging el canonical antiguo. Se corrigieron ambos contratos sin retirar controles. El recorrido de Google en navegador detectó además un bloqueo de CSP en el regreso al origen: la página de autenticación ahora permite únicamente el destino de la solicitud validada, además de Google y el host de autenticación.

Verificación local con Ruby 3.4.12, Rails 8.1.4.1 y PostgreSQL, repetida después de actualizar el lockfile:

| Control | Resultado real |
| --- | --- |
| `PARALLEL_WORKERS=2 bin/rails test` | 241 pruebas, 3018 aserciones, sin fallos, errores ni omisiones. Incluye búsqueda vacía o solo espacios. |
| `RAILS_ENV=test bin/rails zeitwerk:check` | Carga completa correcta. |
| `bin/rubocop` | Sin infracciones. |
| `bin/brakeman --no-pager` | 0 errores y 0 advertencias de seguridad. |
| `bin/bundler-audit` | Sin vulnerabilidades conocidas. |
| `bin/importmap audit` | Sin paquetes vulnerables. |
| `RAILS_ENV=test bin/rails tenant_integrity:audit` | OK. |
| `RAILS_ENV=test bin/rails agent:audit` | OK, incluye cifrado y referencias privadas. |
| `npm run test:e2e -- --workers=2` | 48 recorridos aprobados en escritorio y Pixel 7. |
| `git diff --check` | Correcto; árbol de trabajo limpio tras publicar. |

Las pruebas nuevas cubren ciphertext no determinista, búsqueda parcial por propietario/archivo, migración reanudable desde texto plano con plan vencido/suspendido y precio histórico, claves incompatibles sin sobrescritura, logs sin datos privados, exportaciones y cookies independientes por host. Las carreras de publicación y respuesta de Gemini comprueban acceso fresco y descarte tras vencimiento, conservando originales y consumo. Se mantienen las pruebas anteriores de cuotas simultáneas, reintentos, idempotencia, páginas PDF y operación empresarial.

La primera ejecución local de Bundler Audit usó una base de avisos antigua. Al ejecutar el control en CI se detectaron avisos adicionales y se reprodujeron localmente tras actualizarla. El comando sin argumentos ahora ejecuta `check --update`, igualando la evidencia local a un runner nuevo; un fallo al actualizar no se presenta como auditoría correcta. Se corrigieron las dependencias mediante actualizaciones conservadoras de mantenimiento, sin exclusiones nuevas.

`agent_pilot.spec.js` recorre Google simulado mediante el intercambio real de hosts, alta/prueba, proveedor, PDF con cuatro salidas, revisión de dos fichas, publicación, filtros destino/fechas, WhatsApp, cliente/nota/exportación, vencimiento, bloqueo, lectura, renovación mediante UI de operador y restitución exclusiva de la revisión publicada. Compara las dos membresías empresariales antes y después y rechaza otro asesor. Las fixtures solo existen en test con `AGENT_E2E_FIXTURES=true`; Playwright usa CSRF y deshabilita conexiones externas mediante WebMock.

La repetición de CI detectó interferencia entre pruebas que compartían el asesor demo: ocultar Viajes durante la prueba de configuración podía dejar sin catálogo a los recorridos de importación y de compartir. La configuración de web usa ahora un espacio exclusivo por dispositivo y espera la confirmación del guardado. La validación visual espera que carguen los estilos al cambiar al host de autenticación antes de leer su apariencia. Se conservan todos los recorridos y aserciones; no se agregan reintentos ni se elevan timeouts para cubrir esas condiciones.

`bin/smoke-staging` crea un proyecto Compose y credenciales sintéticas únicos: migra una base vacía y una base anterior con datos de agencias y contactos Pro en texto plano; arranca web/worker/PostgreSQL/Redis; valida HTTP anónimo canónico y antiguo, metadatos HTTPS, imágenes, originales privados y ausencia de fixtures de test; comprueba reinicio, despublicación y restauración consistente de DB/storage cifrado con la misma clave. No usa credenciales ni datos de un entorno existente.

La [CI de `c264e21`](https://github.com/mauroponce/travel_agencies/actions/runs/43161420757) ejecutó y aprobó todos los controles, sin omitir jobs:

| Job | Resultado |
| --- | --- |
| `scan_ruby` | SUCCESS: Brakeman y Bundler Audit actualizado. |
| `scan_js` | SUCCESS: Importmap Audit. |
| `lint` | SUCCESS: RuboCop. |
| `test` | SUCCESS: 241 pruebas Rails/3017 aserciones, Zeitwerk, auditorías y 48 Playwright. |
| `Docker development boot` | SUCCESS: Compose, Caddy y smoke completo con backup/restore. |
| `Required checks` | SUCCESS: todos los jobs requeridos aprobaron. |

El smoke de CI terminó con `Staging clean migrations, agency/reseller coexistence, worker, public PDF, persistence and backup/restore: OK`. Verificó el cifrado de contactos anteriores, notas y referencias después del reinicio y la restauración; preservó el precio histórico y el vencimiento.

Límite del entorno local: las imágenes llegaron a exportarse, pero los clientes Docker quedaron retenidos; el daemon registró `extraction snapshot removal failed: calling snapshotter.Remove is forbidden`. Se interrumpieron los dos intentos propios y se limpiaron sus proyectos descartables; no se contabilizan como smoke/boot local aprobado. La evidencia completa de Docker corresponde a la ejecución real de CI indicada arriba. No se modificó el daemon ni los servicios ajenos al proyecto.

La rama está publicada. La integración de GitHub devolvió `403 Resource not accessible by integration` al intentar crear el PR; necesita permisos de escritura sobre Pull Requests o apertura manual desde la comparación de la rama. No se afirma que el PR haya sido creado. Los logs locales y la descripción preparada quedan en `tmp/stabilization/` y las trazas de navegador en `test-results/`, fuera de Git. Antes de integrar, comprobar también los checks del último commit de documentación y realizar una revisión independiente del diff.

Antes del piloto real siguen siendo necesarios DNS/TLS del dominio principal, autenticación y hosts históricos, OAuth Google con callbacks autorizados, Redis compartido, PostgreSQL y almacenamiento privado con backups restaurables, claves estables custodiadas, SMTP y una cuenta Gemini con límites y monitoreo. No se validaron credenciales, DNS ni servicios de cuentas reales ni envío nativo de WhatsApp en Android/iOS; Pixel 7 en Playwright no acredita ese envío. No se ejecutó despliegue ni se accedió a datos productivos. Revisar independientemente el PR y ejecutar el recorrido de staging real antes de admitir usuarios del piloto.
