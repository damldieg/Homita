// Caracterización de la skill `organizar` (change mcp-organizar, T3): escenarios que fijan los cuerpos que Kito
// envía al api y lo que devuelve cada herramienta, ANTES de mover su lógica a `_shared/homita/organizar/`.
// Los resultados esperados están en `organizar_caracterizacion.json`; los tests los comparan tal cual.
import { HERRAMIENTAS_CALENDARIOS } from "../skills/organizar/calendarios.ts";
import { HERRAMIENTAS_EVENTOS } from "../skills/organizar/eventos.ts";
import { HERRAMIENTAS_LISTAS } from "../skills/organizar/listas.ts";
import { HERRAMIENTAS_RUTINAS } from "../skills/organizar/rutinas.ts";
import { HERRAMIENTAS_TAREAS } from "../skills/organizar/tareas.ts";
import { ejecutarAccion, OPS } from "../skills/organizar/acciones.ts";
import { esNoExiste, traducir } from "../skills/organizar/errores.ts";
import { ctxDe, escritorFalso, fallo, lectorFalso, ok, SECRETO } from "./organizar_util.ts";
import type { Respuestas } from "./organizar_util.ts";

const TODAS = [
    ...HERRAMIENTAS_LISTAS, ...HERRAMIENTAS_TAREAS, ...HERRAMIENTAS_EVENTOS, ...HERRAMIENTAS_RUTINAS, ...HERRAMIENTAS_CALENDARIOS,
];
const tool = (n: string) => TODAS.find((t) => t.name === n)!;

const LISTAS = [
    { id: 1, name: "Casa", color: "#112233", sort: "title", widget: 0, dashboard: 1, pending_task_count: 3, can_edit: true },
    { id: 2, name: "Compra", color: "#445566", widget: true, dashboard: false, pending_task_count: 0, can_edit: true },
    { id: 3, name: "Solo lectura", color: "#000000", can_edit: false },
];
const UNA_LISTA = [LISTAS[1]];
const CALENDARIOS = [
    { id: 10, name: "Familia", color: "#aa0000", widget: 1, dashboard: 0, can_edit: true },
    { id: 11, name: "Fútbol", color: "#00aa00", widget: true, dashboard: true, can_edit: true },
];
const UN_CAL = [CALENDARIOS[0]];
const PERSONAS = [
    { id: 20, name: "Lucía", app_user_id: 502, home_id: 7 },
    { id: 21, name: "Pedro", app_user_id: null, home_id: 7 },
    { id: 22, name: "Yo", app_user_id: 501, home_id: 7 },
];
const TAREA = { id: 5, title: "Llamar", task_list_id: 2, priority: "media", person_ids: [20], due_at: "2026-11-30 10:00:00" };
const EVENTO = { id: 6, title: "Cena", date_at: "2026-12-01 20:30:00", end_date: null, alarm: 15, person_ids: [20] };
const RUTINA = {
    id: 7, title: "Regar", frequency: "weekly", interval: 2, days: [1, 3], time: "08:30:00", start_date: "2026-11-01",
    end_date: "2027-01-01", active: true, person_ids: [20],
};
const DETALLES: Respuestas = {
    "GET task/detail": ok(TAREA), "GET event/detail": ok(EVENTO), "GET routine/detail": ok(RUTINA),
};

export interface Escenario {
    nombre: string;
    herramienta: string;
    input: Record<string, unknown>;
    leer?: Record<string, unknown>;
    resp?: Respuestas;
    /** Sin secreto de confirmación (los borrados se niegan). */
    sinSecreto?: boolean;
    toolUseId?: string;
    escrituras?: number;
    sinLector?: boolean;
}

export const ESCENARIOS: Escenario[] = [
    // listas
    { nombre: "crear_lista", herramienta: "crear_lista", input: { nombre: "  Viaje " }, toolUseId: "t1" },
    { nombre: "crear_lista con color", herramienta: "crear_lista", input: { nombre: "Viaje", color: "#AABBCC" }, toolUseId: "t2" },
    { nombre: "crear_lista sin toolUseId", herramienta: "crear_lista", input: { nombre: "Viaje" } },
    { nombre: "crear_lista sin nombre", herramienta: "crear_lista", input: {} },
    { nombre: "crear_lista color malo", herramienta: "crear_lista", input: { nombre: "A", color: "rojo" } },
    { nombre: "crear_lista error 400", herramienta: "crear_lista", input: { nombre: "A" }, resp: { "POST task-list/create": fallo(400, "Name is required") } },
    { nombre: "crear_lista error 403", herramienta: "crear_lista", input: { nombre: "A" }, resp: { "POST task-list/create": fallo(403, "Not Allowed") } },
    { nombre: "editar_lista solo nombre", herramienta: "editar_lista", input: { id: 1, nombre: "Casa 2" }, leer: { "task-list": LISTAS } },
    { nombre: "editar_lista solo color", herramienta: "editar_lista", input: { id: 2, color: "#FFFFFF" }, leer: { "task-list": LISTAS } },
    { nombre: "editar_lista sin cambios", herramienta: "editar_lista", input: { id: 1 }, leer: { "task-list": LISTAS } },
    { nombre: "editar_lista sin id", herramienta: "editar_lista", input: { nombre: "X" }, leer: { "task-list": LISTAS } },
    { nombre: "editar_lista inexistente", herramienta: "editar_lista", input: { id: 99, nombre: "X" }, leer: { "task-list": LISTAS } },
    { nombre: "borrar_lista con pendientes", herramienta: "borrar_lista", input: { id: 1 }, leer: { "task-list": LISTAS } },
    { nombre: "borrar_lista sin pendientes", herramienta: "borrar_lista", input: { id: 2 }, leer: { "task-list": LISTAS } },
    { nombre: "borrar_lista inexistente", herramienta: "borrar_lista", input: { id: 99 }, leer: { "task-list": LISTAS } },
    { nombre: "borrar_lista sin secreto", herramienta: "borrar_lista", input: { id: 1 }, leer: { "task-list": LISTAS }, sinSecreto: true },
    { nombre: "borrar_lista sin lector", herramienta: "borrar_lista", input: { id: 1 }, sinLector: true },
    // tareas
    { nombre: "crear_tarea lista única", herramienta: "crear_tarea", input: { titulo: "Pan", prioridad: "alta", persona_ids: [20, 20, 21] }, leer: { "task-list": UNA_LISTA }, toolUseId: "t3", resp: { "POST task/create": ok({ id: 8 }, 201) } },
    { nombre: "crear_tarea varias listas", herramienta: "crear_tarea", input: { titulo: "Pan" }, leer: { "task-list": LISTAS }, toolUseId: "t3" },
    { nombre: "crear_tarea varias listas sin título", herramienta: "crear_tarea", input: {}, leer: { "task-list": LISTAS } },
    { nombre: "crear_tarea con lista y vence", herramienta: "crear_tarea", input: { titulo: "Dentista", lista_id: 1, vence: "2026-11-27" }, leer: { "task-list": LISTAS }, toolUseId: "t4", resp: { "POST task/create": ok({ id: 8 }, 201) } },
    { nombre: "crear_tarea vence con hora, PATCH falla", herramienta: "crear_tarea", input: { titulo: "Dentista", lista_id: 1, vence: "2026-07-01 09:15" }, leer: { "task-list": LISTAS }, toolUseId: "t4", resp: { "POST task/create": ok({ id: 8 }, 201), "PATCH task/update": fallo(403, "Not Allowed") } },
    { nombre: "crear_tarea lista ajena", herramienta: "crear_tarea", input: { titulo: "Pan", lista_id: 99 }, leer: { "task-list": LISTAS } },
    { nombre: "crear_tarea sin listas editables", herramienta: "crear_tarea", input: { titulo: "Pan" }, leer: { "task-list": [LISTAS[2]] } },
    { nombre: "crear_tarea sin lector", herramienta: "crear_tarea", input: { titulo: "Pan" }, sinLector: true },
    { nombre: "crear_tarea prioridad mala", herramienta: "crear_tarea", input: { titulo: "Pan", lista_id: 1, prioridad: "urgente" }, leer: { "task-list": LISTAS } },
    { nombre: "crear_tarea personas malas", herramienta: "crear_tarea", input: { titulo: "Pan", lista_id: 1, persona_ids: ["x"] }, leer: { "task-list": LISTAS } },
    { nombre: "crear_tarea vence malo", herramienta: "crear_tarea", input: { titulo: "Pan", lista_id: 1, vence: "el viernes" }, leer: { "task-list": LISTAS } },
    { nombre: "editar_tarea prioridad", herramienta: "editar_tarea", input: { id: 5, prioridad: "baja" }, resp: DETALLES },
    { nombre: "editar_tarea todo", herramienta: "editar_tarea", input: { id: 5, titulo: "Llamar ya", persona_ids: [21], prioridad: "alta", vence: "2026-12-02 18:00" }, resp: DETALLES },
    { nombre: "editar_tarea quita vence", herramienta: "editar_tarea", input: { id: 5, vence: "" }, resp: DETALLES },
    { nombre: "editar_tarea sin cambios", herramienta: "editar_tarea", input: { id: 5 }, resp: DETALLES },
    { nombre: "editar_tarea sin id", herramienta: "editar_tarea", input: {}, resp: DETALLES },
    { nombre: "editar_tarea inexistente", herramienta: "editar_tarea", input: { id: 5, titulo: "X" }, resp: { "GET task/detail": fallo(500, "Not Found") } },
    { nombre: "editar_tarea detalle falla", herramienta: "editar_tarea", input: { id: 5, titulo: "X" }, resp: { "GET task/detail": fallo(503, "boom") } },
    { nombre: "completar_tarea", herramienta: "completar_tarea", input: { id: 5 }, resp: DETALLES },
    { nombre: "completar_tarea desmarcar", herramienta: "completar_tarea", input: { id: 5, completada: false }, resp: DETALLES },
    { nombre: "completar_tarea sin id", herramienta: "completar_tarea", input: {}, resp: DETALLES },
    { nombre: "completar_tarea inexistente", herramienta: "completar_tarea", input: { id: 5 }, resp: { "GET task/detail": fallo(404, "Not Found") } },
    { nombre: "completar_tarea varias escrituras", herramienta: "completar_tarea", input: { id: 5 }, resp: DETALLES, escrituras: 2 },
    { nombre: "borrar_tarea", herramienta: "borrar_tarea", input: { id: 5 }, resp: DETALLES },
    { nombre: "borrar_tarea inexistente", herramienta: "borrar_tarea", input: { id: 5 }, resp: { "GET task/detail": fallo(500, "Not Found") } },
    // eventos
    { nombre: "crear_evento calendario único", herramienta: "crear_evento", input: { titulo: "Cena", inicio: "2026-12-01 20:30", persona_ids: [20], alarma_min: 10 }, leer: { calendar: UN_CAL } },
    { nombre: "crear_evento varios días", herramienta: "crear_evento", input: { titulo: "Viaje", inicio: "2026-12-01 09:00", fin: "2026-12-05", calendario_id: 11 }, leer: { calendar: CALENDARIOS } },
    { nombre: "crear_evento varios calendarios", herramienta: "crear_evento", input: { titulo: "Cena", inicio: "2026-12-01 20:30" }, leer: { calendar: CALENDARIOS } },
    { nombre: "crear_evento varios calendarios sin nada", herramienta: "crear_evento", input: {}, leer: { calendar: CALENDARIOS } },
    { nombre: "crear_evento sin hora", herramienta: "crear_evento", input: { titulo: "Cena", inicio: "2026-12-01" }, leer: { calendar: UN_CAL } },
    { nombre: "crear_evento inicio malo", herramienta: "crear_evento", input: { titulo: "Cena", inicio: "mañana" }, leer: { calendar: UN_CAL } },
    { nombre: "crear_evento fin malo", herramienta: "crear_evento", input: { titulo: "Cena", inicio: "2026-12-01 20:30", fin: "x" }, leer: { calendar: UN_CAL } },
    { nombre: "crear_evento calendario inexistente", herramienta: "crear_evento", input: { titulo: "Cena", inicio: "2026-12-01 20:30", calendario_id: 99 }, leer: { calendar: UN_CAL } },
    { nombre: "editar_evento titulo", herramienta: "editar_evento", input: { id: 6, titulo: "Cena fuera" }, resp: DETALLES },
    { nombre: "editar_evento mover día", herramienta: "editar_evento", input: { id: 6, inicio: "2026-12-03" }, resp: DETALLES },
    { nombre: "editar_evento todo", herramienta: "editar_evento", input: { id: 6, inicio: "2026-12-03 19:00", fin: "2026-12-04", persona_ids: [21], alarma_min: 0 }, resp: DETALLES },
    { nombre: "editar_evento sin alarma previa", herramienta: "editar_evento", input: { id: 6, titulo: "X" }, resp: { "GET event/detail": ok({ ...EVENTO, alarm: undefined }) } },
    { nombre: "editar_evento sin cambios", herramienta: "editar_evento", input: { id: 6 }, resp: DETALLES },
    { nombre: "editar_evento inexistente", herramienta: "editar_evento", input: { id: 6, titulo: "X" }, resp: { "GET event/detail": fallo(500, "Not Found") } },
    { nombre: "borrar_evento", herramienta: "borrar_evento", input: { id: 6 }, resp: DETALLES },
    // rutinas
    { nombre: "crear_rutina semanal", herramienta: "crear_rutina", input: { titulo: "Regar", hora: "08:30", frecuencia: "semanal", dias: [3, 1, 3], persona_ids: [20], alarma_min: 5 }, leer: { calendar: UN_CAL } },
    { nombre: "crear_rutina diaria", herramienta: "crear_rutina", input: { titulo: "Pastilla", hora: "21:00", frecuencia: "diaria", intervalo: 2, desde: "2026-12-01", hasta: "2027-01-31" }, leer: { calendar: UN_CAL } },
    { nombre: "crear_rutina mensual", herramienta: "crear_rutina", input: { titulo: "Recibo", hora: "10:00", frecuencia: "mensual", calendario_id: 11 }, leer: { calendar: CALENDARIOS } },
    { nombre: "crear_rutina días sin frecuencia", herramienta: "crear_rutina", input: { titulo: "Regar", hora: "08:30", dias: [2] }, leer: { calendar: UN_CAL } },
    { nombre: "crear_rutina semanal sin días", herramienta: "crear_rutina", input: { titulo: "Regar", hora: "08:30", frecuencia: "semanal" }, leer: { calendar: UN_CAL } },
    { nombre: "crear_rutina varios calendarios", herramienta: "crear_rutina", input: { titulo: "Regar", hora: "08:30", frecuencia: "diaria" }, leer: { calendar: CALENDARIOS } },
    { nombre: "crear_rutina hora mala", herramienta: "crear_rutina", input: { titulo: "Regar", hora: "25:00", frecuencia: "diaria" }, leer: { calendar: UN_CAL } },
    { nombre: "crear_rutina días malos", herramienta: "crear_rutina", input: { titulo: "Regar", hora: "08:30", frecuencia: "semanal", dias: [9] }, leer: { calendar: UN_CAL } },
    { nombre: "crear_rutina fecha mala", herramienta: "crear_rutina", input: { titulo: "Regar", hora: "08:30", frecuencia: "diaria", desde: "x" }, leer: { calendar: UN_CAL } },
    { nombre: "editar_rutina hora", herramienta: "editar_rutina", input: { id: 7, hora: "09:00" }, resp: DETALLES },
    { nombre: "editar_rutina a diaria", herramienta: "editar_rutina", input: { id: 7, frecuencia: "diaria" }, resp: DETALLES },
    { nombre: "editar_rutina a semanal sin días previos", herramienta: "editar_rutina", input: { id: 7, frecuencia: "semanal" }, resp: { "GET routine/detail": ok({ ...RUTINA, frequency: "daily", days: [] }) } },
    { nombre: "editar_rutina hasta vacío y pausa", herramienta: "editar_rutina", input: { id: 7, hasta: "", activa: false, titulo: "Regar plantas", intervalo: 1, desde: "2026-12-01", dias: [5] }, resp: DETALLES },
    { nombre: "editar_rutina sin cambios", herramienta: "editar_rutina", input: { id: 7 }, resp: DETALLES },
    { nombre: "editar_rutina hora mala", herramienta: "editar_rutina", input: { id: 7, hora: "9" }, resp: DETALLES },
    { nombre: "editar_rutina frecuencia mala", herramienta: "editar_rutina", input: { id: 7, frecuencia: "anual" }, resp: DETALLES },
    { nombre: "editar_rutina inexistente", herramienta: "editar_rutina", input: { id: 7, hora: "09:00" }, resp: { "GET routine/detail": fallo(500, "Not Found") } },
    { nombre: "borrar_rutina", herramienta: "borrar_rutina", input: { id: 7 }, resp: DETALLES },
    // calendarios
    { nombre: "crear_calendario solo yo", herramienta: "crear_calendario", input: { nombre: "Fútbol", solo_yo: true }, leer: { person: PERSONAS } },
    { nombre: "crear_calendario compartido", herramienta: "crear_calendario", input: { nombre: "Fútbol", compartir_con: [{ persona_id: 20 }, { persona_id: 22, puede_editar: true }], color: "#123456" }, leer: { person: PERSONAS } },
    { nombre: "crear_calendario compartido editar", herramienta: "crear_calendario", input: { nombre: "Fútbol", compartir_con: [{ persona_id: 20, puede_editar: true }] }, leer: { person: PERSONAS } },
    { nombre: "crear_calendario sin con quién", herramienta: "crear_calendario", input: { nombre: "Fútbol" }, leer: { person: PERSONAS } },
    { nombre: "crear_calendario sin nada", herramienta: "crear_calendario", input: {}, leer: { person: PERSONAS } },
    { nombre: "crear_calendario sin cuenta", herramienta: "crear_calendario", input: { nombre: "Fútbol", compartir_con: [{ persona_id: 21 }] }, leer: { person: PERSONAS } },
    { nombre: "crear_calendario persona inexistente", herramienta: "crear_calendario", input: { nombre: "Fútbol", compartir_con: [{ persona_id: 99 }] }, leer: { person: PERSONAS } },
    { nombre: "crear_calendario color malo", herramienta: "crear_calendario", input: { nombre: "Fútbol", solo_yo: true, color: "x" }, leer: { person: PERSONAS } },
    { nombre: "crear_calendario PATCH 403", herramienta: "crear_calendario", input: { nombre: "Fútbol", compartir_con: [{ persona_id: 20 }] }, leer: { person: PERSONAS }, resp: { "POST calendar/create": ok({ id: 40 }, 201), "PATCH calendar/user": fallo(403, "Not Allowed") } },
    { nombre: "crear_calendario PATCH 500", herramienta: "crear_calendario", input: { nombre: "Fútbol", compartir_con: [{ persona_id: 20 }] }, leer: { person: PERSONAS }, resp: { "POST calendar/create": ok({ id: 40 }, 201), "PATCH calendar/user": fallo(500, "x") } },
    { nombre: "editar_calendario nombre", herramienta: "editar_calendario", input: { id: 10, nombre: "Familia 2" }, leer: { calendar: CALENDARIOS } },
    { nombre: "editar_calendario color", herramienta: "editar_calendario", input: { id: 11, color: "#FFFFFF" }, leer: { calendar: CALENDARIOS } },
    { nombre: "editar_calendario sin cambios", herramienta: "editar_calendario", input: { id: 10 }, leer: { calendar: CALENDARIOS } },
    { nombre: "editar_calendario inexistente", herramienta: "editar_calendario", input: { id: 99, nombre: "X" }, leer: { calendar: CALENDARIOS } },
    { nombre: "borrar_calendario", herramienta: "borrar_calendario", input: { id: 10 }, leer: { calendar: CALENDARIOS } },
    { nombre: "borrar_calendario inexistente", herramienta: "borrar_calendario", input: { id: 99 }, leer: { calendar: CALENDARIOS } },
];

type Obj = Record<string, unknown>;

/** Lo que devuelve una herramienta (valor, cambios y tarjeta sin firma) y las llamadas al escritor. */
export const correr = async (e: Escenario): Promise<Obj> => {
    const w = escritorFalso(e.resp);
    const ctx = ctxDe({
        escribir: w.escribir,
        leer: e.sinLector ? undefined : lectorFalso(e.leer ?? {}),
        secretoConfirmacion: e.sinSecreto ? undefined : SECRETO,
        turno: { escrituras: e.escrituras ?? 1 },
    });
    let salida: unknown;
    try {
        salida = await tool(e.herramienta).run(e.input, ctx, e.toolUseId ? { toolUseId: e.toolUseId } : undefined);
    } catch (err) {
        salida = { lanza: (err as Error).message };
    }
    const sim = salida !== null && typeof salida === "object" ? Object.getOwnPropertySymbols(salida) : [];
    const efectos = sim.length ? (salida as Record<symbol, Obj>)[sim[0]] : undefined;
    const valor = efectos ? (salida as { valor: unknown }).valor : salida;
    const tarjeta = efectos?.tarjeta as Obj | undefined;
    return JSON.parse(JSON.stringify({
        valor,
        cambios: efectos?.cambios,
        tarjeta: tarjeta ? { texto: tarjeta.texto, acciones: tarjeta.acciones, firmada: typeof tarjeta.token === "string" } : undefined,
        llamadas: w.llamadas,
    }));
};

const ARGS_OPS: Record<string, Obj> = {
    crear_lista: { name: "L", color: "#6923E2", client_request_id: "u" },
    editar_lista: { id: 1, name: "L", color: "#6923E2", sort: "title", widget: true, dashboard: false },
    borrar_lista: { id: 1 },
    crear_tarea: { task_list_id: 1, title: "T", priority: "alta", person_ids: [1], due_at: "2026-11-27 22:59:00", client_request_id: "u" },
    editar_tarea: { id: 5, title: "T" },
    completar_tarea: { id: 5, completed: false },
    borrar_tarea: { id: 5 },
    crear_evento: { calendar_id: 10, title: "E", date_at: "2026-12-01 20:30:00" },
    editar_evento: { id: 6, title: "E", date_at: "2026-12-01 20:30:00", alarm: null },
    borrar_evento: { id: 6 },
    crear_rutina: { calendar_id: 10, title: "R", frequency: "daily", interval: 1, days: [], time: "08:00", start_date: "2026-11-25", active: true },
    editar_rutina: { id: 7, title: "R", frequency: "daily", interval: 1, days: [], time: "08:00", start_date: "2026-11-25", end_date: null, active: true },
    borrar_rutina: { id: 7 },
    crear_calendario: { name: "C", color: "#6923E2", compartir: [{ user_id: 502, can_edit: true, nombre: "Lucía" }, { user_id: 503, can_edit: false, nombre: "Pedro" }] },
    editar_calendario: { id: 10, name: "C", color: "#6923E2", widget: true, dashboard: true },
    borrar_calendario: { id: 10 },
};

/** `ejecutarAccion` de cada operación: éxito, error del api y borrado de algo que ya no existe. */
export const correrAcciones = async (): Promise<Obj> => {
    const salida: Obj = {};
    for (const op of Object.keys(OPS)) {
        for (const [caso, resp] of [["ok", undefined], ["403", fallo(403, "Not Allowed")], ["noexiste", fallo(500, "Not Found")], ["400", fallo(400, "Bad")]] as const) {
            const w = escritorFalso(resp ? { [`${OPS[op].metodo} ${OPS[op].ruta}`]: resp } : { "POST calendar/create": ok({ id: 40 }, 201) });
            const r = await ejecutarAccion(w.escribir, { op, args: ARGS_OPS[op], nombre: "Algo" });
            salida[`${op} ${caso}`] = JSON.parse(JSON.stringify({ r, llamadas: w.llamadas }));
        }
    }
    const w = escritorFalso({ "POST task/create": ok({ id: 8 }, 201), "PATCH task/update": fallo(400, "due_at inválido") });
    salida["crear_tarea PATCH falla"] = JSON.parse(JSON.stringify({ r: await ejecutarAccion(w.escribir, { op: "crear_tarea", args: ARGS_OPS.crear_tarea, nombre: "Casa" }), llamadas: w.llamadas }));
    const w2 = escritorFalso({ "POST calendar/create": ok({ id: 40 }, 201), "PATCH calendar/user": fallo(403, "x") });
    salida["crear_calendario PATCH 403"] = JSON.parse(JSON.stringify({ r: await ejecutarAccion(w2.escribir, { op: "crear_calendario", args: ARGS_OPS.crear_calendario, nombre: "C" }), llamadas: w2.llamadas }));
    salida["op desconocida"] = JSON.parse(JSON.stringify(await ejecutarAccion(escritorFalso().escribir, { op: "x", args: {} })));
    return salida;
};

export const correrErrores = (): Obj => {
    const casos: Array<[number, unknown, string?]> = [
        [403, "Not Allowed", "Compra"], [403, "Not Allowed"], [404, "Not Found"], [500, "Not Found"], [500, "otro"], [400, "Name is required"],
        [400, ""], [400, undefined], [400, "x".repeat(300)], [409, "x"], [503, undefined], [401, "x"],
    ];
    const salida: Obj = {};
    casos.forEach(([s, e, n], i) => {
        salida[`${i}:${s}`] = { traducir: traducir(s, e, n), esNoExiste: esNoExiste(s, e) };
    });
    return salida;
};
