# Estado de implementación

## Dashboard administrativo Cadence

- El panel privado usa el sistema visual Cadence del mockup, con componentes server-rendered y navegación Rails real.
- Los siete indicadores se calculan sobre el alcance completo autorizado; los listados recientes mantienen límites explícitos.
- La serie histórica ficticia del prototipo fue reemplazada por una visualización de ocupación real de próximas salidas. Cada barra representa `occupied_seats / capacity` de una `Departure`, por lo que ofertas que comparten micro no duplican inventario. Una capacidad heredada en cero se representa como 0% sin dividir por cero.
- Los filtros de salidas se aplican sobre el conjunto tenant-scoped completo antes del límite visible. No se incorporó el buscador simulado del HTML.

Actualizado: 20 de octubre de 2026.

## Operativo y probado

- Google OAuth central, alta exclusivamente global, invitaciones y selector de perfil dentro del tenant resuelto por hostname.
- Aislamiento multiempresa y alcance privado por revendedor/coordinador.
- Catálogos base, paquetes, salidas, ofertas, publicación y ficha pública dinámica.
- Versionado de precios, Super Sale, contacto oficial/personalizado y disponibilidad compartida.
- Reserva multi-pasajero transaccional, pago mínimo, idempotencia, cancelación y cupos.
- Formularios privados cifrados y expirables sin ocupación de lugar.
- Cobros parciales, comprobantes, rendiciones agrupadas/verificadas y comisiones congeladas.
- Hoja de ruta, embarque con deduplicación/conflictos y manifiestos CSV/PDF.
- Centro interno, email asíncrono, Web Push opt-in, PWA y polling público.
- Datos demo, Docker, CI, Caddy/Hetzner y documentación.
- Confirmación protegida por estado de oferta/salida, con bloqueos compartidos con la edición de oferta y capacidad.
- Manifiestos, hoja de ruta y sincronización de embarque incluyen exclusivamente pasajeros de reservas confirmadas; las solicitudes y cancelaciones no pueden registrar embarques.
- Rendiciones parciales sucesivas y concurrentes, con comprobante, campos no seleccionados ignorados y tope transaccional por cobro.
- Formularios recibidos con vista privada y conversión idempotente a solicitud sin ocupar cupos.
- Confirmación posterior de una solicitud sobre la misma reserva y los mismos pasajeros, con seña declarada, tarifa vigente, autorización, auditoría y asignación atómica de cupos.
- Horario editable por parada de salida e importes de interfaz expresados en pesos argentinos.
- Empresas suspendidas excluidas de contextos, operaciones públicas, servicios y notificaciones; operador global separado de administradores tenant.
- Claves foráneas tenant compuestas para asociaciones críticas, con auditoría y reparación explícita previa a migración.
- Contacto comercial por agencia en `Membership`, con backfill desde el teléfono global heredado.
- Ofertas, reglas de comisión, notificaciones, comprobantes y métricas cerrados por empresa y perfil.
- Cola de embarque persistente y aislada por empresa/salida/usuario, con estados pendiente, error y conflicto y recuperación ante fallas de red.
- CSP activa, parámetros personales filtrados y comprobantes servidos solo por rutas autorizadas.
- Operador global con alta/suspensión de empresas y administración de dominios desde interfaz.
- `CompanyDomain` con subdominio permanente, dominio propio, unicidad global, dominio principal y verificación TXT/CNAME/HTTPS.
- Reverificación segura de dominios activos y cambio de principal serializado por empresa, sin perder el subdominio permanente de recuperación.
- `TenantResolver` obligatorio en rutas privadas y públicas; hosts desconocidos, deshabilitados o suspendidos no resuelven datos.
- OAuth central con solicitud ligada al navegador, retorno registrado, código de dos minutos, consumo atómico y protección contra replay/open redirect.
- Cookies host-only, URLs salientes desde dominios persistidos, PWA/caché por tenant y Push asociado a empresa/origen.

La suite actual contiene 81 pruebas Rails con 456 aserciones y cubre además hosts desconocidos, dominios duplicados/reservados, dominios propios, reverificación segura, concurrencia al cambiar el dominio principal, recuperación por subdominio, usuarios multiagencia, cookies por host, cruces de slugs, OAuth de retorno, invitaciones, códigos vencidos/reutilizados y el dashboard tenant-scoped. Playwright ejecuta 4 recorridos en desktop y mobile (8 ejecuciones), incluido el dashboard administrativo a 390 px.

## Parcial

- El CRUD visual de rutas crea rutas, pero la edición detallada de etapas se realiza todavía por consola/API; las rutas demo ya tienen etapas completas.
- Preferencias de notificación existen en datos y son respetadas por los canales, pero aún no tienen pantalla editable.
- Alojamiento por pasajero funciona; la interfaz completa para armar habitaciones sigue siendo manual.
- La cola offline de embarque conserva comandos no sensibles entre recargas; no ofrece sincronización en segundo plano con la app cerrada y requiere validación adicional en Safari/iOS real.
- Las imágenes de paquetes/hoteles están modeladas con Active Storage, pero el formulario visual de carga múltiple requiere pulido.
- Los estados de comisión están preparados, pero la liquidación se mantiene deliberadamente sin acción hasta validar políticas.
- Branding usa nombre y contacto de la empresa y dispone de un adjunto `logo` protegido; no se implementó todavía un editor avanzado de logo/tema.

## Pendiente antes de producción real

- Completar validación visual manual en dispositivos físicos iOS/Android y con usuarios del sector.
- Ensayar despliegue en el servidor Hetzner definitivo, restauración de backups y rotación de secretos.
- Configurar credenciales reales Google, SMTP, VAPID y S3; aplicar el runbook DNS/TLS de `docs/despliegue-dominios.md`.
- Validación legal de privacidad/retención y capacitación operativa.
- Resolver las reglas comerciales de `docs/decisiones-pendientes.md`.
- Ejecutar `tenant_integrity:audit` sobre una copia reciente de producción antes de aplicar las restricciones compuestas.
