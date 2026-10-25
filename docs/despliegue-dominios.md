# Despliegue, staging, dominios y recuperación

## Configuración de referencia

Producción usa:

```text
PLATFORM_NAME=Turistack
PLATFORM_BASE_DOMAIN=turistack.com
PLATFORM_HOST=turistack.com
AUTH_HOST=auth.turistack.com
CUSTOM_DOMAIN_CNAME_TARGET=tenants.turistack.com
APP_PROTOCOL=https
CADDY_SITE_ADDRESSES=turistack.com, auth.turistack.com, agencia.turistack.com
```

Staging debe usar otro dominio o subdominio, otra base, otros volúmenes, otro OAuth client y otras claves. `compose.staging.yml` fija el proyecto `turistack-staging`; `compose.production.yml`, `turistack-production`. No copie `.env`, volúmenes, buckets ni backups entre ellos.

Los ejemplos completos están en `deploy/env.staging.example` y `deploy/env.production.example`. Guarde los archivos reales como `.env.staging`/`.env.production`, modo `0600`, fuera de Git. Use exclusivamente `DATABASE_URL` o `DB_*`; los Compose entregados usan `DB_*`. HTTPS es obligatorio y no depende de una bandera opcional.

## Alta inicial en Hetzner

1. Crear un usuario de despliegue sin contraseña, acceso por llave y permisos limitados a Docker y `/opt/turistack-<entorno>`.
2. Instalar Docker Engine y Compose; habilitar firewall solamente para SSH, 80 y 443.
3. Copiar `compose.<entorno>.yml`, `deploy/Caddyfile` y el `.env.<entorno>` al directorio del entorno. Autenticar el registry.
4. Crear A/AAAA para plataforma, auth, subdominios de agencia y el destino CNAME técnico.
5. Registrar en Google exactamente `https://AUTH_HOST/auth/google_oauth2/callback` usando un cliente exclusivo del entorno.
6. Validar sin arrancar:

   ```bash
   ENV_FILE=.env.staging docker compose --env-file .env.staging -f compose.staging.yml config --quiet
   ```

7. Desplegar un tag inmutable con `bin/deploy-hetzner`. El servicio `migrate` es el único que ejecuta `db:migrate`; no carga seeds, y web/worker rechazan `RUN_MIGRATIONS=true`.
8. Verificar `/up`, logs, Sidekiq, envío de correo, OAuth, Active Storage y las rutas críticas. No incorporar agencias reales hasta completar staging.

Caddy recibe solamente los hosts listados y persiste certificados en `caddy_data`. `reverse_proxy` informa el protocolo original y Rails usa `assume_ssl`; las cookies siguen siendo host-only. No se habilita TLS on-demand para hostnames arbitrarios.

## Staging reproducible

Crear claves propias, copiar el ejemplo y desplegar. Luego provisionar dos agencias ficticias:

```bash
ENV_FILE=.env.staging docker compose --env-file .env.staging -f compose.staging.yml run --rm web bin/rails staging:provision
```

La tarea exige `RAILS_ENV=staging` y `ENABLE_STAGING_DATA=true`. Crea `Agencia Uno Staging` con catálogo y operación demo, `Agencia Dos Staging` vacía e invitaciones de administrador para los correos configurados. Es idempotente respecto de empresas e invitaciones pendientes. El operador global se obtiene al autenticar un correo de `PLATFORM_ADMIN_GOOGLE_EMAILS`.

### Prueba extremo a extremo

1. Entrar como operador en `PLATFORM_HOST`; crear manualmente una tercera agencia descartable para probar el alta y luego suspenderla.
2. Confirmar la invitación del administrador de Agencia Uno iniciando sesión con Google.
3. Invitar cuentas distintas como revendedor y coordinador; autenticar cada una.
4. Como admin, crear/publicar un viaje y anotar el cupo inicial.
5. Como revendedor, confirmar una reserva; comprobar una reducción exacta del cupo y que una repetición no duplique la operación.
6. Registrar un pago, declarar la rendición y verificarla como admin.
7. Asignar el coordinador; abrir Operación, marcar embarque, probar modo offline y sincronización.
8. Instalar la PWA, probar manifest/service worker y notificaciones con VAPID de staging.
9. Abrir Agencia Dos con otro usuario y comprobar que no aparecen pasajeros, reservas, pagos ni viajes de Agencia Uno.
10. Con una sesión de Agencia Uno, navegar al hostname de Agencia Dos: debe solicitar autenticación local y nunca reutilizar la cookie.
11. Registrar un dominio personalizado de prueba, crear TXT/CNAME, agregarlo explícitamente a `CADDY_SITE_ADDRESSES`, recargar Caddy, verificar TLS y activarlo.
12. Retirar temporalmente el dominio propio de la prueba y confirmar acceso por el subdominio permanente.

Los tests Rails/Playwright automatizan aislamiento, OAuth simulado, cupos, pagos/rendiciones, coordinador, embarque y PWA. DNS público, certificados ACME, Google real, Push real y entrega SMTP requieren infraestructura externa y verificación manual.

## Alta de una agencia y sus hostnames

1. El operador crea la empresa e invitación; Rails crea un único subdominio permanente.
2. Agregar A/AAAA o CNAME del subdominio y sumarlo a `CADDY_SITE_ADDRESSES`; ejecutar `caddy validate`/recargar y comprobar HTTPS.
3. El administrador entra por ese hostname; OAuth viaja a `AUTH_HOST` y vuelve con un código efímero al mismo origen.
4. Para un dominio propio, registrar el hostname en plataforma, publicar el TXT solicitado y un CNAME a `CUSTOM_DOMAIN_CNAME_TARGET`.
5. Agregar el hostname a Caddy antes de verificar HTTPS. Solo activar luego de que TXT, CNAME y TLS pasen.
6. Hacerlo principal cambia enlaces nuevos, no datos. Nunca eliminar el subdominio permanente de recuperación.

Rails Host Authorization admite hosts centrales, subdominios sintácticamente válidos y dominios propios activos; `TenantResolver` además exige un registro activo y una empresa no suspendida.

## Auditoría y cambio del dominio base

Ejecutar regularmente:

```bash
bin/rails company_domains:audit
STRICT_INFRASTRUCTURE=true bin/rails company_domains:audit
bin/rails tenant_integrity:audit
```

La auditoría detecta dominio base anterior, duplicados case-insensitive, principales inconsistentes, personalizados inválidos/CNAME obsoleto, empresas sin subdominio permanente y hosts activos ausentes de Caddy. El modo estricto convierte desalineaciones de infraestructura en error.

Nunca se reescriben dominios por cambiar una variable. Para migrar `old.example` a `new.example`:

1. Realizar backup y ventana de mantenimiento; esperar a que terminen los intercambios OAuth.
2. Preparar DNS, Caddy, OAuth y rollback para ambos dominios.
3. Planificar sin cambios: `bin/rails 'company_domains:base_migration:plan[old.example,new.example]'`.
4. Configurar `PLATFORM_BASE_DOMAIN=new.example` y valores relacionados.
5. Aplicar en una transacción: `CONFIRM='old.example->new.example' bin/rails 'company_domains:base_migration:apply[old.example,new.example]'`.
6. Auditar y probar aislamiento/OAuth. Conservar DNS anterior durante la ventana.
7. Para rollback, restaurar primero la configuración anterior y ejecutar `CONFIRM='new.example->old.example' bin/rails 'company_domains:base_migration:rollback[new.example,old.example]'`.

La operación aborta ante destinos duplicados, registros fuera del dominio origen o autenticaciones vigentes. No modifica migraciones históricas ni datos comerciales.

## Backups y restauración

Respaldar antes de cada despliegue con migraciones y además mediante una política programada con retención y copia fuera del servidor:

```bash
DEPLOY_ENVIRONMENT=staging \
ENV_FILE=.env.staging \
BACKUP_ROOT=/srv/backups/turistack \
bin/backup-turistack
```

El backup contiene `pg_dump` en formato custom, el volumen de Active Storage, checksums y manifiesto. Si `ACTIVE_STORAGE_SERVICE=s3`, reemplace el tar local por versionado/replicación del bucket y pruebe su restauración. También deben conservarse de forma segura las claves cifrantes; un dump sin `ACTIVE_RECORD_ENCRYPTION_KEY` no basta.

Probar restauraciones periódicamente en staging. La restauración reemplaza objetos de la base seleccionada, por lo que exige confirmación explícita y los servicios web/worker se detienen:

```bash
DEPLOY_ENVIRONMENT=staging \
ENV_FILE=.env.staging \
RESTORE_CONFIRM=restore-staging \
bin/restore-turistack /srv/backups/turistack/staging/AAAAMMDDTHHMMSSZ
```

Antes de una restauración productiva, sacar un backup del estado actual y validar que el path/manifest indiquen `production`. El script no elimina archivos extra del volumen antes de superponer el backup; si se requiere una restauración exacta, usar un volumen nuevo y cambiarlo solamente después de validarlo.

## Rollback de aplicación

1. Conservar el tag anterior y el resultado del backup previo.
2. Si la migración es compatible hacia adelante, volver a ejecutar `bin/deploy-hetzner` con el tag anterior.
3. No ejecutar `db:rollback` automáticamente. Si el código anterior no tolera el esquema nuevo, corregir hacia adelante o restaurar base/archivos en una ventana aprobada.
4. Verificar revisión, `/up`, web, worker, cola, OAuth y recorridos críticos; observar logs antes de cerrar el incidente.

## Checklist productiva

- [ ] Staging completó el recorrido E2E con dos agencias y aislamiento negativo.
- [ ] Imagen identificada por digest/tag inmutable, revisada y con todas las pruebas verdes.
- [ ] `.env.production` modo `0600`, sin secretos de staging/desarrollo y fuera de Git.
- [ ] Base/usuario/volumen PostgreSQL existentes coinciden con `POSTGRES_*`; no se recrearon volúmenes.
- [ ] Backup de PostgreSQL/adjuntos restaurado con éxito en un entorno descartable.
- [ ] DNS, Caddy, almacenamiento persistente de certificados y renovación TLS verificados.
- [ ] OAuth callback exacto, cookies Secure/host-only y rechazo de hosts desconocidos comprobados.
- [ ] SMTP, S3/local storage, VAPID, Redis, Sidekiq y tareas periódicas comprobados.
- [ ] `company_domains:audit` y `tenant_integrity:audit` sin errores.
- [ ] Migraciones revisadas por compatibilidad; migrador único y rollback/forward-fix acordado.
- [ ] Monitoreo de salud, logs, espacio en disco, backups y alertas operativo.
- [ ] Alta del primer cliente se realiza solo después de aprobar esta lista.
