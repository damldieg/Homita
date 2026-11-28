# Cómo lanzar la mejora del dashboard con claude CLI + dorch-claude

Plan para que la pantalla de pared (`apps/dashboard`) pase de pantalla de consulta a producto: sesión que
no caduca, Hoy legible a distancia, pantalla vinculada al hogar, marcar tareas hechas y actualización
remota. La auditoría completa, con los hallazgos numerados (U, N, A, C, Q), está en [brief.md](brief.md).

## Pasos

1. En el Mac, `cd` al repo Homita y `git fetch`.
2. Para cada paso, en orden, abre dorch-claude y pásale:
   - el prompt del paso (`prompts/0N-*.md`),
   - `brief.md` de esta carpeta.
3. Los pasos 02, 03 y 05 empiezan con una **propuesta sin código** y se paran. Lee la propuesta, elige
   una opción y díselo a dorch en la misma sesión para que siga.
4. Cuando dorch termine, revisa su informe. Para push y PR añade `authorized: push pr gh` al `status.md`
   del change.
5. No empieces un paso hasta que los que necesita estén en master (tabla de abajo).

| Paso | Prompt | Qué consigue | Se para a preguntar | Necesita |
|---|---|---|---|---|
| 01 | [01-dashboard-sesion](prompts/01-dashboard-sesion.md) | La pantalla deja de volver al login cada semana | No | nada |
| 02 | [02-dashboard-hoy-legible](prompts/02-dashboard-hoy-legible.md) | Hoy se lee de pie, avisos de vencimiento correctos, menos duplicados | Sí, diseño de Hoy | nada |
| 03 | [03-dashboard-pantalla-hogar](prompts/03-dashboard-pantalla-hogar.md) | Vincular con código desde iOS; la pantalla es del hogar y se configura desde el móvil | Sí, identidad de la pantalla | 01 |
| 04 | [04-dashboard-marcar-hecho](prompts/04-dashboard-marcar-hecho.md) | Completar tareas con un toque y filtrar por persona | Confirma si la pantalla escribe | 02 y 03 |
| 05 | [05-dashboard-actualizacion-remota](prompts/05-dashboard-actualizacion-remota.md) | Actualizar las pantallas sin ADB | Sí, dónde se publica la APK | 03 |
| 06 | [06-dashboard-menu-compra](prompts/06-dashboard-menu-compra.md) | Pantalla Menú rediseñada (Semana) y Compra en la pared, con marcar comprado | Sí, capturas de la fase A antes de la fase B | 03 y 04 |

Orden: 01 ∥ 02 → 03 → 04 → 05; el 06 puede ir en cuanto 03 y 04 estén en master. El 01 y el 02 pueden ir en paralelo porque no tocan los mismos ficheros
salvo `DashboardViewModel.kt`; si los lanzas a la vez, fusiona primero el 01.

## Antes de empezar, decide

Las decisiones abiertas están al final de [brief.md](brief.md). Solo la 1 (¿la pantalla escribe?) bloquea
un paso, el 04; las demás las pide cada prompt en su momento.

## Cómo encaja con lo que ya está en marcha

- **Planificador de comidas**: «Hoy se come» ya está en master (fase 4). El paso 02 le da sitio propio en
  Hoy. El paso 06 rediseña la pantalla Menú y añade la Compra (decidido el 2026-11-28: la pared marca y
  desmarca comprado, nada más).
- **Kito**: no entra en la pantalla (el XORO no tiene micrófono). El resumen «Buenos días» (A5) puede
  reutilizar la tarjeta de Hoy cuando el paso 02 esté hecho.
- **TestFlight**: el paso 03 añade una sección a la app iOS, así que entra en la siguiente versión.

## Qué no cubren estos pasos

Rutinas hechas por persona (A3), fotos como salvapantallas (A6), calendarios externos (A9), Kito en la
pantalla (A10) y la vista por persona del Calendario (C3). Quedan en el brief para cuando toque.

## Pendientes conocidos

- **Residuo de la cuenta técnica al revocar una pantalla (GoTrue local).** Cada pantalla tiene una cuenta técnica en `auth.users`. Al revocarla, `fn_display_revoke` quita su membresía y su selección (la pantalla deja de leer datos del hogar) y la Edge pide a GoTrue que borre la cuenta. GoTrue registra `user_deleted`, pero la fila sigue en la base de datos local, sin `deleted_at` y con una sesión activa. No hay triggers ni reglas sobre `auth.users` que lo expliquen. Riesgo práctico: bajo, porque la pantalla ya no tiene permisos sobre el hogar; queda una cuenta sobrante que podría iniciar sesión. Estado: abierto y documentado, sin cambios de código. Pendiente de investigar la versión de GoTrue local o de reforzar la revocación (banear la cuenta y reintentar el borrado).
