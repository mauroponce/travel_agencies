# Arquitectura

## Vista general

Turistack es un monolito Rails con HTML server-rendered, Turbo y Stimulus. PostgreSQL es la fuente de verdad; Redis soporta Sidekiq, caché y tareas programadas. Active Storage conserva comprobantes e imágenes en disco privado o S3 compatible. Caddy termina TLS en el despliegue Docker.

Los índices y catálogos extensos se paginan en el servidor. Cada paginador vive dentro de un Turbo Frame con parámetros independientes, por lo que navegar páginas hace una solicitud AJAX y reemplaza solo la colección correspondiente.

```text
Hostname registrado → Caddy/TLS → Rails/Puma → TenantResolver → PostgreSQL
                         │       ├→ Active Storage/S3
                         └→ Redis → Sidekiq → SMTP / Web Push
```

No hay microservicios ni un inventario duplicado por paquete. La salida operativa concentra el micro y la capacidad; las ofertas comerciales relacionan paquete, hotel y tarifa con esa salida.

## Límites y módulos

- **Identidad y tenancy:** `User`, `Company`, `CompanyDomain`, `Membership`, roles e invitaciones. La identidad es global; el teléfono comercial público pertenece a cada `Membership`.
- **Comercial:** destinos, alojamientos, paquetes, salidas, ofertas y versiones de tarifa.
- **Reservas:** servicio `Reservations::Confirm`, pasajeros y asignaciones de asiento.
- **Finanzas operativas:** cobros declarados, rendiciones, asignaciones y comisiones.
- **Operación:** rutas, paradas, coordinadores, eventos de embarque y manifiestos.
- **Comunicaciones:** notificaciones internas, preferencias, email y Web Push.

`TenantResolver` clasifica cada request como `tenant`, `platform` o `auth`. En un host de agencia, `Current.company` proviene exclusivamente de un `CompanyDomain` activo y nunca de parámetros ni de la sesión. Recién después se busca una membresía activa de ese usuario para esa empresa. El namespace `platform` solo responde en el hostname global y exige un `PlatformRole`; el callback OAuth solo responde en el hostname central de autenticación.

Cada empresa conserva un `platform_subdomain` permanente. Un dominio `custom` solo puede activarse luego de comprobar el TXT de propiedad, el CNAME técnico y un certificado HTTPS válido. El dominio principal determina enlaces salientes, pero no cambia ningún dato del tenant.

## Integridad y concurrencia

`Reservations::Confirm` abre una transacción, bloquea la salida con `SELECT … FOR UPDATE`, recalcula lugares desde `seat_allocations` activas, valida pago mínimo y recién entonces crea reserva, pasajeros, asientos, pago y comisión. Una clave de idempotencia evita duplicados. Cancelar libera asignaciones dentro de otra transacción.

Las asociaciones tenant críticas tienen dos barreras: validaciones de dominio y claves foráneas compuestas `(id, company_id)` en PostgreSQL. La migración ejecuta un preflight y aborta si encuentra cruces. `bin/rails tenant_integrity:audit` permite revisar una base antes del despliegue y `tenant_integrity:repair_company[tabla,id,asociación]` realiza únicamente una reparación explícita que vuelva a pasar todas las validaciones.

Las tarifas son append-only: una reserva copia precio, gastos, mínimo y condiciones. Las páginas públicas consultan la tarifa vigente y los lugares reales, con polling y ETag de corta duración.

## Seguridad

- OAuth Google centralizado, CSRF, CSP en modo enforcement, rate limiting y autorización por hostname/rol/tenant.
- El login crea una solicitud de diez minutos ligada a un nonce del navegador. El callback central emite un código de dos minutos y un solo uso para el hostname exacto de origen. Las cookies siguen siendo host-only; no se comparte una sesión entre subdominios ni dominios propios.
- DNI, nombre/notas del pasajero y credenciales Push cifrados con Active Record Encryption.
- Comprobantes privados con tipos PDF/JPEG/PNG/WebP y máximo 10 MB.
- Auditoría append-only de operaciones críticas.
- Cola offline de embarque limitada a IDs/estado, persistida en `localStorage` bajo una clave separada por empresa, salida y usuario; no persiste nombres ni DNI. Se conserva ante recargas y errores de red, pero no promete sincronización con la aplicación cerrada.
- Las rutas globales de Active Storage están deshabilitadas. Los comprobantes se descargan mediante controladores que vuelven a autorizar empresa y perfil, con `Cache-Control: private, no-store`.
- Email y Web Push se generan con el dominio principal registrado, revalidan empresa/membresía y no cambian de tenant desde la sesión. Las suscripciones Push quedan ligadas a empresa y hostname de origen.
- Secretos fuera de Git y claves separadas para sesión/cifrado.

## Operación

Web y worker son procesos separados sobre la misma imagen. `db:prepare` se ejecuta únicamente en web al desplegar. `/up` es el health check. PostgreSQL y los objetos deben tener backups externos y pruebas periódicas de restauración.

La configuración y el procedimiento de alta de hosts están en `docs/despliegue-dominios.md`. Caddy recibe una lista explícita de hosts autorizados; no se habilita TLS on-demand irrestricto.

## Turistack Asesor

`AgentWorkspace` pertenece a un único `User`, independientemente de sus `Membership`; durante una invitación conserva el correo autorizado y asigna el propietario después de verificarlo con Google. `AgentSupplier` es privado y no crea empresas globales. No hay sincronización ni permisos implícitos hacia proveedores de Turistack Empresa.

`HostnameRegistration` protege la unicidad entre empresas y agentes. `CompanyDomain` conserva verificación DNS/TLS, dominio principal y recuperación; sus escrituras reservan el hostname transaccionalmente. La finalización operativa agrega la FK `(hostname, company_id)` después del reemplazo de todos los procesos anteriores. Los agentes tienen un único subdominio permanente. El hostname, nunca parámetros del navegador, selecciona el espacio.

`AgentTrip` conserva una identidad pública estable y apunta a revisiones actuales/publicadas de `AgentTripRevision`. Cada revisión pertenece al mismo viaje, proveedor y espacio mediante claves foráneas compuestas. La edición crea una revisión nueva: la web sigue usando la anterior hasta publicación explícita. No existe inventario independiente ni acoplamiento artificial con `Departure`.

`AgentImport` conserva el original privado y produce varios `AgentImportItem`. Estos separan extracción de correcciones (`review_data`) y guardan de manera idempotente el viaje/revisión elegidos. La creación de un proveedor durante la revisión conserva los campos editados. `AgentSearch` persiste consulta, interpretación y filtros; `CatalogQuery` aplica esos filtros sobre PostgreSQL, con búsqueda insensible a acentos mediante `unaccent`.

`AgentAiJob` reclama trabajo con token y lease de cinco minutos bajo bloqueo de workspace. La llamada a Gemini sucede fuera de la transacción. Las respuestas de intentos vencidos se descartan. `RecoverAgentAiJobsJob` recupera tareas pendientes o interrumpidas; solo errores transitorios del proveedor se reintentan automáticamente, hasta tres intentos. `AgentAiExecution` conserva consumo informado, modelo, contrato, duración y resultado, sin contenido del documento ni claves.

El catálogo público usa solo la revisión publicada, fechas vigentes y proveedores activos. Publicar una ficha habilita la imagen de su flyer: se reutilizan los bytes originales para JPG/PNG/WebP y se genera la primera página para PDF con Poppler. El documento fuente se conserva mediante `flyer_source` en la revisión. Las rutas de originales y todas las operaciones privadas se reautorizan. La PWA cachea únicamente `/assets/` e iconos estáticos, con versión de caché por contexto y origen.
