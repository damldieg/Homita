# Mejorar el dashboard de pared: auditoría y fases

Pedido por Damian el 2026-11-22 y revisado el 2026-11-26 sobre `origin/master` 8abb1e6. Auditoría de la
app del marco (`apps/dashboard`, Android, 1920×1200, `Density(1f)`), no de la pestaña Inicio de iOS.
Este documento es la base de los changes `dashboard-sesion`, `dashboard-hoy-legible`,
`dashboard-pantalla-hogar`, `dashboard-marcar-hecho` y `dashboard-actualizacion-remota`. Se pasa a dorch
junto con el prompt de cada paso.

Documento de la auditoría con la comparativa y la matriz impacto × esfuerzo:
https://claude.ai/artifact/FVqLoG2wMYdwhKFk5iZaYf

## Resumen

Como pantalla de consulta funciona muy bien (reloj nocturno, caché sin red, tiempo, «lo siguiente» con
cuenta atrás). Como producto para vender le fallan tres cosas:

1. **La sesión caduca cada 7 días.** El JWT no se refresca y un 401 borra la sesión
   (`DashboardViewModel.kt`, `error.isUnauthorized -> logout()`); `docs/ARCHITECTURE.md` lo documenta
   como «re-login semanal». La Edge ya devuelve `refresh_token` en `POST /user/auth`.
2. **El acceso es de una persona, no del hogar.** Se teclea email y contraseña en la pared, y la pantalla
   enseña lo que esa persona marcó en «Mostrar en el dashboard». El menú (`GET /meal/today`) usa «el hogar
   por defecto de la cuenta».
3. **Solo se puede mirar.** No se marca nada como hecho ni se ve «lo de cada persona».

## Qué hay hoy en master (2026-11-26)

- Pantallas: Hoy, Calendario (2 semanas), Tiempo (2 páginas), Tareas (columnas por lista, orden y
  filtro de prioridad), Ajustes, Reloj nocturno. Barra lateral solo con iconos, con «sincronizar» y
  «apagar pantalla» al nivel de las secciones. Vuelve a Hoy tras 2 min sin tocar.
- Datos: `GET /event?dashboard=true`, `GET /task?dashboard=true` cada 5 min, `GET /meal/today`,
  Open-Meteo cada 30 min (14 días). Todo con `DiskCache` + `CachedResource` (stale-if-error).
- Desde el 22/11 se añadió: tarjeta «Hoy se come» en la columna del reloj (1 casilla si hay siguiente
  evento, 2 si no; `MealsTodayState.MAX_ROWS`) y aviso de fecha límite (0041) para tareas de prioridad
  alta (`TaskDue.banner`, `DueBannerRow`) y «Vence dd/MM HH:mm» en cada fila de Tareas.
- Backend que ya existe y sirve: `PATCH /task/complete` (escritura con el JWT del usuario), personas de
  tarea (`task_person`, 0024), filtro por persona en iOS (Mis tareas), escrituras de Kito con
  confirmación (`asistente`, skill `organizar`).
- Instalación y actualización solo por ADB (`scripts/install.sh`). El XORO CPF 10PF no tiene micrófono
  documentado (`docs/FRAME.md`).

## Hallazgos

Impacto y esfuerzo: A alto, M medio, B bajo.

### Mejorar UX
| # | Hallazgo | Propuesta | Imp. | Esf. |
|---|---|---|---|---|
| U1 | Re-login semanal | Guardar y usar `refresh_token`; si falla, pantalla «vuelve a vincular» en vez del formulario | A | B |
| U2 | Hoy: reloj (1/3) y tiempo (2/3) llenan el 55 % del alto; eventos y rutinas salen cortados | Reloj más pequeño, tiempo en franja compacta, agenda de hoy como bloque principal | A | M |
| U3 | Horas, chips de persona y rutinas del Calendario en 16–20 px; lo pasado en gris muy claro | Mínimo ~24 px para lo que se lee de pie; atenuar sin perder contraste | A | B |
| U4 | Sin vista por persona aunque cada persona tiene color | Tocar un avatar filtra Hoy, Calendario y Tareas (vuelve solo a los 2 min) | A | M |
| U5 | Calendario: rutinas diarias repetidas 14 veces, media tarjeta por día | Ocultar o resumir las diarias («+3 rutinas») | M | B |
| U6 | Barra solo con iconos; acciones al nivel de secciones | Etiqueta corta bajo cada icono; acciones fuera de la navegación | M | B |
| U7 | «Sin conexión» pequeño; no se sabe de cuándo son los datos | «Actualizado hace 2 h» si los datos tienen más de 15 min | M | B |
| U8 | Tareas sin personas asignadas | Mostrar las personas de cada tarea; destacar prioridad alta | M | B |
| U9 | Ajustes de Android, Wi-Fi, Cerrar sesión y Apagar a un toque para cualquiera | Pulsación larga o PIN del hogar | M | B |

### Hallazgos nuevos del 26/11 (aviso de vencimiento y menú)
| # | Hallazgo | Propuesta | Imp. | Esf. |
|---|---|---|---|---|
| N1 | El aviso deja de salir cuando la tarea vence: solo fechas futuras (`TaskDue.banner`, `isAfter(now)`) | Mantener la vencida en rojo («Vencida hace 2 h») hasta completarla | A | B |
| N2 | «Vence a las 19:00» sin día aunque venza la semana que viene | «Hoy 19:00», «Mañana 19:00», «vie 4 dic 19:00»; avisar solo con < 24–48 h | A | B |
| N3 | El aviso es una fila nueva sobre la rejilla y quita alto a todo Hoy | Integrarlo en la columna de «lo siguiente» o franja fina sobre el tiempo | M | B |
| N4 | «Cerrar» es texto con poca área táctil; el cierre se pierde al reiniciar | Botón de 64 px; recordar el cierre en disco por tarea y fecha | B | B |
| N5 | «Hoy se come» cabe con 1 casilla en la columna más llena | Darle sitio propio (hueco de Tiempo, Q2, o tarjeta junto a Rutinas) | M | M |
| N6 | Un 403/400 de `/meal/today` oculta la tarjeta sin decir nada | Correcto, pero dejarlo visible en un diagnóstico de Ajustes | B | B |

### Añadir
| # | Funcionalidad | Imp. | Esf. |
|---|---|---|---|
| A1 | Vinculación por código o QR desde la app iOS | A | M |
| A2 | Marcar tarea hecha con un toque (deshacer 5 s) | A | M |
| A3 | Rutinas hechas por persona (necesita modelo nuevo) | A | A |
| A4 | Comidas de hoy (hecho en parte) y Compra en pantalla | A | M |
| A5 | «Buenos días»: lo de hoy por persona + ropa según el tiempo (tier Plus, resumen de Kito) | M | M |
| A6 | Fotos del hogar como salvapantallas (1 GB de RAM, almacenamiento) | M | M |
| A7 | Actualización remota de la app y diagnóstico | A | A |
| A8 | Ajustes de la pantalla desde el móvil (horario, ubicación, brillo, calendarios y listas) | M | M |
| A9 | Calendarios externos (Google, iCloud, Outlook) de solo lectura | A | A |
| A10 | Kito en la pantalla (sin micrófono en el XORO) | B | A |

### Cambiar
| # | Hoy | Propuesta |
|---|---|---|
| C1 | La pantalla es la sesión de una persona | Pantalla vinculada al hogar, con su propia selección de calendarios y listas |
| C2 | Calendario del mes en Hoy solo con puntos | «Próximos 3 días» con títulos; el mes queda en Calendario |
| C3 | Calendario de 2 semanas en columnas estrechas | Añadir vista «hoy y mañana por persona» (más adelante) |
| C4 | Sincronizar es un botón manual de la barra | Pasarlo a Ajustes; en la barra solo el estado |
| C5 | Chips de orden y prioridad arriba en Tareas | Orden fijo por prioridad y filtro por persona (U4) |
| C6 | La ubicación del tiempo se busca en el marco | Tomarla del hogar (A8), buscador como alternativa |

### Quitar
| # | Qué | Por qué |
|---|---|---|
| Q1 | Segunda página de Tiempo (días 8–14) | Previsión poco fiable; pide 14 días cada 30 min |
| Q2 | Tiempo como sección de primer nivel | Repite la tarjeta de Hoy; deja hueco para Comidas |
| Q3 | Reloj de la barra lateral estando en Hoy | Duplica el reloj grande |
| Q4 | Formulario de email y contraseña | Lo sustituye la vinculación (A1); queda como modo técnico |
| Q5 | Botón de sincronizar de la barra | Ver C4 |

No quitar el reloj de paletas: es la seña de identidad. Solo hacerlo más pequeño (U2).

## Orden

| Paso | Change | Qué cubre | Toca | Necesita |
|---|---|---|---|---|
| 01 | `dashboard-sesion` | U1 | Edge + Android | nada |
| 02 | `dashboard-hoy-legible` | U2, U3, U5–U9, C2, C4, C5, Q1–Q3, Q5, N1–N5 | Android | nada (en paralelo a 01) |
| 03 | `dashboard-pantalla-hogar` | A1, C1, A8, C6, Q4, N6 | BD + Edge + iOS + Android | 01 |
| 04 | `dashboard-marcar-hecho` | A2, U4 | Edge + Android | 02 y 03 |
| 05 | `dashboard-actualizacion-remota` | A7 (+ diagnóstico) | Android + scripts (+ Edge) | 03 |

Fuera de estos pasos, para más adelante: A3, A5, A6, A9, A10, C3 y la Compra en pantalla (A4).

`dashboard-sesion` se separa de la vinculación porque arregla el problema más visible con poco riesgo y
no depende de decidir el modelo de «pantalla del hogar».

## Decisiones abiertas (Damian)

1. ¿La pantalla puede escribir (paso 04) o sigue siendo de solo lectura y se marca desde el móvil?
   Recomendado: escribir, solo completar/descompletar tareas.
2. ¿Hardware de venta = XORO o tablet con micrófono? Cambia la prioridad de A6 y A10.
3. Paso 03: ¿la pantalla tiene identidad propia (cuenta técnica del hogar) o actúa en nombre del adulto
   que la vinculó? Recomendado: identidad propia, con permisos de solo lectura + completar tareas.
4. Paso 02: diseño de Hoy. El prompt pide 2 propuestas antes de implementar.
