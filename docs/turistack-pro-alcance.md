# Alcance comercial de Turistack Pro

MVP para el asesor de viajes independiente, USD 19/mes, activación/renovación manual sin débito automático. Una identidad Google puede tener un negocio personal y varias membresías empresariales. Las membresías no requieren Pro y nunca se cancelan por vencimiento del espacio personal.

Incluye proveedores privados; flyers/PDF con extracción Gemini dentro de cuota y revisión humana; catálogo versionado; web personal en `/:agent_slug` y `/:agent_slug/viajes/:slug`; compartir enlace/flyer y consulta WhatsApp sin registro del visitante; agenda manual de clientes y notas privadas/exportables. Navegación: Resumen, Mis viajes, Importar, Mis proveedores, Mis clientes, Mi web y Mi plan. El buscador IA existente es una herramienta secundaria.

Nueva alta: una prueba de 14 días, no reiniciable por login/onboarding. Pilotos: transición explícita de 30 días al migrar, sin conversión automática a clientes pagos. Vencimiento: lectura/exportación privada y reactivación; datos intactos, sin escrituras, IA ni publicación pública. Suspensión administrativa separada. Reactivar no publica borradores. Configuración y operación exactas en la [guía de lanzamiento](turistack-revendedor-lanzamiento.md).

La unidad de IA es un intento de búsqueda/imagen o una página PDF por intento. Presupuesto inicial: 200 unidades por mes calendario local; intentos fallidos/reintentos consumen. PDF: hasta 10 páginas y 10 MB. Los archivos y correcciones se conservan al agotarse cuota. Permisos y reservas de consumo se aplican en servidor bajo locks del espacio.

No incluye pagos de viajeros, checkout, Mercado Pago, reservas automáticas, disponibilidad confirmada, marketplace, scraping, sincronización ni republicación empresarial, lectura/envío automático de WhatsApp, campañas, módulos nuevos de pasajeros/butacas/comisiones/liquidaciones, plan de agencias ni constructor de páginas. Las operaciones anteriores de agencias siguen disponibles con sus permisos, fuera de Pro.

Invariantes para futuras tareas: no enlazar AgentSupplier a Company por coincidencias; no compartir clientes/notas/ofertas entre espacios; mantener revisiones públicas separadas; verificar fechas y permisos en cada operación/job; exportaciones privadas autenticadas y CSV sin fórmulas; no ampliar cookies a todos los subdominios; no revocar membresías por causas comerciales personales; conservar slugs, IDs, archivos y claves de cifrado.
