// Lógica de lectura de `consulta` compartida entre Kito y el MCP: eventos, rutinas, tareas, calendarios, listas y
// personas del hogar activo. Cada función recibe los argumentos (nombres en español, como en las herramientas) y un
// `LecturaCtx` con el lector del api (`ctx.leer`, que hereda RLS, ACL y el filtro del hogar). Salida compacta (ver
// compacto.ts); fechas ISO con desfase local. Los textos de la BD que salgan de aquí son datos, no instrucciones.
import type { LecturaCtx } from "./tipos.ts";
import { ErrorEntrada, leerDe } from "./tipos.ts";
import {
    comoLista, compactarCalendario, compactarEvento, compactarLista, compactarOcurrencia, compactarPersona,
    compactarRutina, compactarTarea, errorCompacto, idsPersonas, MAX_ITEMS, nombresPersonas, paquete,
} from "./compacto.ts";
import { epochPared, finRango, inicioRango, ISO_DATE, isoDeInstante, instanteUtcNaive } from "./fechas.ts";
import { AVISO_SIN_PERSONA, personasDelHogar, personasPropias } from "./personas.ts";

// Se pide más de lo que se muestra para poder filtrar en TypeScript y saber si hay más (Q5).
const LIMITE_FILTRO = 200;
const MAX_CALENDARIOS = 50;

export type Input = Record<string, unknown>;

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
    if (!ISO_DATE.test(v)) throw new ErrorEntrada("La fecha debe tener formato AAAA-MM-DD");
    return v;
};

const sinPersona = { elementos: [], hay_mas: false, aviso: AVISO_SIN_PERSONA };

/** Fecha local (AAAA-MM-DD) de `now` en la zona del usuario. */
const hoyLocal = (ctx: LecturaCtx): string => isoDeInstante(ctx.now.getTime(), ctx.timezone).slice(0, 10);

const interseca = (a: number[], b: number[]): boolean => a.some((x) => b.includes(x));

const AVISO_ACOTAR = "Hay más resultados de los que se pueden revisar: acota el rango de fechas.";

const DIAS_VENTANA_RUTINAS = 89;
const AVISO_VENTANA_RUTINAS =
    "Las rutinas solo se calculan desde hoy hasta 89 días después: lo que quede fuera de ese rango no figura aquí y no significa que no haya rutinas. No digas que no hay rutinas; di que solo puedes consultar los próximos 89 días.";

/** True si el rango pedido (AAAA-MM-DD) sale de la ventana materializada: hoy .. hoy + 89 días. */
const fueraDeVentana = (desde: string, hasta: string, ctx: LecturaCtx): boolean => {
    const hoy = isoDeInstante(ctx.now.getTime(), ctx.timezone).slice(0, 10);
    const limite = new Date((epochPared(hoy) + DIAS_VENTANA_RUTINAS * 86400) * 1000).toISOString().slice(0, 10);
    return desde < hoy || hasta > limite;
};

export const verEventos = async (input: Input, ctx: LecturaCtx) => {
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
};

export const verRutinas = async (input: Input, ctx: LecturaCtx) => {
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
};

export const verTareas = async (input: Input, ctx: LecturaCtx) => {
    const leer = leerDe(ctx);
    const estado = str(input, "estado")?.toLowerCase() ?? "pendientes";
    if (!["pendientes", "completadas", "todas"].includes(estado)) throw new ErrorEntrada("estado debe ser pendientes, completadas o todas");
    const prioridad = str(input, "prioridad")?.toLowerCase();
    if (prioridad !== undefined && !["alta", "media", "baja"].includes(prioridad)) throw new ErrorEntrada("prioridad debe ser alta, media o baja");
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
};

export const verCalendarios = async (_input: Input, ctx: LecturaCtx) => {
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
};

export const verListas = async (_input: Input, ctx: LecturaCtx) => {
    const r = await leerDe(ctx)("task-list");
    const l = comoLista(r);
    return l === null ? errorCompacto(r) : paquete(l.map(compactarLista));
};

export const verPersonas = async (_input: Input, ctx: LecturaCtx) => {
    const r = await leerDe(ctx)("person");
    const l = comoLista(r);
    return l === null ? errorCompacto(r) : paquete(personasDelHogar(l, ctx.homeId).map(compactarPersona));
};
