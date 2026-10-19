# Plan de implementación

Este plan vive en el repositorio deliberadamente; no se guardan artefactos de dev-skills en la configuración global de Codex.

## Decisiones confirmadas

- Monolito modular Rails 8.1, PostgreSQL, Redis, Sidekiq y Hotwire/Tailwind.
- Autenticación únicamente con Google; alta propia inmediata e invitaciones por email.
- Actualización pública mediante polling/ETag y Web Push, sin WebSockets.
- Docker local y despliegue manual por Bash/SSH en Hetzner.
- Dinero entero en centavos, UUID, aislamiento por empresa y datos personales cifrados.

El cambio respecto del stack preferido Laravel/Vue responde a la decisión tomada durante el descubrimiento: Rails/Hotwire reduce superficie operativa y mantiene un monolito server-rendered apto para el alcance. PostgreSQL, Tailwind, PWA, Redis, colas, Web Push y S3 compatible se conservan.

## Hitos

1. **Fundación:** proyecto, OAuth Google, tenants, roles, diseño responsive, seeders y seguridad base.
2. **Comercial:** catálogos, paquetes, salidas, ofertas, historial de tarifa, ficha pública y referencia del revendedor.
3. **Reservas y pagos:** confirmación transaccional, cupos, formularios privados, pagos, rendiciones y comisiones congeladas.
4. **Operación:** hoja de ruta, coordinadores, embarque idempotente/offline y manifiestos CSV/PDF.
5. **PWA y cierre:** manifest, service worker, Push/email, auditoría, Docker, CI, pruebas y documentación.

## Verificación por corte

- El esquema debe migrar desde una base vacía.
- `zeitwerk:check`, pruebas, RuboCop, Brakeman y auditoría de dependencias.
- Smoke tests de las rutas principales y comprobación manual desktop/móvil.
- Despliegue ensayado con imagen inmutable y health check antes del primer uso real.
