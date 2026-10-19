# Dominio

## Identidad

- `User`: identidad Google única, nombre, email y WhatsApp opcional.
- `Company`: tenant y configuración comercial.
- `Membership`: vincula usuario/empresa; contiene uno o más `MembershipRole`.
- `ResellerAuthorization`: referencia pública y permiso explícito de autoconfirmación.
- `CompanyInvitation`: invitación expirable por email y perfiles.

## Catálogo y operación

- `Destination`, `Accommodation`, `TravelPackage`: contenido reutilizable.
- `Bus`: vehículo y capacidad nominal.
- `Route`/`RouteStage`: recorrido reusable.
- `Departure`: micro y fecha concretos; dueño de la capacidad real.
- `DepartureStop`: copia publicable de parada/horario para una salida.
- `DepartureOffer`: paquete + salida + alojamiento.
- `FareVersion`: precio, gasto, mínimo y promoción vigentes desde una fecha.

Dos ofertas pueden apuntar a una misma salida y consumir el mismo conjunto de `SeatAllocation`. Un hotel nunca determina el inventario del micro.

## Venta y pasajeros

- `PassengerForm` y `PassengerFormSubmission`: captura privada previa, sin asiento.
- `Reservation`: acuerdo comercial y snapshot de tarifa.
- `Passenger`: datos cifrados, parada y alojamiento.
- `SeatAllocation`: asiento lógico activo/liberado.
- `RoomAssignment`: agrupación operativa extensible, sin reglas automáticas todavía.

## Dinero

- `CustomerPayment`: dinero que el pasajero declaró entregar.
- `Remittance`: dinero que el revendedor declaró enviar.
- `RemittanceAllocation`: cuánto de una rendición corresponde a cada cobro.
- `CommissionRule`: porcentaje o fijo vigente para un revendedor.
- `CommissionEntry`: importe congelado de una reserva atribuida, con estados devengado/pagable/liquidado.

Todos los importes son enteros en centavos ARS. Un comprobante nunca verifica dinero por sí solo.

## Operación y comunicación

- `DepartureAssignment`: salida visible para un coordinador.
- `BoardingEvent`: comando idempotente con estado, autor y hora.
- `Notification`, `NotificationPreference`, `PushSubscription`: comunicación dirigida.
- `AuditEvent`: bitácora inmutable con actor, tenant, request e IP.
