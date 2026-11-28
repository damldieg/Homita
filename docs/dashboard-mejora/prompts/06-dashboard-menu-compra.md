Change `dashboard-menu-compra` (Homita). Rediseño de la pantalla **Menú** del dashboard de pared (`apps/dashboard`) con la estética del resto de la app, y un apartado **Compra** nuevo, como el de Menú › Compra en Control iOS.

> Referencia visual del estado actual: [`docs/images/dashboard-menu-actual.png`](../../images/dashboard-menu-actual.png). Captura del emulador `Frame_API_29` (1920×1200), 28-11-2026.

## Contexto

**Estado actual (captura).** Desde la barra lateral, «Menú» abre «Menú de la semana · 23 al 29 noviembre»: una tabla de texto de 7 días × 4 franjas (Desayuno, Comida, Merienda, Cena), con flechas ‹ › arriba a la derecha. Problemas:
- No usa ninguna pieza del sistema visual del dashboard: no hay tarjetas (`Panel`/`Card`), ni `CardHeader`, ni `SectionLabel`, ni `EmptyState`. El texto flota sobre el fondo.
- Hoy (sáb. 28) no se distingue en nada. Tampoco la franja actual ni los días pasados.
- Las casillas vacías son «—» sueltos, y la merienda casi vacía se lleva una fila entera.
- Las cabeceras de día (24 px, InkSoft) se leen peor a distancia que los platos, y las etiquetas de franja quedan pegadas al borde.
- La mitad de abajo de la pantalla está vacía, mientras los platos parten en 2 o 3 líneas.
- «Comida fuera» y las sobras se pintan como un plato más.
- Las flechas son glifos de texto pequeños (no llegan a 64 px de área táctil) y no hay «Volver a esta semana».

**Dónde está el código.** En `origin/master` (0ea315b, 28-11) la barra solo tiene Hoy, Calendario, Tiempo, Tareas y Ajustes (`ui/App.kt`, `enum class Page`), y no hay ninguna `MenuScreen` en ninguna rama remota. La pantalla de la captura está solo en local, en algún worktree de Damian. **Lo primero: búscala** (`grep -rn "Menú de la semana" ../Homita*/apps/dashboard`). Si existe, parte de ella (modelo, repositorio, llamada a la API) y sustituye su UI. Si no la encuentras, pregunta a Damian antes de empezar de cero.

**Sistema visual del dashboard (lo que hay que reutilizar).** Todo en `apps/dashboard/app/src/main/java/com/dld/homita/dashboard/ui/`:
- `theme/Theme.kt`: `Palette` (fondo `Background` F7EEE2, `Card` FFFDF9, `Line`, `Ink`, `InkSoft`, `InkMuted`, `Accent` B04A27 para etiquetas y «Hoy», `Sage` 4F7A63 que ya es el color de las comidas en «Hoy se come», `Highlight` F6ECDD), fuente Geist y estilos `Type.Title` 46, `Large` 34, `Body` 29, `Small` 24, `Tiny` 20, `Label` 19 en mayúsculas. Con `Density(1f)`, 1 dp = 1 px del panel.
- `Common.kt`: `Panel` (tarjeta de radio 36), `CardHeader` (icono en cuadro tintado + título + píldora con el total), `EmptyState` (icono en dos círculos), `SectionLabel`, `Hairline`, `fadingScroll`, `PersonInitials`, `weekRange()`, `relativeDay()`.
- `App.kt`: `PillButton` (84 px de alto), `ScreenPadding`, la barra (`Rail`), la vuelta a Hoy tras 2 min sin tocar, y el «Deshacer» de 5 s de las tareas.
- `CalendarScreen.kt`: el patrón de semana más cercano. 7 `DayCard` de lunes a domingo: hoy en `Card` opaca con «Hoy» y el número en `Accent` SemiBold, los demás días en `Card` al 50 %, los pasados con `alpha(0.6f)`, y «Volver a hoy» como `PillButton` primario cuando no estás en la semana actual.
- `TodayScreen.kt`: `MealsCard` («Hoy se come»: franja actual en SemiBold, pasadas en `InkMuted`) y el resto de tarjetas.
- `TasksScreen.kt`: columnas de `Panel` con `CardHeader` y filas con casilla. Es el patrón que debe seguir la Compra.

**Compra en Control iOS (lo que hay que imitar).** `apps/control-ios/Sources/ControlKit/Features/Meals/ShoppingView.swift`, `ShoppingStore.swift` y `Model/ShoppingModels.swift`:
- La lista del hogar va agrupada por sección, en el orden `ShoppingFormat.sectionOrder` (verdura, fruta, carne, embutido, pescado, marisco, lácteos, huevos, legumbres, cereales, panadería, despensa, aceites, especias, bebidas, congelados, otros). Títulos con `sectionTitle()`: «Lácteos», «Panadería», el resto con mayúscula inicial.
- Cada fila lleva un círculo (vacío si está pendiente, ✓ si está comprado y una casa si es «ya lo tengo»), el nombre (tachado si está comprado), la cantidad a la derecha («2 kg», «3 ud», con el mismo formato que `ShoppingFormat.quantity`) y el detalle «Para: Lentejas, Ensalada» con los platos distintos de `sources[].name`.
- Estado vacío: «La compra está vacía. Acepta el menú de la semana o añade algo a mano.»
- En iOS además se añade a mano, se edita la cantidad, se borra, «Vaciar comprados» y el modo revisión. **Nada de eso va en la pared** (no hay teclado cómodo y lo hace el móvil).

**Backend que ya existe (master).** Sin cabecera `X-Home-Id`, el hogar sale de `fn_home_for_root_create()`. La pantalla vinculada (0049/0050) tiene `calendar.view`, `task.view`, `menu.view` y `task.complete`.
- `GET /meal/plan?week_start=YYYY-MM-DD` (`get_meal_plan`, `menu.view`). Devuelve `null` si no hay plan, o `{id, week_start, status: draft|accepted, revision, items:[{id, day, slot, position, kind, recipe_id, title, servings, cook_member_id, members:[member_id]}]}`. Las franjas (`slot`) son `breakfast`, `midmorning`, `lunch`, `snack` y `dinner`. Los tipos (`kind`) son `recipe`, `free_text`, `leftovers` y `eat_out`. **`week_start` tiene que coincidir con el inicio de semana del hogar** (`meal_profile.week_start_day`, 1 = lunes; ver `fn_meal_week_of`), no siempre es lunes.
- `GET /meal/profile` (`menu.view`): de aquí se sacan `week_start_day`, `slots` (`slot`, `enabled`, `time`) y, si se pintan comensales, `members` (`home_member_id`, `name`, `color`). **Ojo: la respuesta trae alergias, dieta y otros datos de salud.** En el modelo Kotlin declara solo los campos que se usan, para que nunca lleguen a la caché en disco ni a los logs.
- `GET /meal/today` (`get_meals_today`): ya lo usa `MealRepository` para «Hoy se come». Trae `now_local` y la hora de cada franja de hoy.
- `GET /shopping` (`list_shopping`, `menu.view`): `{revision, items:[{id, label, food_id, quantity, unit, section, origin: manual|menu, plan_id, sources, qty_overridden, state: pending|checked|skipped, checked_at, checked_by, …}]}`.
- `PATCH /shopping/item/check` `{id, state}` (`set_shopping_item_state`) **exige `menu.shopping.edit`, que la pantalla no tiene**. Ver la fase B.

## Diseño propuesto

Lienzo útil: 1920 − 136 (barra) = 1784 × 1200 px. Se lee desde 2–3 m, así que el texto mínimo es `Type.Small` (24) y los platos van en `Type.Body` (29). Áreas táctiles de 64 px como mínimo. Sin animaciones continuas: el marco se calienta.

### 1. Cabecera común (Menú y Compra)

Una fila de 84 px arriba (padding como en `ScreenPadding`):
- A la izquierda, el título «Menú» en `Type.Title` SemiBold y debajo, o al lado en `Type.Large` `InkSoft`, el rango de la semana con `weekRange()` («23 – 29 de noviembre»). En Compra, en su lugar, «N pendientes».
- En el centro o a la derecha, un **selector segmentado de dos píldoras**, «Semana» y «Compra», de 84 px de alto. La activa en `Palette.Ink` con texto `Card` y la otra en `Card`, como `PillButton(primary)`. La de Compra lleva el número de pendientes en una píldora `Sage`.
- A la derecha, solo en Semana, **‹ ›** como botones redondos de 84 px (icono `ChevronLeft`/`ChevronRight` de 40 px sobre `Card`) y, si no estás en la semana actual, «Volver a esta semana» como `PillButton` primario (mismo comportamiento que «Volver a hoy» del Calendario). Se puede navegar como mucho 1 semana atrás y 2 adelante: hay menús planificados como mucho para la siguiente.

La barra sigue teniendo un solo botón «Menú» (`Icons.Outlined.Restaurant`). Al entrar se abre siempre en **Semana**. La vuelta a Hoy tras 2 min sin tocar ya existe y vale. Además, **tocar la tarjeta «Hoy se come» de Hoy abre Menú › Semana** (como la del tiempo abre Tiempo).

### 2. Semana

Rejilla de **7 tarjetas de día** (lunes a domingo, o desde `week_start_day`), separadas 14 px como en `CalendarScreen`, con las **franjas alineadas en filas** entre todas las tarjetas:

- **Columna de franjas a la izquierda** (≈150 px, sin tarjeta): por cada franja, un icono de 36 px en `Sage` (sugerencia: `FreeBreakfast` desayuno, `BakeryDining` media mañana, `LunchDining` comida, `Cookie` merienda, `DinnerDining` cena), el nombre en `Type.Small` `InkSoft` y la hora de la franja en `Type.Tiny` `InkMuted` (de `slots[].time`).
- **Qué franjas salen**: las `enabled` del perfil. Si una franja habilitada no tiene ninguna casilla en toda la semana, se oculta. El alto se reparte con `weight` entre las franjas visibles, y la cena y la comida pesan más (por ejemplo 1.2) que desayuno y merienda (0.8). Así la pantalla se llena de arriba abajo y no queda media pantalla vacía como ahora.
- **Tarjeta del día**: cabecera como `DayCard` («Lun» a la izquierda, «23» a la derecha en `Type.Large` SemiBold). Hoy dice «Hoy» y lleva el número en `Accent`. Debajo, un `Hairline` y, por cada franja, una celda separada por `Hairline`.
  - **Hoy**: `Card` opaca, con un borde de 3 px en `Sage` al 40 %.
  - **Otros días**: `Card` al 55 %.
  - **Días pasados**: `alpha(0.6f)`.
- **Celda con plato**: el título en `Type.Body` (29) `Ink`, hasta 3 líneas con elipsis, alineado a la izquierda (no centrado: centrado y partido en tres líneas es lo que hace difícil leer la captura). Si `members` no es toda la gente que come en casa, van `PersonInitials` de 26 px debajo. Si hay varias casillas en la misma franja (`position`), se apilan con 8 px de separación.
- **Celda de la franja actual (hoy)**: fondo `Highlight`, barra izquierda de 5 px en `Sage` y el título en SemiBold. La franja actual se calcula con la misma lógica que `MealsTodayState`, con la hora del hogar.
- **Tipos especiales**:
  - `eat_out`: icono `Storefront` 28 px + «Comen fuera» en `Type.Small` `Sage`, en cursiva (o el título si lo trae).
  - `leftovers`: píldora «Sobras» en `Warm` al 15 % y, debajo, el título.
  - `free_text`: como un plato.
- **Celda vacía**: nada de «—». Un texto «Sin plan» en `Type.Tiny` `InkMuted` al 60 %, o directamente la celda en blanco. Elige lo que se lea más limpio en el emulador y enséñalo en las capturas.

**Estados de la semana:**
- **Sin plan** (`null`): `EmptyState(large = true)` con el icono `Restaurant` en `Sage`, «Sin menú esta semana» / «Planifícalo desde la app Homita». Las flechas siguen activas.
- **Plan en borrador** (`status = draft`): no se pinta el borrador (puede cambiar en cualquier momento). Se pinta `EmptyState`: «El menú de esta semana está en preparación» / «Aparecerá aquí cuando se acepte en la app». Coherente con «Hoy se come», que solo enseña el plan aceptado.
- **Sin red**: la última copia de esa semana (stale-if-error); el estado de la barra (`RailStatus`) ya avisa. Sin copia: `EmptyState` «Sin conexión».
- **403/400** (sin `menu.view` o sin hogar): el botón «Menú» desaparece de la barra (mismo criterio que la tarjeta de Hoy, que se oculta).

### 3. Compra

Layout en dos zonas:

**Izquierda (≈ 2/3): la lista**, en columnas de `Panel`, como en `TasksScreen`. Las secciones (en el orden de `sectionOrder`, solo las que tienen artículos) se reparten en **3 columnas equilibradas por número de filas** (cada sección entera en una columna, sin partirla), y cada columna lleva `fadingScroll` si no cabe.
- **Cabecera de sección**: `SectionLabel` («VERDURA», «LÁCTEOS»…) en `Accent`, con el número de pendientes a la derecha.
- **Fila** (mínimo 72 px de alto, toda la fila es táctil en la fase B): círculo de 40 px a la izquierda (vacío `InkMuted`, ✓ relleno `Sage` si está comprado, casa `Sage` si es «ya lo tengo»), el nombre en `Type.Body`, la cantidad a la derecha en `Type.Small` `InkSoft` y, debajo del nombre, «Para: Lentejas con chorizo» en `Type.Tiny` `InkMuted`, una línea con elipsis (solo si viene del menú). Los añadidos a mano no llevan detalle.
- **Orden dentro de la sección**: pendientes primero (por nombre) y luego comprados, tachados y en `InkMuted`. Los «ya lo tengo» (`skipped`) no se listan aquí: solo se cuentan en el resumen.

**Derecha (≈ 1/3): una `Panel` de resumen**, con `CardHeader("Compra", Icons.Outlined.ShoppingCart, Palette.Sage, count = pendientes)`:
- El número grande de pendientes (`Type.Huge` a 96 px) y debajo «por comprar».
- Una barra de progreso de 12 px (`Line` de fondo, `Sage` de relleno) y «12 de 30 comprados».
- Líneas en `Type.Small`: «Del menú: 22 · A mano: 8», «Ya lo tenéis: 4» y, si el perfil tiene `shopping_day`, «Día de compra: sábado» («Hoy toca compra» en `Accent` si es hoy).
- Abajo, en `Type.Tiny` `InkMuted`: «Para añadir o cambiar cantidades, usa la app Homita».

**Estados de la Compra:**
- **Vacía**: `EmptyState(large = true)` con `ShoppingCart` en `Sage`, «La compra está vacía» / «Acepta el menú de la semana o añade algo desde la app».
- **Todo comprado**: `EmptyState` con `TaskAlt` en `Online`, «Todo comprado» y el resumen.
- **Sin red / 403**: igual que en Semana.

### 4. Interacción en la pantalla táctil

- **Fase A (solo lectura).** Selector Semana/Compra, flechas de semana, «Volver a esta semana», tocar «Hoy se come» y desplazar las columnas de la Compra. Las filas no reaccionan al tocarlas.
- **Fase B (marcar comprado, decidido por Damian; ver «Decisión tomada»).** Tocar una fila la marca como comprada al momento (optimista) y aparece el «Deshacer» de 5 s que ya existe para las tareas. La petición sale al acabar ese tiempo. Sin red, va a la cola en disco y se envía al volver. Con 403 o 404 se revierte y se avisa con `completionNotice`. Tocar una comprada la vuelve a pendiente. «Ya lo tengo», borrar, cantidades y altas siguen siendo solo del móvil.

## Datos y refresco (Android)

- `Api.kt`: `GET meal/plan?week_start=`, `GET meal/profile` y `GET shopping`, con el mismo esquema de auth que `mealsToday` (Bearer, sin `X-Home-Id`).
- Repositorios con `DiskCache` + `CachedResource` (stale-if-error), como `MealRepository`:
  - Plan: una clave por semana (`mealplan-<week_start>`), y solo se guardan la semana anterior, la actual y las dos siguientes.
  - Perfil: solo los campos seguros (`week_start_day`, `shopping_day`, `slots`, `members.{home_member_id,name,color}`), refresco cada hora.
  - Compra: refresco cada 60 s mientras está en pantalla y cada 5 min fuera de ella, usando `revision` para no repintar si no ha cambiado.
- Si la pantalla local ya tiene repositorio o modelo, reutilízalos y quita lo que sobre.
- Estado en `UiState` / `DashboardViewModel` siguiendo el patrón de `meals` y `shownWeeks`. Al cerrar sesión, `clear()` borra las cachés nuevas (como `mealRepository.clear()`).
- **Lógica pura con tests JUnit4**, en `data/`, en el estilo de `MealsTodayState`:
  - Inicio de semana según `week_start_day`.
  - Franjas visibles de la semana (habilitadas y con alguna casilla).
  - Franja actual de hoy.
  - Agrupar y ordenar la Compra por sección y estado.
  - Reparto de secciones en 3 columnas.
  - Formato de cantidades (portado de `ShoppingFormat.quantity`, con decimales con coma: «0,5 kg»).
  - Resumen de la Compra (pendientes, comprados, origen, «ya lo tenéis»).

## Backend (solo fase B)

- Migración nueva, con el **siguiente número libre** (master llega a **0054** el 28-11; compruébalo con `git fetch`). Un permiso `menu.shopping.check` (o el nombre que encaje con el catálogo; explícalo) que deja **marcar y desmarcar** (`pending` ↔ `checked`) y nada más. Se concede a las pantallas en `fn_display_link_complete`, con backfill para las ya vinculadas, igual que hizo 0050 con `task.complete`.
- `set_shopping_item_state`: una pantalla pasa con `menu.shopping.check` solo para `pending`/`checked`, y `skipped` sigue exigiendo `menu.shopping.edit`. Registro en `audit_log` con `source: display`. Usa `client_request` para que un toque repetido sin red no se duplique.
- Rollback en `scripts/supabase/rollback/`, check SQL en `scripts/supabase/tests/` añadido a `ci.sh`, tests Deno de la ruta y casos en `cross_tenant_check.py`: la pantalla de A no marca artículos de B, y no puede crear, borrar, cambiar cantidades ni poner `skipped`.

## Qué hacer

1. Change `.dorch/changes/dashboard-menu-compra/` (`brief.md` con este documento y el contexto que necesites de `docs/dashboard-mejora/brief.md`, + `status.md`), rama `dc/dashboard-menu-compra` desde `origin/master`, worktree `../Homita-dashboard-menu-compra`.
2. Localiza la pantalla Menú local (ver Contexto) y confirma con qué endpoint lee hoy.
3. **Fase A**: la cabecera, la Semana y la Compra en solo lectura, el toque de «Hoy se come», los repositorios, los tests y los datos de demo. `scripts/demo/seed.py` hoy no crea menú ni compra: añade un plan aceptado de la semana actual (con un `eat_out`, unas sobras y una merienda suelta, como en la captura) y una compra con unos 25 artículos en 6 o más secciones, con algunos comprados, algún «ya lo tengo» y algún manual. Fechas relativas al día, como el resto del seed.
4. **Para, pasa capturas de la fase A a Damian y espera su visto bueno** antes de la fase B.
5. **Fase B**: el backend de arriba, y en Android el toque optimista con «Deshacer» y la cola sin red, reutilizando lo de `dashboard-marcar-hecho` (`Completion`, `pending`/`queued`).
6. Docs: sección del Menú y la Compra en `docs/ARCHITECTURE.md`, y en el README del dashboard qué escribe la pantalla.

## Decisión tomada

**La Compra de la pared marca artículos como comprados: sí, solo marcar y desmarcar** (Damian, 28-11-2026). La fase B se hace, tras el visto bueno de las capturas de la fase A.

## Criterios de aceptación

**Fase A**
- [ ] Menú usa solo piezas y tokens del sistema (`Palette`, `Type`, `Panel`/`Card`, `CardHeader`, `EmptyState`, `SectionLabel`, `Hairline`, `PillButton`). No quedan colores ni tamaños sueltos, salvo los nuevos que se documenten.
- [ ] Hoy se distingue a 3 m: «Hoy» en `Accent`, tarjeta opaca con borde salvia y franja actual resaltada. Los días pasados van atenuados.
- [ ] No hay «—». Las franjas sin casillas en toda la semana no ocupan sitio y la rejilla llena el alto disponible.
- [ ] `eat_out` y `leftovers` se distinguen de un plato.
- [ ] Ningún texto de dato baja de 24 px y los platos van a 29 px. Todo lo táctil mide 64 px o más.
- [ ] Las flechas respetan `week_start_day`, y «Volver a esta semana» aparece fuera de la semana actual.
- [ ] El selector Semana/Compra funciona, Menú abre siempre en Semana, «Hoy se come» lleva a Semana y la vuelta a Hoy tras 2 min sigue funcionando.
- [ ] La Compra va agrupada por sección en el orden de iOS, con cantidad, «Para: …» y comprados tachados al final. El resumen cuadra con los datos.
- [ ] Los estados vacío, borrador, sin red (con y sin copia) y 403 tienen la pantalla descrita.
- [ ] Ningún dato de salud del perfil se guarda en disco ni sale en los logs (lo cubre un test del modelo).

**Fase B**
- [ ] La pantalla solo puede poner `pending` ↔ `checked` en su hogar, lo cubre cross-tenant, y queda en `audit_log`.
- [ ] Toque optimista, «Deshacer» de 5 s, cola sin red que se recupera al volver la red y reversión con 403/404.

## Verificación

- `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` en `apps/dashboard`.
- Fase B: tests Deno, `scripts/supabase/ci.sh` (check SQL nuevo y cross-tenant).
- **Emulador** (`Frame_API_29`, 1920×1200, ver `docs/ARCHITECTURE.md`): `scripts/demo.sh app`. Capturas con `adb exec-out screencap -p > x.png` de:
  1. Semana actual con hoy y la franja actual resaltados.
  2. La semana siguiente con «Volver a esta semana».
  3. Semana sin plan.
  4. Plan en borrador.
  5. Compra con datos.
  6. Compra vacía.
  7. Sin red (modo avión del AVD) con copia.
  8. Hoy → tocar «Hoy se come» → Semana.
  9. Fase B: marcar, deshacer, y marcar sin red y recuperar.

  Compara la 1 con `docs/images/dashboard-menu-actual.png`.

## Reglas

- Nada en producción: no apliques migraciones, no despliegues la Edge ni instales en el marco real. Sin push ni PR (status sin `authorized: push pr gh`). Nunca merge.
- Rutas nuevas de `api`, si hacen falta, aditivas al contrato (D-008) y con el estilo de nombres que ya hay. Casos de uso en `usecases/`.
- Android: `Density(1f)`, minSdk 29, sin librerías nativas nuevas (los iconos salen de `material-icons-extended`, que ya está) y nada de animaciones continuas nuevas.
- Actualiza `docs/ARCHITECTURE.md` y el README del dashboard con lo que cambie.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env` ni valores de env.

## Al terminar, infórmame de

Dónde estaba la pantalla local y qué reutilizaste. Capturas de la fase A y parada. Después de la fase B: hash, tests (número y fallos), migración usada y capturas.
