# Decisiones pendientes

Estas definiciones requieren validación con empresas turísticas. El sistema evita automatizaciones irreversibles hasta resolverlas.

- Penalidades, reintegros y efecto de una cancelación sobre cobros y comisiones.
- Momento exacto en que una comisión pasa de devengada a pagable y de pagable a liquidada.
- Límites monetarios o temporales de confianza por revendedor, además del permiso binario actual.
- Vencimiento de solicitudes/reservas incompletas y política de liberación automática.
- Reemplazos extraordinarios de hotel, micro, ruta o parada una vez vendidos.
- Reglas de cupo y composición de habitaciones; hoy la asignación es manual.
- Tratamiento contable/impositivo, conciliación bancaria y emisión fiscal (fuera del alcance actual).
- Retención legal y eliminación de DNI, comprobantes, auditoría y colas offline.
- Proveedor SMTP/S3 definitivo, política de backups, RPO/RTO y región de datos.
- Estrategia de recuperación de cuenta: Google es el único ingreso y no hay contraseña local.
- Proveedor DNS y estrategia definitiva de certificados para escalar más allá del alta manual inicial (lista explícita en Caddy, wildcard administrado o TLS on-demand con endpoint `ask` autenticado).
- Alcance visual del branding por agencia: logo, paleta, favicon y plantillas de email.

## PostgreSQL Row-Level Security

No se implementa RLS en esta etapa. Aporta una segunda barrera valiosa, pero activarla correctamente exige fijar el tenant con `SET LOCAL` dentro de cada transacción, cubrir conexiones reutilizadas por Puma y Sidekiq, definir bypass controlado para el operador global y migraciones, y comprobar Active Storage, consola y jobs periódicos. Un `SET` persistente sobre el pool podría filtrar o bloquear datos bajo el tenant equivocado.

Para el piloto se mantiene autorización explícita en Rails más claves foráneas compuestas y auditoría de integridad. Se recomienda reevaluar RLS después de instrumentar consultas sin tenant y diseñar una prueba de concepto en staging que incluya jobs, reintentos, tareas administrativas y conexiones pooled; nunca debe reemplazar la autorización de aplicación.
