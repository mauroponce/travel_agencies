# Despliegue de subdominios y dominios propios

## Variables obligatorias

En producción configurar:

```text
PLATFORM_BASE_DOMAIN=dominio-base.example
PLATFORM_HOST=platform.dominio-base.example
AUTH_HOST=auth.dominio-base.example
APP_PROTOCOL=https
CUSTOM_DOMAIN_CNAME_TARGET=tenants.dominio-base.example
CADDY_SITE_ADDRESSES=platform.dominio-base.example, auth.dominio-base.example, agencia.dominio-base.example
PLATFORM_NAME=Nombre provisional de la plataforma
```

`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, SMTP, VAPID y las claves Rails continúan siendo secretos. No configurar un `domain:` común para la cookie de sesión: la cookie debe permanecer host-only.

## DNS inicial

1. Crear registros A/AAAA para `PLATFORM_HOST`, `AUTH_HOST` y el hostname técnico `CUSTOM_DOMAIN_CNAME_TARGET` hacia Caddy.
2. Crear cada subdominio de agencia mediante A/AAAA o CNAME hacia el hostname técnico.
3. Agregar solamente esos hosts a `CADDY_SITE_ADDRESSES` y recargar Caddy. La configuración entregada no usa un wildcard ni TLS on-demand, por lo que un hostname arbitrario no puede provocar la emisión de un certificado.
4. Registrar en Google exactamente `https://AUTH_HOST/auth/google_oauth2/callback`. No registrar callbacks por agencia.

Rails Host Authorization admite los hosts internos configurados, los subdominios sintácticamente válidos del dominio base y dominios propios que ya estén activos en `company_domains`. Aun cuando Host Authorization admita un subdominio base, `TenantResolver` responde 404 si no existe un registro activo.

## Alta de una agencia

1. El operador global crea la empresa, su subdominio y la invitación del primer administrador.
2. Se agrega el subdominio a DNS y a `CADDY_SITE_ADDRESSES`; luego se recarga Caddy y se comprueba HTTPS.
3. El administrador ingresa por ese hostname. OAuth viaja al host central y vuelve mediante un código efímero al mismo origen.

El subdominio de plataforma no se elimina cuando se configura un dominio propio y sirve como recuperación.

## Dominio propio

1. El operador registra el hostname desde el panel global. El sistema muestra una única vez el valor TXT de propiedad.
2. El cliente crea:
   - TXT en `_tenant-verification.<hostname>` con el valor indicado.
   - CNAME de `<hostname>` hacia `CUSTOM_DOMAIN_CNAME_TARGET`.
3. Antes de verificar HTTPS, el operador agrega explícitamente el hostname a `CADDY_SITE_ADDRESSES` y recarga Caddy para obtener el certificado.
4. La acción **Verificar** comprueba TXT, CNAME y la negociación HTTPS. Solo entonces puede usarse **Activar**.
5. **Hacer principal** cambia los enlaces nuevos de fichas, formularios, invitaciones, emails y Push. No mueve ni modifica datos.

Si el dominio se deshabilita, deja de resolver inmediatamente en Rails y el subdominio permanente vuelve a ser principal si no quedaba otro dominio activo.

La acción **Reverificar** también está disponible para dominios activos. Si durante esa comprobación falla temporalmente DNS o TLS, la aplicación conserva el estado operativo y el dominio principal; muestra y audita el fallo para que el operador decida si corresponde deshabilitarlo. Una reverificación exitosa actualiza la fecha de última verificación. Los cambios simultáneos de dominio principal se serializan por empresa y mantienen la unicidad respaldada por el índice parcial de PostgreSQL.

## Despliegue y rollback

La migración crea los subdominios permanentes para empresas existentes usando su `slug`. Antes de desplegar, revisar que ningún slug use nombres reservados (`www`, `admin`, `auth`, `api`, `platform`, entre otros) y configurar `PLATFORM_BASE_DOMAIN` con el valor definitivo de esa instalación.

Durante un rollback de aplicación no deben eliminarse `company_domains` ni los códigos de autenticación. Los códigos vencen solos y pueden purgarse posteriormente con una tarea de mantenimiento. Para revocar un dominio inmediatamente, deshabilitarlo en plataforma y retirarlo de Caddy/DNS.
