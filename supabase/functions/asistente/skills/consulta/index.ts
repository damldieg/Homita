// Skill `consulta` (fase 1, solo lectura): responde sobre eventos, rutinas, listas, tareas y personas
// del hogar activo. Las herramientas llaman en proceso a los casos de uso de `api` con el JWT del
// usuario: heredan RLS, ACL y el filtro del hogar (X-Home-Id) sin duplicar lógica.
import { handlePersonIndex } from "../../../api/usecases/persons.ts";
import { handleTask } from "../../../api/usecases/tasks.ts";
import { handleTaskListIndex } from "../../../api/usecases/task-lists.ts";
import { handleEvent } from "../../../api/usecases/events.ts";
import { handleRoutineIndex } from "../../../api/usecases/routines.ts";
import type { Skill, Tool, ToolCtx } from "../../core.ts";

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/** Día siguiente a YYYY-MM-DD, en el mismo formato (aritmética en UTC, sin zona). */
export const diaSiguiente = (ymd: string): string => {
    const [y, m, d] = ymd.split("-").map(Number);
    return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
};

/** Medianoche local de la zona `tz` para una fecha YYYY-MM-DD, en segundos Unix (formato de get_events). */
export const localMidnightUnix = (ymd: string, tz: string): number => {
    const [y, m, d] = ymd.split("-").map(Number);
    const guess = Date.UTC(y, m - 1, d);
    const offsetMs = (ts: number): number => {
        const parts = new Intl.DateTimeFormat("en-US", {
            timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
            hour: "2-digit", minute: "2-digit", second: "2-digit",
        }).formatToParts(new Date(ts));
        const g = (t: string) => Number(parts.find((p) => p.type === t)!.value);
        return Date.UTC(g("year"), g("month") - 1, g("day"), g("hour"), g("minute"), g("second")) - ts;
    };
    const primera = guess - offsetMs(guess);
    return Math.floor((guess - offsetMs(primera)) / 1000);
};

/** Ejecuta un caso de uso GET de `api` y devuelve su JSON; un error HTTP se devuelve como objeto de error. */
const leer = async (res: Response): Promise<unknown> => {
    const texto = await res.text();
    if (!res.ok) return { error: res.status, detalle: texto.slice(0, 200) };
    try {
        return JSON.parse(texto);
    } catch {
        return { error: "respuesta no válida" };
    }
};

const peticion = (ruta: string, params: Record<string, string | undefined>, tz: string): Request => {
    const url = new URL(`https://asistente.local/api/${ruta}`);
    for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") url.searchParams.set(k, v);
    url.searchParams.set("timezone", tz);
    return new Request(url.toString(), { method: "GET" });
};

const str = (input: Record<string, unknown>, key: string): string | undefined => {
    const v = input[key];
    return typeof v === "string" && v.trim() !== "" ? v.trim() : undefined;
};

const fechaValida = (v: string | undefined): string | undefined => {
    if (v === undefined) return undefined;
    if (!ISO_DATE.test(v)) throw new Error("La fecha debe tener formato AAAA-MM-DD");
    return v;
};

const verEventos: Tool = {
    name: "ver_eventos",
    description: "Lista los eventos del hogar activo. Filtra por rango de fechas (desde, hasta) y/o texto (buscar). Sin filtros, devuelve los próximos.",
    input_schema: {
        type: "object",
        properties: {
            desde: { type: "string", description: "Primer día del rango, AAAA-MM-DD (incluido)." },
            hasta: { type: "string", description: "Último día del rango, AAAA-MM-DD (incluido)." },
            buscar: { type: "string", description: "Texto a buscar en el título." },
        },
    },
    run: async (input, ctx: ToolCtx) => {
        const desde = fechaValida(str(input, "desde"));
        const hasta = fechaValida(str(input, "hasta"));
        // get_events filtra por end de día: hasta incluido = medianoche del día siguiente.
        const siguiente = hasta ? diaSiguiente(hasta) : undefined;
        const params: Record<string, string | undefined> = {
            start_date: desde ? String(localMidnightUnix(desde, ctx.timezone)) : undefined,
            end_date: siguiente ? String(localMidnightUnix(siguiente, ctx.timezone)) : undefined,
            search: str(input, "buscar"),
            order_mode: "asc",
        };
        return await leer(await handleEvent(peticion("event", params, ctx.timezone), ctx.token, ctx.uid));
    },
};

const verRutinas: Tool = {
    name: "ver_rutinas",
    description: "Lista las rutinas del hogar activo (con su calendario, hora y días).",
    input_schema: { type: "object", properties: {} },
    run: async (_input, ctx) =>
        await leer(await handleRoutineIndex(peticion("routine", {}, ctx.timezone), ctx.token, ctx.uid)),
};

const verListas: Tool = {
    name: "ver_listas",
    description: "Lista las listas de tareas del hogar activo.",
    input_schema: { type: "object", properties: {} },
    run: async (_input, ctx) => await leer(await handleTaskListIndex(peticion("task-list", {}, ctx.timezone), ctx.token)),
};

const verTareas: Tool = {
    name: "ver_tareas",
    description: "Lista las tareas del hogar activo. Si se indica lista_id, solo las de esa lista.",
    input_schema: {
        type: "object",
        properties: { lista_id: { type: "integer", description: "Id de la lista (opcional)." } },
    },
    run: async (input, ctx) => {
        const lista = typeof input.lista_id === "number" && Number.isInteger(input.lista_id) ? String(input.lista_id) : undefined;
        return await leer(await handleTask(peticion("task", { task_list_id: lista }, ctx.timezone), ctx.token));
    },
};

const verPersonas: Tool = {
    name: "ver_personas",
    description: "Lista las personas del hogar activo (nombres y vínculos con cuentas).",
    input_schema: { type: "object", properties: {} },
    run: async (_input, ctx) => await leer(await handlePersonIndex(peticion("person", {}, ctx.timezone), ctx.token)),
};

const fechaActual: Tool = {
    name: "fecha_actual",
    description: "Devuelve la fecha, la hora y la zona horaria del usuario ahora mismo. Úsala para «hoy», «mañana» o «esta semana».",
    input_schema: { type: "object", properties: {} },
    run: async (_input, ctx) => {
        const f = new Intl.DateTimeFormat("es-ES", {
            timeZone: ctx.timezone, weekday: "long", year: "numeric", month: "long", day: "numeric",
            hour: "2-digit", minute: "2-digit", hourCycle: "h23",
        });
        return { fecha_y_hora: f.format(ctx.now), zona: ctx.timezone };
    },
};

export const consulta: Skill = {
    id: "consulta",
    nombre: "Consulta",
    descripcion: "Responde preguntas sobre eventos, rutinas, tareas, listas y personas del hogar (solo lectura).",
    instrucciones: `Skill «consulta»: responde preguntas sobre eventos, rutinas, tareas, listas y personas del hogar activo usando solo las herramientas ver_eventos, ver_rutinas, ver_listas, ver_tareas, ver_personas y fecha_actual. Para «hoy», «mañana» o «esta semana», consulta primero fecha_actual. Esta fase es solo de lectura: si el usuario pide crear, cambiar o borrar algo, dile que todavía no puedes hacerlo.`,
    herramientas: [verEventos, verRutinas, verListas, verTareas, verPersonas, fechaActual],
    tarjetas: [],
    disponible: () => true,
};
