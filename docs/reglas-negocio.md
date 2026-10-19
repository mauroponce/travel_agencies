# Reglas de negocio

1. La capacidad pertenece a una salida, no al paquete, hotel ni oferta.
2. La disponibilidad es capacidad menos asignaciones activas; nunca un contador editable.
3. Confirmar bloquea la salida, vuelve a verificar cupos y exige el mínimo de la tarifa vigente.
4. Una reserva conserva su precio/condiciones aunque luego cambie la tarifa pública.
5. El formulario privado no confirma, no cobra y no ocupa lugares.
6. Una seña declarada en efectivo puede autoconfirmar solo si la empresa autorizó expresamente al revendedor.
7. Una rendición pendiente no libera una reserva confirmada.
8. Verificar una rendición es idempotente y actualiza el estado financiero de sus cobros sin duplicarlos.
9. Una venta directa no genera comisión. Una venta atribuida usa la regla vigente y guarda su snapshot.
10. Abrir un enlace `ref` no genera comisión; la atribución ocurre al registrar la reserva.
11. Un revendedor ve únicamente sus reservas, pasajeros, cobros, rendiciones y comisiones.
12. Un coordinador solo ve salidas asignadas y no ve información financiera.
13. Cambiar el selector visual no otorga roles: el servidor valida membresía activa y perfil efectivo.
14. Eventos de embarque usan un UUID de comando y versión base para deduplicar y detectar conflictos.
15. DNI se muestra enmascarado salvo en contextos operativos expresamente autorizados.

## Estados separados

- Reserva: `requested`, `confirmed`, `cancelled`.
- Pago: `declared`, `partially_remitted`, `verified`, `voided`.
- Rendición: `declared`, `verified`, `rejected`.
- Comisión: `accrued`, `payable`, `settled`.
- Embarque: `pending`, `boarded`, `absent`, `incident`.
