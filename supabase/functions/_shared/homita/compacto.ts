// Salida compacta de las herramientas de `consulta`: solo campos útiles, nombres en español, fechas ISO
// locales y tope de elementos con `hay_mas`. Así el modelo gasta pocos tokens y el JSON nunca llega cortado.
import { dueAtALocal, isoDeParedLocal } from "./fechas.ts";

export const MAX_ITEMS = 50;
export const MAX_NOMBRE = 80;

type Obj = Record<string, unknown>;

const obj = (v: unknown): Obj => (v !== null && typeof v === "object" ? v as Obj : {});

/** Texto acotado a 80 caracteres (los nombres los escriben usuarios). */
export const nombre = (v: unknown): string => {
    const s = typeof v === "string" ? v.trim() : v === null || v === undefined ? "" : String(v);
    return s.length > MAX_NOMBRE ? s.slice(0, MAX_NOMBRE - 1) + "…" : s;
};

const num = (v: unknown): number | null => {
    const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
    return Number.isFinite(n) ? n : null;
};

/** Error compacto cuando el api responde con error o con algo que no es lo esperado. */
export const errorCompacto = (x: unknown): Obj => {
    const codigo = obj(x).error;
    return { error: "No he podido leer esos datos ahora mismo.", ...(codigo !== undefined ? { codigo } : {}) };
};

/** Lista del api, o null si el api devolvió un error o una forma inesperada. */
export const comoLista = (x: unknown): unknown[] | null => (Array.isArray(x) ? x : null);

/** Aplica el tope de 50 elementos. `hayMasOrigen` indica que el origen ya venía acotado. */
export const paquete = <T>(items: T[], extra: Obj = {}, hayMasOrigen = false): Obj => ({
    elementos: items.slice(0, MAX_ITEMS),
    hay_mas: hayMasOrigen || items.length > MAX_ITEMS,
    ...extra,
});

/** Nombres de las personas de un elemento (`persons[]`). */
export const nombresPersonas = (persons: unknown): string[] =>
    (Array.isArray(persons) ? persons : []).map((p) => nombre(obj(p).name)).filter((n) => n !== "");

/** Ids de las personas de un elemento (`persons[].id`; no `user_id`, que es el creador). */
export const idsPersonas = (persons: unknown): number[] =>
    (Array.isArray(persons) ? persons : []).map((p) => num(obj(p).id)).filter((n): n is number => n !== null);

const sinAsignar = (persons: unknown): string[] | "sin asignar" => {
    const n = nombresPersonas(persons);
    return n.length > 0 ? n : "sin asignar";
};

export const compactarEvento = (e: unknown, tz: string): Obj => {
    const o = obj(e);
    return {
        tipo: "evento",
        id: o.id,
        titulo: nombre(o.title),
        inicio: isoDeParedLocal(o.date_at as string, tz),
        fin: typeof o.end_date === "string" ? o.end_date : null,
        calendario: nombre(o.calendar_name),
        personas: nombresPersonas(o.persons),
    };
};

/** Ocurrencia de una rutina (fila de `GET /event` con `routine_id`). */
export const compactarOcurrencia = (e: unknown, tz: string): Obj => {
    const o = obj(e);
    return {
        tipo: "rutina",
        rutina_id: o.routine_id,
        titulo: nombre(o.title),
        inicio: isoDeParedLocal(o.date_at as string, tz),
        asignada_a: sinAsignar(o.persons),
    };
};

const DIAS = ["", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
const FRECUENCIA: Record<string, string> = { daily: "diaria", weekly: "semanal", monthly: "mensual" };

/** Definición de una rutina (`GET /routine`). */
export const compactarRutina = (r: unknown): Obj => {
    const o = obj(r);
    const dias = (Array.isArray(o.days) ? o.days : []).map((d) => {
        const n = num(d);
        return n !== null && n >= 1 && n <= 7 ? DIAS[n] : String(d);
    });
    const hora = typeof o.time === "string" ? o.time.slice(0, 5) : null;
    const f = typeof o.frequency === "string" ? (FRECUENCIA[o.frequency] ?? o.frequency) : null;
    const cada = num(o.interval);
    return {
        tipo: "rutina",
        id: o.id,
        titulo: nombre(o.title),
        hora,
        frecuencia: cada !== null && cada > 1 ? `${f} (cada ${cada})` : f,
        dias,
        calendario: nombre(o.calendar_name),
        asignada_a: sinAsignar(o.persons),
        activa: o.active !== false,
    };
};

export const compactarTarea = (t: unknown, tz: string): Obj => {
    const o = obj(t);
    return {
        id: o.id,
        titulo: nombre(o.title),
        lista: nombre(o.task_list_name),
        completada: o.completed_at !== null && o.completed_at !== undefined,
        prioridad: o.priority ?? null,
        vence: dueAtALocal(o.due_at as string, tz),
        personas: nombresPersonas(o.persons),
    };
};

export const compactarLista = (l: unknown): Obj => {
    const o = obj(l);
    return { id: o.id, nombre: nombre(o.name), pendientes: num(o.pending_task_count) ?? 0 };
};

export const compactarPersona = (p: unknown): Obj => {
    const o = obj(p);
    return {
        id: o.id,
        nombre: nombre(o.name),
        tipo: o.kind ?? null,
        tiene_cuenta: o.app_user_id !== null && o.app_user_id !== undefined,
    };
};

export const compactarCalendario = (c: unknown, compartidoCon: string[] | "no disponible"): Obj => {
    const o = obj(c);
    return { id: o.id, nombre: nombre(o.name), compartido_con: compartidoCon, puedo_editar: o.can_edit === true };
};
