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
13. El hostname determina la empresa. El selector visual solo cambia entre roles de la membresía actual y nunca entre agencias.
14. Eventos de embarque usan un UUID de comando y versión base para deduplicar y detectar conflictos.
15. DNI se muestra enmascarado salvo en contextos operativos expresamente autorizados.
16. Una empresa suspendida no puede crear contexto, vender, rendir, embarcar, publicar formularios ni despachar notificaciones.
17. Solo un pasajero de reserva confirmada con `SeatAllocation` activa puede integrar manifiestos o embarque.
18. El contacto del revendedor es una configuración por membresía; ningún administrador de agencia modifica la identidad global del usuario.
19. Las métricas usan el conjunto completo autorizado; los límites de “recientes” se aplican únicamente a listados.
20. Una solicitud solo pasa a confirmada y una confirmada a cancelada. Los reintentos sobre el estado final son idempotentes en los servicios correspondientes.
21. Solo el operador global crea agencias, asigna subdominios, invita al primer administrador, suspende empresas y administra dominios propios.
22. Cada agencia conserva un subdominio de plataforma activo como recuperación, aun cuando otro dominio sea principal.
23. Un dominio propio requiere propiedad TXT, CNAME y HTTPS verificados antes de activarse. Registrar un hostname no lo autoriza automáticamente.
24. Google OAuth solo se inicia y completa en el host central. El retorno usa el hostname persistido, no un parámetro libre ni el header `Host` para generar destinos.
25. Reverificar un dominio activo nunca lo retira automáticamente de servicio: un fallo se informa y audita, y la desactivación queda como acción explícita del operador.
26. Los cambios de dominio principal se serializan por empresa; la última operación que obtiene el bloqueo pasa a ser principal y siempre queda un único dominio principal.

## Estados separados

- Reserva: `requested`, `confirmed`, `cancelled`.
- Pago: `declared`, `partially_remitted`, `verified`, `voided`.
- Rendición: `declared`, `verified`, `rejected`.
- Comisión: `accrued`, `payable`, `settled`.
- Embarque: `pending`, `boarded`, `absent`, `incident`.
