# Estado de implementación

Actualizado: 19 de octubre de 2026.

## Operativo y probado

- Google OAuth, onboarding, invitaciones y selector seguro de empresa/perfil.
- Aislamiento multiempresa y alcance privado por revendedor/coordinador.
- Catálogos base, paquetes, salidas, ofertas, publicación y ficha pública dinámica.
- Versionado de precios, Super Sale, contacto oficial/personalizado y disponibilidad compartida.
- Reserva multi-pasajero transaccional, pago mínimo, idempotencia, cancelación y cupos.
- Formularios privados cifrados y expirables sin ocupación de lugar.
- Cobros parciales, comprobantes, rendiciones agrupadas/verificadas y comisiones congeladas.
- Hoja de ruta, embarque con deduplicación/conflictos y manifiestos CSV/PDF.
- Centro interno, email asíncrono, Web Push opt-in, PWA y polling público.
- Datos demo, Docker, CI, Caddy/Hetzner y documentación.

La suite actual contiene 15 pruebas Rails con 58 aserciones y 4 escenarios Playwright en desktop/móvil. El esquema migra desde cero y `zeitwerk:check` pasa.

## Parcial

- El CRUD visual de rutas crea rutas, pero la edición detallada de etapas se realiza todavía por consola/API; las rutas demo ya tienen etapas completas.
- Preferencias de notificación existen en datos y son respetadas por los canales, pero aún no tienen pantalla editable.
- Alojamiento por pasajero funciona; la interfaz completa para armar habitaciones sigue siendo manual.
- La cola offline de embarque conserva solo comandos no sensibles durante la sesión del navegador; no ofrece sincronización en segundo plano con la app cerrada.
- Las imágenes de paquetes/hoteles están modeladas con Active Storage, pero el formulario visual de carga múltiple requiere pulido.
- Los estados de comisión están preparados, pero la liquidación se mantiene deliberadamente sin acción hasta validar políticas.

## Pendiente antes de producción real

- Completar validación visual manual en dispositivos físicos iOS/Android y con usuarios del sector.
- Ensayar despliegue en el servidor Hetzner definitivo, restauración de backups y rotación de secretos.
- Configurar credenciales reales Google, SMTP, VAPID y S3; verificar DNS/TLS.
- Validación legal de privacidad/retención y capacitación operativa.
- Resolver las reglas comerciales de `docs/decisiones-pendientes.md`.
