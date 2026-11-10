# Contratos de la API de hogares y membresías (`/home/*`)

Contrato de las 15 rutas `/home/*` de la Edge Function `api` (tarjeta 1.10 de `HOMITA_FUNDATIONS.md:201`). Pensado para los clientes nuevos (iOS 1.11-1.14) y para 1.15 (invitaciones). Es documentación: no cambia la Edge, las migraciones ni las 43 rutas legacy (D-008).

## Alcance y fuentes

- **Fuente.** No hay oráculo PHP para `/home/*` (`supabase/functions/api/usecases/homes.ts:2`). El contrato es el código de la Edge (`index.ts`, `usecases/homes.ts`, `_shared/errors.ts`, `_shared/home.ts`), las migraciones 0012 a 0021 y los casos de `scripts/supabase/contract_check.py`. Cada código HTTP y mensaje de este documento sale de ahí; donde no hay caso de contrato se indica "sin caso".
- **Verificación.** `contract_check.py` completo contra la Edge local: 385/385 casos, 43/43 rutas legacy, 15/15 rutas home, mínimo 3 casos por ruta home. El total sube de 351 a 385 con el bloque 1.10 (15 casos 401, 15 casos `Invalid home` y 4 específicos).
- **Invitaciones (Q1 a).** El contrato de invitaciones se documenta al final como **diseñado, no implementado**. La implementación queda en 1.15 (`HOMITA_FUNDATIONS.md:221`), con la migración `0022` (libre: la última existente es `0021`). No hay rutas `invitation` en la Edge.
- **Idioma de los errores.** Los mensajes son inglés, exactos y sensibles a mayúsculas. Los clientes pueden depender del texto.

## Convenciones

### Autenticación

Todas las rutas exigen `Authorization: Bearer <token>`. Sin cabecera o con token inválido: `401 {"error":"Unauthorized"}` (`index.ts:156,159`; `errors.ts:62`). Se resuelve en el dispatcher, antes del handler y sin tocar datos.

### Cabecera `X-Home-Id`

Opcional, solo en rutas autenticadas (`index.ts:163-175`; `_shared/home.ts:15-20`):

- Ausente o vacía: sin contexto de hogar (A9). Sigue con normalidad.
- Formato `^[0-9]{1,18}$` (se normaliza, `007` pasa a `7`). Otro valor: `400 {"error":"Invalid home"}` (`index.ts:168`; `errors.ts:72`).
- Hogar válido pero el usuario no es miembro (o está archivado: `get_homes` solo lista activos): `404 {"error":"Not Found"}` en las rutas `/home/*` (`index.ts:171`; `errors.ts:71`).
- Si la cabecera está presente y es de otro hogar que el pedido en query o body, la RPC responde `404 Not Found` (comparación con `fn_active_home_id()`).

### Orden de validación

1. Ruta existente (si no: `404 {"error":"Not Found"}`, `index.ts:149`).
2. Sesión (401).
3. Cabecera `X-Home-Id`: formato (400) y pertenencia (404).
4. Entrada en la Edge (`usecases/homes.ts`): ids requeridos, tipos, nombre, timezone, rol, permisos (400). No llama a la RPC.
5. RPC: cabecera contra id pedido (404), existencia/pertenencia (404), permiso (403), reglas de negocio (400/403).

### Entrada

- `GET`: solo query string. La plataforma descarta el body de GET.
- `POST`, `PATCH`, `DELETE`: body JSON. El query también se lee y el body gana en caso de colisión (`_shared/contract.ts:44-58`). El ejemplo de cada ficha usa lo habitual.
- Ids numéricos (`inputInt`, `contract.ts:68`): entero JSON o string de solo dígitos. Cualquier otro valor, `0` o ausente equivale a "ausente" (`Home ID is required` y equivalentes).

### Formato de error

`{"error":"<mensaje>"}` con el código HTTP indicado (`errors.ts:5`). Un `raise exception` de una RPC cuyo mensaje no está mapeado sale como `500` con ese mensaje (`errors.ts:55`). El mapeo de una RPC `/home/*` (`rpcPassHome`, `errors.ts:51-58`):

| Mensaje de la RPC | HTTP |
|---|---|
| `Not Found` | 404 |
| `Not Allowed` | 403 |
| `Invalid member`, `Invalid role`, `Invalid membership`, `Invalid permission`, `Name is required`, `Name is required (max 50 characters)`, `Color must be #RRGGBB` | 400 |
| otro | 500 |

### Plantillas de respuesta

Claves exactas, las de `contract_check.py`. `<ts>` = `YYYY-MM-DD HH:MM:SS`; `<id>` = entero >= 1; `?` = nullable.

| Plantilla | Forma |
|---|---|
| `HOME_ITEM` | `{home_id, name, role, is_default, is_personal}` |
| `HOME_DETAIL` | `{id, name, timezone, is_personal, created_at, updated_at}` (`<ts>` en las dos fechas) |
| `MEMBERSHIP_ITEM` | `{membership_id, app_user_id, name, email, role, permissions: [string]}` |
| `MEMBERSHIP_STATE` | `{membership_id, home_id, app_user_id, role}` |
| `TRANSFER_STATE` | `{from_membership_id, to_membership_id}` |
| `HOME_MEMBER` | `{id, home_id, kind, name, color, status, linked, created_at, updated_at}` |
| `PERMISSION_GET` | `{catalog: [{code, domain, description}], defaults: [{kind, permissions: [string]}], memberships: [PERMISSION_ITEM]}` |
| `PERMISSION_ITEM` | `{membership_id, app_user_id, name, email, role, kind?, editable, permissions: [string]}` |
| `PERMISSION_STATE` | `{membership_id, home_id, permissions: [string], granted: [string], revoked: [string]}` |
| `AUDIT_ITEM` | `{id, action, target_type, target_id?, actor_app_user_id?, actor_name?, payload: object, created_at}` |
| `SUCCESS` | `{"success":true}` |

## Glosario

| Término | Qué es | Tabla |
|---|---|---|
| `home` | El hogar. Lo identifican `id` o `home_id` según la ruta (ver desviaciones). | `home` |
| `home_member` | Una **persona** del hogar, con o sin cuenta (hijo, mascota, invitado...). `kind` = `adult`, `child`, `relative`, `guest` o `pet`; `status` = `active` o `inactive` (baja sin borrado). `linked` = tiene cuenta vinculada. Su id es el `id` de `/home/member/*`. | `home_member` |
| `home_membership` | Una **cuenta** (`app_user`) que pertenece al hogar con `role` = `admin` o `member`. Su id es el `membership_id` de `/home/membership/*` y `/home/permission`. | `home_membership` |
| `membership_permission` | Permisos por membresía de rol `member`: una fila por código. El admin no tiene filas y recibe el catálogo completo (A4). | `membership_permission` |

Un `id` de `/home/member` no es un `membership_id`: son identificadores distintos.

**Nombre de tabla de permisos.** La tabla vigente es `membership_permission` (`0012:82`, usada por 0018-0021). El comentario de la cabecera de `0012` ("home_member_permission", línea 12) está desactualizado; las migraciones existentes no se editan. La migración `0022` (1.15) solo crea `home_invitation`; no crea `home_member_permission`. 1.15 debe citar `membership_permission`.

**Permisos del hogar** (catálogo de 23, `0012:140-144`): `home.view`, `home.members.manage`, `home.invite`, `home.permissions.manage`, `home.settings.manage`, más los de calendario, tareas y rutinas. El `admin` los tiene todos sin filas. Un `member` solo los que tenga en `membership_permission` (snapshot por `kind` en 0019).

## Desviaciones documentadas

Se documentan tal como están hoy. No se renombra ni se corrige nada (D-008, aditivo). Para clientes nuevos: el nombre del parámetro es parte del contrato de cada ruta; no inferir. Una unificación solo vendría como alias aditivo en un cambio futuro.

### Naming (R-3)

| Concepto | Nombre en la ruta |
|---|---|
| Id del hogar | `id`: `GET /home/detail`, `PATCH /home/update` y `GET /home/membership` (`homes.ts:50,59,85`). `home_id`: el resto (`default`, `member`, `member/create`, `membership/role`, `membership/transfer`, `DELETE membership`, `permission`, `audit`). |
| Id de `home_member` | `id`, solo en `PATCH /home/member/update` (`homes.ts:120`). |
| Id de `home_membership` | `membership_id` en `membership/role`, `DELETE membership` y `PATCH permission`; `to_membership_id` en `membership/transfer`. |

### Códigos de éxito (R-4)

- `201`: `POST /home/create` y `POST /home/member/create` (`homes.ts:44,114`).
- `200`: todo lo demás, incluidos `POST /home/membership/transfer` (`TRANSFER_STATE`) y `DELETE /home/membership` (`SUCCESS`).
- `PATCH /home/default` devuelve `{"default_home_id": <id>}` y no un `HOME_DETAIL`.

### `Not Found` (R-5, R-6)

- En `/home/*` es `404` en todos los casos: no miembro, cabecera distinta del id, recurso ajeno (`rpcPassHome`, `errors.ts:55`; `errRouteHomeNotFound`, `index.ts:171`).
- En las rutas legacy el mismo texto es `500` por herencia del contrato PHP (`errPhpNotFound`, `errors.ts:64`).
- La ruta inexistente también es `404 {"error":"Not Found"}` (`errors.ts:63`): el cuerpo no distingue "ruta inexistente" de "hogar no visible".
- `Name is required` (nombre de hogar, `errors.ts:96`) y `Name is required (max 50 characters)` (nombre de miembro, `errors.ts:105`) son mensajes distintos.

### Comentarios y documentación desactualizados (deuda conocida, fuera de alcance)

- `index.ts:2-3` dice "9 rutas /home/*"; hay 15.
- `supabase/README.md` describe 43 rutas, migraciones hasta 0010 y "43/43".
- `errors.ts:82-83` afirma que la Edge rechaza los códigos de permiso fuera del catálogo; en realidad lo hace la RPC (`0021:136-138`). El resultado es el mismo: `400 Invalid permission`.
- `0012` línea 12: nombre `home_member_permission` (ver glosario).

## Rutas

Cada ficha: parámetros, éxito, errores (en orden de evaluación), permiso, usecase y RPC con la migración vigente. "Casos" nombra los de `contract_check.py`. Todas las rutas comparten los errores de convenciones (401, `400 Invalid home`, `404` por cabecera); las fichas listan solo lo propio. Los 401 y `Invalid home` de cada ruta tienen un caso `H110` por ruta.

### GET /home

Mis hogares activos.

- **Parámetros:** ninguno. La cabecera no filtra: la lista es completa (`0016:27-28`).
- **Éxito:** `200 [HOME_ITEM]`. Orden por `home_id`. `role` = `admin` o `member`. Hogares archivados excluidos.
- **Errores propios:** ninguno (`Not Allowed` 403 solo si el usuario autenticado no tiene `app_user`, `0016:35`).
- **Permiso:** ninguno (cualquier usuario autenticado).
- **Usecase / RPC:** `handleHomeIndex` (`homes.ts:28`) -> `get_homes` (`0016:29`).
- **Casos:** H1, H18, H14b, H110 (cabecera vacía, A9).

### POST /home/create

Crea un hogar; el creador queda como `admin`.

- **Body:** `name` (requerido, se hace `trim`), `timezone` (opcional, IANA; por defecto `Europe/Madrid`).
- **Éxito:** `201 HOME_DETAIL` con `is_personal: false`.
- **Errores:** `400 Name is required` (ausente, no string o solo blancos; `homes.ts:36`); `400 Invalid timezone` (`homes.ts:41`; `timezone` null equivale a ausente).
- **Permiso:** ninguno.
- **Usecase / RPC:** `handleHomeCreate` (`homes.ts:32`) -> `create_home` (`0016:52`; `Name is required` también en `0016:62`).
- **Casos:** H2, H3, H3b, H3c.

### GET /home/detail

- **Query:** `id` (hogar, requerido).
- **Éxito:** `200 HOME_DETAIL`.
- **Errores:** `400 Home ID is required` (`homes.ts:51`, sin caso); `404 Not Found` (cabecera distinta de `id`, `0016:83`; no miembro, `fn_require_member`, `0012:237`); `403 Not Allowed` (miembro sin `home.view`, `0016:85`).
- **Permiso:** `home.view`.
- **Usecase / RPC:** `handleHomeDetail` (`homes.ts:48`) -> `get_home_detail` (`0016:79`).
- **Casos:** H4, H5, H110 (403 sin `home.view`).

### PATCH /home/update

- **Body:** `id` (hogar, requerido), `name` (requerido, `trim`), `timezone` (opcional; ausente o null conserva la zona actual).
- **Éxito:** `200 HOME_DETAIL`.
- **Errores:** `400 Home ID is required`; `400 Name is required`; `400 Invalid timezone` (orden de la Edge: id, name, timezone; `homes.ts:57-70`); `404 Not Found` (cabecera distinta, `0016:103`; no miembro); `403 Not Allowed` (sin `home.settings.manage`, `0016:105`).
- **Permiso:** `home.settings.manage`.
- **Usecase / RPC:** `handleHomeUpdate` (`homes.ts:57`) -> `update_home` (`0016:97`; `Name is required` repetido en `0016:107`).
- **Casos:** H6, H6b, H7, H8, H8b. Sin caso del 403.

### PATCH /home/default

Fija el hogar por defecto de la cuenta.

- **Body:** `home_id` (requerido).
- **Éxito:** `200 {"default_home_id": <id>}`.
- **Errores:** `400 Home ID is required` (`homes.ts:78`); `404 Not Found` (cabecera distinta, `0016:135`; no miembro, `0016:137`). Ninguna ruta de error emite `403`: el único `Not Allowed` es el de usuario sin `app_user` (`0016:132`), no alcanzable con una sesión válida. No existe caso 403 de contrato para esta ruta.
- **Permiso:** ser miembro del hogar.
- **Usecase / RPC:** `handleHomeDefault` (`homes.ts:75`) -> `set_default_home` (`0016:126`).
- **Casos:** H9, H10, H11, H110 (sin `home_id`).

### GET /home/membership

Cuentas del hogar con permisos efectivos.

- **Query:** `id` (hogar, requerido; ver naming).
- **Éxito:** `200 [MEMBERSHIP_ITEM]`. Orden por `role` y `name` (collate "C", `0016:164`). `permissions` del `admin` = catálogo completo; del `member` = su snapshot.
- **Errores:** `400 Home ID is required` (sin caso); `404 Not Found`; `403 Not Allowed` (sin `home.view`, `0016:151`).
- **Permiso:** `home.view`.
- **Usecase / RPC:** `handleHomeMembership` (`homes.ts:83`) -> `get_home_memberships` (`0016:145`).
- **Casos:** H12, H13, M0d, K1-K5, PP3 (403).
- **No emite** `User cannot remove themselves`: ese mensaje solo existe en `/calendar/user` y `/task-list/user`.

### PATCH /home/membership/role

Designa o degrada admin. Idempotente: si el rol ya coincide devuelve el estado sin escribir.

- **Body:** `home_id`, `membership_id` (requeridos), `role` (`admin` o `member`).
- **Éxito:** `200 MEMBERSHIP_STATE`.
- **Errores (orden):** `400 Home ID is required`; `400 Membership ID is required`; `400 Invalid role` (ausente, no string u otro valor; `homes.ts:145`); `404 Not Found` (hogar archivado, cabecera distinta, no miembro, membresía de otro hogar; `0018:67-72,151`); `403 Not Allowed` (el caller no es admin, `0018:154`; degradar al último admin, `0018:161`).
- **Permiso:** `admin`.
- **Efectos:** promover borra el snapshot de permisos; degradar siembra el snapshot legacy.
- **Usecase / RPC:** `handleHomeMembershipRole` (`homes.ts:138`) -> `set_home_membership_role` (`0018:128`).
- **Casos:** M1, M2, M6, M6b, M8, M11, M12, M13, M16-M19.

### POST /home/membership/transfer

Transferencia atómica de la administración: el destino pasa a `admin` y el caller a `member`.

- **Body:** `home_id`, `to_membership_id` (requeridos).
- **Éxito:** `200 TRANSFER_STATE` (no 201).
- **Errores (orden):** `400 Home ID is required` (sin caso); `400 Membership ID is required`; `404 Not Found` (guarda de hogar y caller sin membresía; `0018:199`); `403 Not Allowed` (caller no admin, `0018:202`); `404 Not Found` (destino de otro hogar, `0018:207`); `400 Invalid membership` (destino = la propia membresía, `0018:210`).
- **Permiso:** `admin`.
- **Usecase / RPC:** `handleHomeMembershipTransfer` (`homes.ts:153`) -> `transfer_home_admin` (`0018:180`).
- **Casos:** M3, M4, M7, M9, M12b, M16b-M19b.

### DELETE /home/membership

Salir del hogar (membresía propia) o expulsar (ajena, solo admin).

- **Body:** `home_id`, `membership_id` (requeridos).
- **Éxito:** `200 SUCCESS`. Reasigna `default_home_id` si apuntaba a ese hogar.
- **Errores (orden):** `400 Home ID is required` (sin caso); `400 Membership ID is required`; `404 Not Found` (guarda de hogar, membresía de otro hogar o inexistente; `0018:260`); `403 Not Allowed` en todos estos casos: expulsar sin ser admin (`0018:263`), ser el último admin (`0018:266`), ser el único owner de un calendario o lista (`0018:269`) y salir del último hogar activo (`0018:277`).
- **Permiso:** `admin` para expulsar; ser la propia membresía para salir.
- **No emite** `User cannot remove themselves` (verificado en `0018:230-289`: los únicos errores son `Not Allowed` y `Not Found`). Salir siendo owner único, último admin o con un solo hogar es `403 Not Allowed`.
- **Usecase / RPC:** `handleHomeMembershipRemove` (`homes.ts:166`) -> `remove_home_membership` (`0018:230`).
- **Casos:** M5, M10, M12c, M13b, M14, M15, M16c-M19c.

### GET /home/member

Personas del hogar (activas e inactivas).

- **Query:** `home_id` (requerido).
- **Éxito:** `200 [HOME_MEMBER]`. Orden: `status` (`active` antes), `name`, `id` (`0017:197-198`). No incluye `app_user_id` ni email.
- **Errores:** `400 Home ID is required` (sin caso); `404 Not Found`; `403 Not Allowed` (sin `home.view`, `0017:195`).
- **Permiso:** `home.view`.
- **Usecase / RPC:** `handleHomeMemberIndex` (`homes.ts:92`) -> `get_home_members` (`0017:186`).
- **Casos:** K7, K10, K13, K15.

### POST /home/member/create

Persona sin cuenta (sin membresía ni permisos) más su `person` 1:1.

- **Body:** `home_id` (requerido), `kind` (requerido: `adult`, `child`, `relative`, `guest`, `pet`), `name` (requerido, 1 a 50 caracteres tras `trim`), `color` (opcional `#RRGGBB`; por defecto `#6923E2`).
- **Éxito:** `201 HOME_MEMBER` con `status: "active"`, `linked: false`.
- **Errores (orden):** `400 Home ID is required` (sin caso); `400 Invalid member` (`kind` ausente, no string o fuera de lista; `homes.ts:104-105`; en RPC `0017:224`); `400 Name is required (max 50 characters)` (ausente o no string, `homes.ts:107-108`; vacío o > 50 en RPC, `0006:80`); `400 Color must be #RRGGBB` (no string o formato; `homes.ts:110`; RPC `0006:83`); `404 Not Found`; `403 Not Allowed` (sin `home.members.manage`, `0017:222`). En la RPC el permiso se comprueba antes que `kind`, nombre y color.
- **Permiso:** `home.members.manage`.
- **Usecase / RPC:** `handleHomeMemberCreate` (`homes.ts:100`) -> `create_home_member` (`0017:206`).
- **Casos:** K1, K2, K3, K4, K4b, K5, K6, K7b.

### PATCH /home/member/update

- **Body:** `id` (de `home_member`, requerido), y opcionales `kind`, `status` (`active` o `inactive`), `name`, `color`. Ausente o null = sin cambio. Un valor presente que no sea string: `400` del campo, sin llamar a la RPC.
- **Éxito:** `200 HOME_MEMBER`. Sin cambios reales no se toca `updated_at`. `status: "active"` reactiva (re-alta).
- **Errores (orden en la Edge):** `400 Member ID is required` (`homes.ts:121`, sin caso); `400 Invalid member` (`kind` o `status` no string, `homes.ts:122,124`); `400 Name is required (max 50 characters)` (`name` no string, o inválido en RPC); `400 Color must be #RRGGBB`. En la RPC (`0021:177-264`): `404 Not Found` (miembro inexistente, de otro hogar, o de otro hogar que la cabecera; `0021:206,222`); `403 Not Allowed` (sin `home.members.manage`, `0021:224`); `400 Invalid member` (`kind` o `status` fuera de lista, o `pet` con cuenta vinculada; `0021:229,232`); `403 Not Allowed` (cambiar el `kind` de un miembro vinculado sin ser admin, `0021:236`, desviación D-011).
- **Permiso:** `home.members.manage`; cambiar `kind` de un miembro vinculado exige además `admin` (resetea el snapshot de permisos).
- **Usecase / RPC:** `handleHomeMemberUpdate` (`homes.ts:118`) -> `update_home_member` (`0021:177`, vigente; la versión de `0017:240` queda reemplazada).
- **Casos:** K6b, K7c, K9, K10, K13, K13b, K14, K15, PK4-PK6, H110 (`status` no string).

### GET /home/permission

Catálogo, defaults por `kind` y permisos efectivos por membresía.

- **Query:** `home_id` (requerido).
- **Éxito:** `200 PERMISSION_GET`. `catalog` (23), `defaults` por `kind` y `memberships`. En cada fila `editable` = el caller es admin y la fila es `member`. `kind` es el del `home_member` vinculado (null si no hay).
- **Errores:** `400 Home ID is required`; `404 Not Found`; `403 Not Allowed` (sin `home.view`, `0021:42`).
- **Permiso:** `home.view`.
- **Usecase / RPC:** `handleHomePermissionIndex` (`homes.ts:180`) -> `get_home_permissions` (`0021:36`).
- **Casos:** PG1-PG8.

### PATCH /home/permission

Fija el conjunto completo de permisos de una membresía `member` (idempotente; el servidor calcula el delta y lo audita).

- **Body:** `home_id`, `membership_id` (requeridos), `permissions` (array de códigos, hasta 100).
- **Éxito:** `200 PERMISSION_STATE`. Si no cambia nada: `granted` y `revoked` vacíos y sin auditoría.
- **Errores (orden):** `400 Home ID is required`; `400 Membership ID is required`; `400 Invalid permission` (ausente, no array o elemento no string, en la Edge, `homes.ts:197-199`; código fuera del catálogo o más de 100 en la RPC, `0021:124-138`); `404 Not Found` (guarda de hogar); `403 Not Allowed` (sin `home.permissions.manage`, `0021:144`; el caller no es admin, `0021:146`); `404 Not Found` (membresía de otro hogar, `0021:151`); `403 Not Allowed` (destino `admin`, `0021:154`).
- **Permiso:** `home.permissions.manage` y además `admin` (un `member` con ese permiso recibe 403, Q1).
- **Usecase / RPC:** `handleHomePermissionUpdate` (`homes.ts:191`) -> `set_home_permissions` (`0021:106`).
- **Casos:** PP1-PP15 (PP13 = 401).

### GET /home/audit

Auditoría del hogar (solo acciones `home.%`).

- **Query:** `home_id` (requerido), `limit` (opcional; por defecto 50, acotado a 1..200; no numérico = por defecto), `before_id` (opcional; solo filas con `id` menor, paginación).
- **Éxito:** `200 [AUDIT_ITEM]`, más recientes primero (`id` desc).
- **Errores:** `400 Home ID is required` (sin caso); `404 Not Found`; `403 Not Allowed` (no admin, `0021:87`).
- **Permiso:** `admin`.
- **Usecase / RPC:** `handleHomeAudit` (`homes.ts:209`) -> `get_home_audit` (`0021:76`).
- **Casos:** PA1-PA7.

## Invitaciones (diseñado, no implementado; 1.15)

**Estado: no vigente.** Ninguna de estas rutas existe en la Edge (`grep home/invitation supabase/functions` vacío) ni hay tabla `home_invitation`. Contrato de diseño tomado de `.dorch/archive/fase-0-auditorias/diseno-home.md` (§5.2 y §7, líneas 435-461 y 400). Se implementa en 1.15 (`HOMITA_FUNDATIONS.md:221`) con la migración `0022_home_invitations.sql`, que solo crea `home_invitation` (ver glosario sobre `membership_permission`).

| Ruta | Permiso | Descripción |
|---|---|---|
| `GET /home/invitation` | `home.invite` | Invitaciones pendientes. |
| `POST /home/invitation/create` | `home.invite` | Crea una invitación (`kind`, `member_id` opcional). Devuelve el código una sola vez (D14: copiable, sin email). |
| `POST /home/invitation/accept` | sesión | Acepta por código: `{code}`. |
| `POST /home/invitation/revoke` | `home.invite` | Revoca una invitación `pending`. |

- **Estados:** `pending`, `accepted`, `revoked`. `expired` se calcula al leer (`expires_at <= now()`); la caducidad es de 7 días y no hay job.
- **Código:** 32 caracteres hex (128 bits CSPRNG), un solo uso; la base guarda solo su hash SHA-256.
- **Errores previstos:**
  - Crear: `400 Invalid member` (`member_id` de otro hogar, `pet`, no activo o ya vinculado; sin `member_id` el `kind` no puede ser `pet`).
  - Aceptar: `404 Not Found` (código inexistente, usado, revocado o caducado; no distingue la causa, sin oráculo); `400 Already member` (ya existe membresía en ese hogar; la invitación no se consume); `400 Invalid member` (`member_id` incompatible al aceptar).
  - Revocar: `404 Not Found` si la invitación no está `pending`.
- **Requisito para 1.15:** `Already member` no está en `RPC_STATUS` (`errors.ts:10-35`); sin añadirlo saldría `500`. `Invalid member` y `Not Found` ya están mapeados.
- Los códigos HTTP de éxito y las formas de respuesta no los fija el diseño; 1.15 los define y añade sus plantillas a `contract_check.py`.
- `add_calendar_user`/`add_task_list_user` con email de un no miembro siguen devolviendo `403 Not Allowed` (Q3); la vía para sumar externos es la invitación.
