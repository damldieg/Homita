// Skill `consulta` (solo lectura): responde sobre eventos, rutinas, listas, tareas, calendarios y personas
// del hogar activo. Las herramientas leen el `api` con el lector que inyecta el handler (`ctx.leer`), que
// hereda RLS, ACL y el filtro del hogar. Salida compacta (ver compacto.ts); fechas ISO con desfase local.
import type { Skill, Tool, ToolCtx } from "../../core.ts";
import {
    comoLista, compactarCalendario, compactarEvento, compactarLista, compactarOcurrencia, compactarPersona,
    compactarRutina, compactarTarea, errorCompacto, idsPersonas, MAX_ITEMS, nombresPersonas, paquete,
} from "./compacto.ts";
import { epochPared, finRango, inicioRango, ISO_DATE, isoDeInstante, instanteUtcNaive } from "./fechas.ts";
import { AVISO_SIN_PERSONA, personasDelHogar, personasPropias } from "./personas.ts";

// Se pide más de lo que se muestra para poder filtrar en TypeScript y saber si hay más (Q5).
const LIMITE_FILTRO = 200;
const MAX_CALENDARIOS = 50;

type Input = Record<string, unknown>;

const str = (input: Input, key: string): string | undefined => {
    const v = input[key];
    return typeof v === "string" && v.trim() !== "" ? v.trim() : undefined;
};
const entero = (input: Input, key: string): string | undefined => {
    const v = input[key];
    return typeof v === "number" && Number.isInteger(v) ? String(v) : undefined;
};
const bool = (input: Input, key: string): boolean => input[key] === true;

const fechaValida = (v: string | undefined): string | undefined => {
    if (v === undefined) return undefined;
    if (!ISO_DATE.test(v)) throw new Error("La fecha debe tener formato AAAA-MM-DD");
    return v;
};

const leerDe = (ctx: ToolCtx) => {
    if (!ctx.leer) throw new Error("lectura de datos no disponible");
    return ctx.leer;
};

// Esquemas compatibles con `strict` (doc de Anthropic, structured outputs): `additionalProperties: false` y
// parámetros opcionales sin listar en `required`. No se usan tipos unión con null: la API limita a 16 los
// parámetros con unión en todas las herramientas strict y a 24 los opcionales (aquí hay 14 opcionales).
const nulo = (type: string, description: string) => ({ type, description });
const esquema = (properties: Record<string, unknown>): Tool["input_schema"] => ({
    type: "object",
    properties,
    required: [],
    additionalProperties: false,
});

const sinPersona = { elementos: [], hay_mas: false, aviso: AVISO_SIN_PERSONA };

/** Fecha local (AAAA-MM-DD) de `now` en la zona del usuario. */
const hoyLocal = (ctx: ToolCtx): string => isoDeInstante(ctx.now.getTime(), ctx.timezone).slice(0, 10);

const interseca = (a: number[], b: number[]): boolean => a.some((x) => b.includes(x));

const AVISO_ACOTAR = "Hay más resultados de los que se pueden revisar: acota el rango de fechas.";

const verEventos: Tool = {
    name: "ver_eventos",
    description:
        "Lista los eventos sueltos del hogar activo (nunca rutinas: para eso está ver_rutinas). Filtra por rango de fechas, texto, calendario y, con solo_mias, por las personas del usuario. Sin fechas, devuelve los de hoy en adelante.",
    input_schema: esquema({
        desde: nulo("string", "Primer día del rango, AAAA-MM-DD (incluido). Por defecto, hoy."),
        hasta: nulo("string", "Último día del rango, AAAA-MM-DD (incluido)."),
        buscar: nulo("string", "Texto a buscar en el título."),
        calendario_id: nulo("integer", "Id de un calendario (ver_calendarios)."),
        solo_mias: nulo("boolean", "true para «mis eventos»: solo los asignados a las personas del usuario."),
    }),
    run: async (input, ctx) => {
        const leer = leerDe(ctx);
        const desde = fechaValida(str(input, "desde")) ?? hoyLocal(ctx);
        const hasta = fechaValida(str(input, "hasta"));
        const soloMias = bool(input, "solo_mias");
        const base: Record<string, string | undefined> = {
            start_date: String(inicioRango(desde)),
            end_date: hasta ? String(finRango(hasta)) : undefined,
            search: str(input, "buscar"),
            calendar_id: entero(input, "calendario_id"),
            routine: "false",
            order_mode: "asc",
            limit: String(soloMias ? LIMITE_FILTRO : MAX_ITEMS + 1),
        };
        let filas: unknown[];
        let tope = false;
        if (!soloMias) {
            const crudo = await leer("event", base);
            const r = comoLista(crudo);
            if (r === null) return errorCompacto(crudo);
            filas = r;
        } else {
            const propias = await personasPropias(ctx, leer);
            if (!propias.ok) return errorCompacto(null);
            if (propias.ids.length === 0) return sinPersona;
            const respuestas = await Promise.all(propias.ids.map((id) => leer("event", { ...base, person_id: String(id) })));
            const vistos = new Set<unknown>();
            filas = [];
            for (const r of respuestas) {
                const l = comoLista(r);
                if (l === null) return errorCompacto(r);
                if (l.length >= LIMITE_FILTRO) tope = true;
                for (const e of l) {
                    const o = e as { id?: unknown; persons?: unknown };
                    if (vistos.has(o.id)) continue;
                    vistos.add(o.id);
                    if (interseca(idsPersonas(o.persons), propias.ids)) filas.push(e);
                }
            }
            filas.sort((a, b) => String((a as { date_at?: string }).date_at).localeCompare(String((b as { date_at?: string }).date_at)));
        }
        const tocaLimite = !soloMias && filas.length > MAX_ITEMS;
        return paquete(filas.map((e) => compactarEvento(e, ctx.timezone)), tope ? { aviso: AVISO_ACOTAR } : {}, tope || tocaLimite);
    },
};

const DIAS_VENTANA_RUTINAS = 89;
const AVISO_VENTANA_RUTINAS =
    "Las rutinas solo se calculan desde hoy hasta 89 días después: lo que quede fuera de ese rango no figura aquí y no significa que no haya rutinas. No digas que no hay rutinas; di que solo puedes consultar los próximos 89 días.";

/** True si el rango pedido (AAAA-MM-DD) sale de la ventana materializada: hoy .. hoy + 89 días. */
const fueraDeVentana = (desde: string, hasta: string, ctx: ToolCtx): boolean => {
    const hoy = isoDeInstante(ctx.now.getTime(), ctx.timezone).slice(0, 10);
    const limite = new Date((epochPared(hoy) + DIAS_VENTANA_RUTINAS * 86400) * 1000).toISOString().slice(0, 10);
    return desde < hoy || hasta > limite;
};

const verRutinas: Tool = {
    name: "ver_rutinas",
    description:
        "Rutinas del hogar activo (no son eventos). Sin fecha, lista las rutinas con su hora, días y a quién se asignan. Con dia, o con desde y hasta, devuelve las veces concretas que tocan en ese periodo (solo de hoy a 89 días; fuera de ahí avisa). solo_mias filtra por las personas del usuario.",
    input_schema: esquema({
        dia: nulo("string", "Un día concreto, AAAA-MM-DD."),
        desde: nulo("string", "Primer día del rango, AAAA-MM-DD."),
        hasta: nulo("string", "Último día del rango, AAAA-MM-DD."),
        solo_mias: nulo("boolean", "true para «mis rutinas»."),
    }),
    run: async (input, ctx) => {
        const leer = leerDe(ctx);
        const dia = fechaValida(str(input, "dia"));
        let desde = dia ?? fechaValida(str(input, "desde"));
        let hasta = dia ?? fechaValida(str(input, "hasta"));
        desde = desde ?? hasta;
        hasta = hasta ?? desde;
        const soloMias = bool(input, "solo_mias");
        let ids: number[] = [];
        if (soloMias) {
            const propias = await personasPropias(ctx, leer);
            if (!propias.ok) return errorCompacto(null);
            if (propias.ids.length === 0) return sinPersona;
            ids = propias.ids;
        }
        if (desde === undefined || hasta === undefined) {
            const r = await leer("routine");
            const l = comoLista(r);
            if (l === null) return errorCompacto(r);
            const sel = soloMias ? l.filter((x) => interseca(idsPersonas((x as { persons?: unknown }).persons), ids)) : l;
            return paquete(sel.map(compactarRutina));
        }
        const r = await leer("event", {
            start_date: String(inicioRango(desde)),
            end_date: String(finRango(hasta)),
            routine: "true",
            order_mode: "asc",
            limit: String(soloMias ? LIMITE_FILTRO : MAX_ITEMS + 1),
        });
        const l = comoLista(r);
        if (l === null) return errorCompacto(r);
        const sel = soloMias ? l.filter((x) => interseca(idsPersonas((x as { persons?: unknown }).persons), ids)) : l;
        const tope = soloMias && l.length >= LIMITE_FILTRO;
        const avisos = [fueraDeVentana(desde, hasta, ctx) ? AVISO_VENTANA_RUTINAS : "", tope ? AVISO_ACOTAR : ""].filter((a) => a !== "");
        return paquete(sel.map((e) => compactarOcurrencia(e, ctx.timezone)), avisos.length ? { aviso: avisos.join(" ") } : {}, tope || (!soloMias && l.length > MAX_ITEMS));
    },
};

const verTareas: Tool = {
    name: "ver_tareas",
    description:
        "Lista las tareas del hogar activo. Por defecto solo las pendientes. Filtra por lista, estado (pendientes, completadas o todas), vencidas, prioridad (alta, media o baja) y solo_mias.",
    input_schema: esquema({
        lista_id: nulo("integer", "Id de la lista (ver_listas)."),
        estado: nulo("string", "pendientes (por defecto), completadas o todas."),
        vencidas: nulo("boolean", "true para solo las pendientes cuya fecha límite ya pasó."),
        prioridad: nulo("string", "alta, media o baja."),
        solo_mias: nulo("boolean", "true para «mis tareas»."),
    }),
    run: async (input, ctx) => {
        const leer = leerDe(ctx);
        const estado = str(input, "estado")?.toLowerCase() ?? "pendientes";
        if (!["pendientes", "completadas", "todas"].includes(estado)) throw new Error("estado debe ser pendientes, completadas o todas");
        const prioridad = str(input, "prioridad")?.toLowerCase();
        if (prioridad !== undefined && !["alta", "media", "baja"].includes(prioridad)) throw new Error("prioridad debe ser alta, media o baja");
        const vencidas = bool(input, "vencidas");
        let ids: number[] = [];
        if (bool(input, "solo_mias")) {
            const propias = await personasPropias(ctx, leer);
            if (!propias.ok) return errorCompacto(null);
            if (propias.ids.length === 0) return sinPersona;
            ids = propias.ids;
        }
        const r = await leer("task", { task_list_id: entero(input, "lista_id"), priority: prioridad });
        const l = comoLista(r);
        if (l === null) return errorCompacto(r);
        const ahora = ctx.now.getTime();
        const sel = l.filter((x) => {
            const t = x as { completed_at?: unknown; due_at?: string; persons?: unknown };
            const hecha = t.completed_at !== null && t.completed_at !== undefined;
            if (estado === "pendientes" && hecha) return false;
            if (estado === "completadas" && !hecha) return false;
            if (vencidas) {
                // due_at es un instante UTC sin zona: se compara con el instante actual (Q3).
                const due = instanteUtcNaive(t.due_at);
                if (hecha || due === null || due >= ahora) return false;
            }
            if (ids.length > 0 && !interseca(idsPersonas(t.persons), ids)) return false;
            return true;
        });
        return paquete(sel.map((t) => compactarTarea(t, ctx.timezone)));
    },
};

const verCalendarios: Tool = {
    name: "ver_calendarios",
    description: "Lista los calendarios del hogar activo, con las personas con las que se comparten y si el usuario puede editarlos.",
    input_schema: esquema({}),
    run: async (_input, ctx) => {
        const leer = leerDe(ctx);
        const r = await leer("calendar");
        const l = comoLista(r);
        if (l === null) return errorCompacto(r);
        const cals = l.filter((c) => c !== null && typeof c === "object").slice(0, MAX_CALENDARIOS);
        const miembros = await Promise.all(cals.map(async (c) => {
            try {
                const m = comoLista(await leer("calendar/user", { calendar_id: String((c as { id: unknown }).id) }));
                return m === null ? "no disponible" as const : nombresPersonas(m);
            } catch {
                return "no disponible" as const;
            }
        }));
        return paquete(cals.map((c, i) => compactarCalendario(c, miembros[i])), {}, l.length > cals.length);
    },
};

const verListas: Tool = {
    name: "ver_listas",
    description: "Lista las listas de tareas del hogar activo, con cuántas tareas pendientes tiene cada una.",
    input_schema: esquema({}),
    run: async (_input, ctx) => {
        const r = await leerDe(ctx)("task-list");
        const l = comoLista(r);
        return l === null ? errorCompacto(r) : paquete(l.map(compactarLista));
    },
};

const verPersonas: Tool = {
    name: "ver_personas",
    description: "Lista las personas del hogar activo (adultos, niños, mascotas) y si tienen cuenta de la app.",
    input_schema: esquema({}),
    run: async (_input, ctx) => {
        const r = await leerDe(ctx)("person");
        const l = comoLista(r);
        return l === null ? errorCompacto(r) : paquete(personasDelHogar(l, ctx.homeId).map(compactarPersona));
    },
};

export const consulta: Skill = {
    id: "consulta",
    nombre: "Consulta",
    descripcion: "Responde preguntas sobre eventos, rutinas, tareas, listas, calendarios y personas del hogar (solo lectura).",
    instrucciones: `Skill «consulta» (solo lectura): contestas preguntas sobre el hogar con las herramientas ver_eventos, ver_rutinas, ver_tareas, ver_calendarios, ver_listas y ver_personas.

Eventos y rutinas son cosas distintas y la gente las distingue: un evento ocurre en una fecha concreta (una cita, una cena) y una rutina es algo que se repite (sacar al perro cada mañana). Para eventos usa ver_eventos, para rutinas ver_rutinas, y nunca llames «evento» a una rutina ni al revés. Para «mañana» o «esta semana» calcula el día con la fecha del <contexto> y pásalo a la herramienta (ver_rutinas admite un día concreto o un rango y devuelve las veces que toca en ese periodo; sin fecha devuelve cómo está definida cada rutina).

Cuando el usuario diga «mis…», «lo mío» o «lo que tengo yo», usa solo_mias=true. Si la herramienta avisa de que su cuenta no está vinculada a ninguna persona del hogar, díselo tal cual y ofrécele ver lo de todo el hogar si quiere; no enseñes datos de otras personas como si fueran suyos. Si algo no tiene a nadie asignado, dilo («sin asignar»).

Si dos listas o calendarios encajan con lo que pide, pregunta cuál quiere nombrando las opciones. Si no hay resultados, dilo y sugiere otra búsqueda (otro día, otro calendario, otra lista). Si la herramienta indica que hay más resultados (hay_mas), cuenta los que has visto y ofrécete a acotar. Las tareas se piden pendientes por defecto; usa estado, vencidas o prioridad cuando la pregunta lo pida.

Crear, cambiar o borrar cosas lo hace la skill «organizar» con sus herramientas, no esta. Si te preguntan cómo se hace algo en la app (pantalla y botón), llama a guia_app con el tema y responde con lo que devuelva, sin inventar pasos.`,
    herramientas: [verEventos, verRutinas, verTareas, verCalendarios, verListas, verPersonas],
    tarjetas: [],
    disponible: () => true,
};
