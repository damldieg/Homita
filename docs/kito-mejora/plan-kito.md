# Plan: Kito por fases

## Arquitectura
- Nueva Edge Function **`asistente`** (Deno, `verify_jwt = false`, auth manual como `api`). Recibe
  `POST {messages, timezone}` con el Bearer del usuario y `X-Home-Id`, y hace un bucle de tool use con
  la API de Anthropic (modelo `KITO_MODEL`, por defecto `claude-haiku-5-5`).
- **Las herramientas no hablan con la base por su cuenta**: llaman en proceso a los casos de uso de
  `api` (`usecases/*.ts`) con el JWT del usuario. Heredan RLS, ACL `can_edit`, catálogo del hogar y
  validaciones sin duplicar lógica. Núcleo en `kito/core.ts` para que Alexa sea otro adaptador.
- Defensa ante prompt injection como en `procesar-feedback`: instrucciones en `system`, datos de la
  app en bloques JSON escapados, ids validados contra lo que devolvieron las herramientas.
- Historial: lo guarda la app y lo manda en cada petición (máx. 20 mensajes); el servidor no lo guarda.
- Límite: migración `0036_assistant_usage.sql` (la 0035 es `0035_client_request_idempotency.sql`, la idempotencia de altas) (tabla `assistant_usage(app_user_id, day, count)` con
  RLS y RPC `assistant_consume(p_timezone)` que suma 1 y devuelve si cabe; tope 50) + rollback + check
  SQL. Se consume antes de llamar al modelo. Tras responder se suman los tokens de entrada, salida y
  caché de `usage` (columnas `input_tokens`, `output_tokens`, `cache_read_tokens`) para medir el coste real
  por hogar y ajustar topes y precios (estimación del 2026-11-20: ~0,002–0,004 € por mensaje con Haiku 5.5).
- iOS: `KitoButton` (flotante, overlay de `MainTabView`), `KitoChatView` + `KitoStore`
  (`@Observable`), `KitoHistoryStore` (JSON en Application Support, por usuario y hogar; se borra en
  `signOut()`), `KitoAPI` (URL hermana de `/api`: `/asistente`), avatar en `Assets`.

## Kito como asistente base con skills (pedido de Damian, 2026-11-20)
Kito no es «el asistente de tareas»: es un núcleo que no cambia y **skills** que se enchufan. Cada
funcionalidad nueva (menús, ropa según el clima, lo que venga) es una skill más.

**Una skill** (`supabase/functions/asistente/skills/<id>/index.ts`) declara:
- `id`, `nombre`, `descripcion` (cuándo usarla; el modelo la lee para decidir).
- `instrucciones`: fragmento del system prompt solo para esa skill.
- `herramientas`: sus tools (esquema + función que las ejecuta con el JWT del usuario).
- `tarjetas`: los tipos de tarjeta que puede devolver (por ejemplo `confirmacion`, `menu`).
- `disponible(ctx)`: si está activa para ese usuario y hogar (tier, permisos, ajustes).
- `modelo` (opcional): secreto propio de la skill (p. ej. `KITO_MODEL_MENUS`); si falta, `KITO_MODEL`.
  Idea de Damian (2026-11-20): `menus` con Sonnet 5.5 y el resto con Haiku 5.5, a validar con una
  comparación sobre 10–20 hogares de ejemplo antes de decidir.

**El núcleo** (`kito/core.ts`): auth, límite de uso, junta las skills disponibles (prompt + tools),
hace el bucle con Anthropic, enruta cada tool a su skill y devuelve `{texto, tarjetas}`. Añadir una
skill = crear su carpeta y registrarla en `skills/registry.ts`; el núcleo no se toca.

**En la app**: un registro de vistas por tipo de tarjeta (`KitoCardRenderer`). Una tarjeta de un tipo
que la app aún no conoce se muestra como texto, así una skill nueva en el servidor no rompe versiones
viejas de la app.

**Skills previstas**
| Skill | Fase | Qué hace |
|---|---|---|
| `consulta` | 1 | Responde sobre eventos, rutinas, tareas, listas, calendarios y personas |
| `organizar` | 2 | Crea, edita y borra listas, tareas, eventos, rutinas y calendarios (campos indispensables + confirmación) |
| `resumen_dia` | 3 | Resumen de lo asignado al usuario |
| `menus` | futura | Menú semanal desde el perfil de hogar + lista de la compra |
| `ropa_clima` | futura | Qué ponerse según el tiempo (tier de la visión de producto) |

Alexa será otro adaptador de entrada sobre el mismo núcleo y las mismas skills.

## Fase 1: consulta por texto
1. Migración 0036 (`assistant_usage`) + rollback + check SQL del límite.
2. `supabase/functions/asistente`: `index.ts` (cableado), `handler.ts` (auth, límite, validación,
   bucle con topes: 2000 caracteres por mensaje, 6 vueltas de tools), `tools.ts` (solo lectura:
   `ver_eventos`, `ver_rutinas`, `ver_listas`, `ver_tareas`, `ver_personas`, `fecha_actual`).
3. Tests Deno con fetch y casos de uso falsos.
4. iOS: botón, chat, store, historial local, cliente, avatar y tests.
5. Docs: README de la función y comandos de despliegue y de secretos (los ejecuta Damian).

## Fase 2: acciones y voz
- Tools de escritura: crear, editar y borrar listas, tareas, rutinas y eventos con el JWT del usuario.
  Un 403 se explica en el chat («no tienes permiso de edición en …»).
- **Confirmación**: borrados y cambios de más de un elemento devuelven una propuesta; la app muestra
  «Confirmar / Cancelar» y solo al confirmar se ejecuta (token de confirmación firmado por el servidor).
- **Campos indispensables.** Cada herramienta de escritura declara en su `input_schema` los campos
  obligatorios. Si falta alguno, Kito pregunta por él (uno o varios a la vez) antes de llamar. Si el
  dato es ambiguo (dos listas «Compra»), ofrece las opciones. Además, el servidor revalida: si el
  modelo llama sin un campo, la herramienta devuelve «falta X» y Kito lo pregunta (no llega a la API).
  Los nombres («lista Compra», «Lucía») se resuelven a ids con las herramientas de lectura.

  | Elemento | Crear | Editar | Borrar |
  |---|---|---|---|
  | Lista | nombre | qué lista + qué cambia | qué lista (con confirmación) |
  | Tarea | título + lista | qué tarea + qué cambia | qué tarea (con confirmación) |
  | Evento | título + fecha y hora + calendario | qué evento + qué cambia | qué evento (con confirmación) |
  | Rutina | título + calendario + hora + días (si es semanal) | qué rutina + qué cambia | qué rutina (con confirmación) |
  | Calendario | nombre + de quién es (ver abajo) | qué calendario + qué cambia | qué calendario (con confirmación) |

  Opcionales que Kito no pide pero acepta: personas asignadas, color, alarma, fecha de fin,
  descripción. La API exige en las ediciones campos completos (por ejemplo, nombre y color del
  calendario): Kito lee el elemento actual y rellena lo que no cambia, sin preguntarlo.

  **Calendario, «de quién es»** (Damian, opción a): con quién se comparte al crearlo. Kito pregunta
  «¿con quién lo compartes?» y acepta «solo conmigo». Resuelve los nombres a cuentas del hogar
  (miembros con cuenta vinculada) y, tras crear el calendario, llama a `POST /calendar/user` por cada
  una y a `PATCH /calendar/user` si se pide edición. Si no se dice el permiso, solo lectura. Miembros
  sin cuenta no se pueden añadir y Kito lo explica.
- Voz: `SFSpeechRecognizer` + `AVAudioEngine`, dictado en `es-ES`, botón de micro en el chat;
  `NSSpeechRecognitionUsageDescription` y `NSMicrophoneUsageDescription`. Respuesta en texto.

## Fase 3: resumen matutino
- Ajuste «Resumen de Kito» en Ajustes › Notificaciones (activar + hora), guardado en el móvil.
- `NotificationPlanner` programa el aviso diario local; al tocarlo abre `homita://kito?resumen=1`.
- Kito genera el resumen al abrir, con solo lo asignado al usuario (persona vinculada a su cuenta),
  en su zona horaria. Cuenta para el límite diario.
- Futuro (con Apple Developer Program): guardar la hora en Supabase y enviar push con el resumen
  ya escrito.

## Fase futura: menús semanales (no entra en este change)
Pedido por Damian el 2026-11-20. Se hará después de crear el «perfil de hogar» de comidas.
- **Perfil de hogar** (fase propia, por definir): gustos y restricciones, cuántas personas comen,
  qué días y qué comidas, días que comen fuera o no comen, etc.
- **Flujo:** Kito lee el perfil → propone el menú de la semana → la persona marca qué cambiar o qué
  no quiere → Kito vuelve a proponer solo lo marcado → al aceptar, Kito crea la **lista de la compra**
  del menú (una lista de tareas de Homita, con cantidades según comensales).
- Encaja con el tier de «recomendador de menús» de la visión de producto.

### Qué se prepara ya en las fases 1–3 para no rehacerlo
- **Herramientas en un registro** (`kito/tools/*.ts`, una por dominio). Añadir `ver_perfil_hogar`,
  `proponer_menu` o `crear_lista_compra` será sumar ficheros, sin tocar el bucle.
- **Respuestas con bloques estructurados**, no solo texto: además de `texto`, la función puede
  devolver `tarjetas` tipadas (por ejemplo `confirmacion` en la fase 2). El menú será otro tipo de
  tarjeta (`menu`, con un elemento por comida que se puede marcar «cambiar» o «no quiero»), y la
  app lo pinta con su propia vista. En la fase 1 solo existe el tipo `texto`, pero el contrato ya
  lleva la lista.
- **Estado de la propuesta en el cliente**: como el historial vive en el móvil, la propuesta de
  menú y las marcas viajan en la petición siguiente; no hace falta tabla de conversaciones.
- **Límite de uso por tipo** listo para tiers: `assistant_usage` cuenta mensajes; más adelante puede
  contar aparte las generaciones de menú.
