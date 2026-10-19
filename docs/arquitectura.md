# Arquitectura

## Vista general

NexoViajes es un monolito Rails con HTML server-rendered, Turbo y Stimulus. PostgreSQL es la fuente de verdad; Redis soporta Sidekiq, caché y tareas programadas. Active Storage conserva comprobantes e imágenes en disco privado o S3 compatible. Caddy termina TLS en el despliegue Docker.

```text
Navegador/PWA → Caddy → Rails/Puma → PostgreSQL
                         │       ├→ Active Storage/S3
                         └→ Redis → Sidekiq → SMTP / Web Push
```

No hay microservicios ni un inventario duplicado por paquete. La salida operativa concentra el micro y la capacidad; las ofertas comerciales relacionan paquete, hotel y tarifa con esa salida.

## Límites y módulos

- **Identidad y tenancy:** `User`, `Company`, `Membership`, roles e invitaciones.
- **Comercial:** destinos, alojamientos, paquetes, salidas, ofertas y versiones de tarifa.
- **Reservas:** servicio `Reservations::Confirm`, pasajeros y asignaciones de asiento.
- **Finanzas operativas:** cobros declarados, rendiciones, asignaciones y comisiones.
- **Operación:** rutas, paradas, coordinadores, eventos de embarque y manifiestos.
- **Comunicaciones:** notificaciones internas, preferencias, email y Web Push.

Los controladores siempre parten de `current_company` y, para revendedores/coordinadores, agregan el alcance del miembro actual. IDs UUID no reemplazan la autorización: solo reducen enumeración accidental.

## Integridad y concurrencia

`Reservations::Confirm` abre una transacción, bloquea la salida con `SELECT … FOR UPDATE`, recalcula lugares desde `seat_allocations` activas, valida pago mínimo y recién entonces crea reserva, pasajeros, asientos, pago y comisión. Una clave de idempotencia evita duplicados. Cancelar libera asignaciones dentro de otra transacción.

Las tarifas son append-only: una reserva copia precio, gastos, mínimo y condiciones. Las páginas públicas consultan la tarifa vigente y los lugares reales, con polling y ETag de corta duración.

## Seguridad

- OAuth Google, CSRF, CSP Rails, rate limiting y autorización por rol/tenant.
- DNI, nombre/notas del pasajero y credenciales Push cifrados con Active Record Encryption.
- Comprobantes privados con tipos PDF/JPEG/PNG/WebP y máximo 10 MB.
- Auditoría append-only de operaciones críticas.
- Cola offline de embarque limitada a IDs/estado, guardada solo en `sessionStorage`; no persiste nombres ni DNI.
- Secretos fuera de Git y claves separadas para sesión/cifrado.

## Operación

Web y worker son procesos separados sobre la misma imagen. `db:prepare` se ejecuta únicamente en web al desplegar. `/up` es el health check. PostgreSQL y los objetos deben tener backups externos y pruebas periódicas de restauración.
