# B4 — Diseño en papel: Inicio (versión mínima) y Hogar

Tarjeta Trello: https://trello.com/c/rygPcyhT · Doc de rediseño: `.dorch/changes/control-ios-redesign-audit/docs/CONTROL_REDESIGN.md` (§5.1, §5.5, B4).

**Diseño visual (canvas):** https://claude.ai/artifact/QECVsJ4WStW5qGnUsWhRgr — dos artboards de 390×844 (Inicio versión mínima y Hogar).

Es diseño en papel: no implementa código. La adopción espera a que Homita Foundation cierre (rutas `/home/*`, migración DP-1).

## Lenguaje visual

Mismo sistema que Control iOS (`apps/control-ios/Sources/ControlKit/Theme/Palette.swift`):

| Token | Valor |
|---|---|
| Fondo | `#F7EEE2` |
| Tarjeta | `#FFFDF9`, borde `#EFE2D0` |
| Línea | `#EADBC6` |
| Tinta | `#221D18` |
| Tinta suave | `#6E6358` |
| Acento | `#C8243B` |
| Online | `#3BA55C` |

Tipografía: Geist en títulos (como en la app); etiquetas de sección en mayúsculas, 13 px, semibold, tinta suave. Tarjetas de 16 px de radio, sin degradados.

## Navegación

Opción A recomendada (§4.1, DP-4 sin cerrar hasta Fase C): tab bar de 5 pestañas — **Inicio · Tareas · Calendario · Hogar · Perfil**.

## Inicio (versión mínima)

Orden de secciones, de arriba abajo:
1. Saludo y fecha: «Hola, [NOMBRE]» con la fecha del día.
2. **Hoy · Eventos**: eventos del día y de varios días que tocan hoy, ordenados por hora. Fuente: `GET event` por ventana de fechas (contrato actual).
3. **Tareas pendientes**: pendientes destacadas. Fuente: contrato actual de tareas.
4. **Rutinas de hoy**: cálculo en cliente con `RoutineRule.occurs(on:)`.
5. **Accesos rápidos**: «+ Tarea» (acento) y «+ Evento».

Sin estadísticas ni contenido inventado: los datos reales van en placeholders marcados con corchetes.

## Hogar

Orden de secciones:
1. Título «Hogar» y **selector de hogar activo** (nombre del hogar y «Cambiar»).
2. **Miembros**: cada uno con inicial, nombre, indicador «tú» si corresponde, permisos del catálogo y **tipo**: adulto, niño, familiar, invitado o mascota (D-010).
3. **Invitar**: código copiable de invitación, con la lista de tipos (D-010: invitación por código, no por email).

El rol y los permisos se muestran como texto del catálogo; no se diseña un editor de permisos en esta versión.

## Criterios de aceptación (tarjeta)

- **CA-1:** cada sección de Inicio se puede servir con el contrato actual (eventos por día, tareas, cálculo cliente de rutinas). Cumple: ninguna sección depende de `/home/*`.
- **CA-2:** el wireframe de Hogar cubre selector, miembros, permisos e invitación por código sin rediseño cuando Foundation despliegue `/home/*`. Cumple: los cuatro bloques están presentes.
- **CA-3:** DP-4 y DP-5 quedan argumentadas y DP-1 a DP-8 con propietario de decisión (matriz abajo).

## Matriz DP-1 a DP-8

| DP | Decisión | Qué aporta este diseño | Propietario |
|---|---|---|---|
| DP-1 | Mapeo Person → HomeMember | Hogar muestra miembros con tipo (sección 2 de Hogar); permite validar cómo se listan las personas migradas | Foundation (migración, 1.2) |
| DP-2 | Futuro de compartir por recurso (`MembersSection`) | Hogar reemplaza la invitación por email con código copiable; la UX de compartir por recurso queda fuera del diseño | Foundation (rutas) + rediseño (Fase C) |
| DP-3 | Branding Planify → Homita | Usa el nombre «Homita» en el canvas pero no define branding; los títulos siguen la paleta actual | Producto (diferido por D-003) |
| DP-4 | Navegación tab-based vs pantalla única | La tab bar de 5 pestañas es la Opción A recomendada; se cierra en Fase C | Producto (Fase C post-Foundation) |
| DP-5 | Detalle en push vs sheet | Inicio enlaza a eventos y tareas; el diseño no fija push vs sheet, solo indica la acción | Producto (Fase C, recomendado: push para detalle, sheet para alta) |
| DP-6 | TestFlight ahora o al terminar | No aplica al diseño; condiciona la validación con la familia | Producto / presupuesto |
| DP-7 | EventKit / Apple Calendar | Sin diseño de sincronización (fuera de alcance) | Foundations 2.10 |
| DP-8 | `user/update` sin contraseña actual | No aplica al diseño; revisar en seguridad backend | Foundation / seguridad |

## Fuera de alcance

- Implementación de vistas SwiftUI, stores o rutas.
- Branding (DP-3).
- Evolucionar `MembersSection` más allá de lo actual (obsoleto con D-010).
- Sincronización con Apple Calendar (DP-7).
