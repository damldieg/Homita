Nuevo change dorch `kito-ayuda` (Homita). Paso 4 de 6 de la mejora de Kito: skill `ayuda`, para que Kito responda «¿cómo se hace…?» sobre la propia app (pedido original de Damian del 2026-11-20). Backend (Edge `asistente`) y una sugerencia en iOS. Requiere el paso 1 (`kito-calidad-consulta`) en master.

## Contexto
Te paso `brief.md` (hallazgo 12). Fuente de verdad de lo que hace la app: `docs/ios-funcional.md` (13 KB, mapa de pantallas, formularios y permisos) y el código de `apps/control-ios`. Kito no debe inventar pantallas ni botones.

## Qué hacer
1. **Change dorch.** `.dorch/changes/kito-ayuda/` (brief, plan tuyo, status `approved: yes` Damian 2026-11-23, `authorized:` vacío). Rama `dc/kito-ayuda` desde `origin/master`, worktree `../Homita-kito-ayuda`.
2. **Guía curada** `supabase/functions/asistente/skills/ayuda/guia.ts`: secciones cortas (máx. ~600 caracteres cada una) escritas para usuarios, no para desarrolladores, con `id`, `titulo`, `palabras` (sinónimos) y `texto` paso a paso («Tareas › Listas › Nueva lista…»). Mínimo: crear/editar/borrar tarea, lista, evento, rutina y calendario; compartir calendario o lista y dar permiso de edición; asignar personas; prioridad y fecha límite de tareas; avisos y resumen de tareas; cambiar de hogar; invitar a alguien al hogar; vincular una persona a una cuenta; administrar el hogar (qué ve un admin y qué un miembro); qué es Kito y su límite diario; enviar feedback. Sácalo de `docs/ios-funcional.md` contrastado con el código actual (si el doc está desfasado, manda el código y anótalo en el informe).
3. **Skill `ayuda`** (`skills/ayuda/index.ts`, registrada en `skills/registry.ts`): herramienta `guia_app(tema)` que devuelve las 1–3 secciones que mejor casan (búsqueda simple por palabras normalizadas, sin acentos), o la lista de temas si no hay coincidencia. Instrucciones: usar `guia_app` para cualquier pregunta sobre cómo se hace algo en Homita; responder solo con lo que diga la guía; si no está, decir que no lo sabe y sugerir enviar feedback desde Perfil. El núcleo no se toca.
4. **Consulta**: cuando el usuario pida una escritura que Kito aún no hace, las instrucciones de `consulta` remiten a `guia_app` para decir dónde se hace (sustituye a la indicación genérica del paso 1).
5. **iOS**: añade «¿Cómo comparto una lista?» a `KitoSuggestions` (del paso 2; si el paso 2 no está en master, sáltalo y anótalo).
6. **Test de cobertura**: un test Deno que falla si alguna pestaña o formulario listado en `docs/ios-funcional.md` §3 no tiene sección en la guía (lista de ids esperados en el test).

## Tests
Búsqueda por tema con y sin acentos, sinónimos, sin coincidencia → lista de temas, tope de secciones, skill registrada sin tocar `core.ts`, test de cobertura.

## Verificación
`deno check` + `deno test` de `asistente` y `scripts/supabase/ci.sh` en verde; si toca iOS, `swift test` y `xcodebuild` Debug/Release. Añade a `scripts/kito/eval.ts` (paso 1): «¿cómo comparto una lista?», «¿cómo invito a alguien al hogar?», «¿cómo cambio el color de un calendario?», «¿puedo exportar a Excel?» (no existe: debe decirlo).

## Reglas
- Nada en producción. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.

## Al terminar, infórmame de
Hashes, tests, secciones de la guía y desfases encontrados entre el doc funcional y el código.
