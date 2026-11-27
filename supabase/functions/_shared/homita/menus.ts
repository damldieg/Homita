// Lectura de menús compartida entre Kito y el MCP: lectura de argumentos, fechas de semana (aritmética en UTC, sin
// zona), reglas de franjas y rangos, y lectores del perfil y del plan sobre un `Leer` (sin ToolCtx). Es la parte de
// lectura de lo que antes era `asistente/skills/menus/util.ts`; la de escritura se queda en Kito. Sin dependencias
// de `api` ni de `asistente`.
import type { Leer } from "./tipos.ts";

export type Obj = Record<string, unknown>;
export type Input = Record<string, unknown>;

export const FRANJAS = ["breakfast", "midmorning", "lunch", "snack", "dinner"] as const;
export const FRANJA_ES: Record<string, string> = {
    breakfast: "desayuno", midmorning: "media mañana", lunch: "comida", snack: "merienda", dinner: "cena",
};
const DIAS = ["", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
export const diaNombre = (isoDow: number): string => DIAS[isoDow] ?? "";

export const obj = (v: unknown): Obj => (v !== null && typeof v === "object" && !Array.isArray(v) ? v as Obj : {});
export const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);

/** Texto recortado y acotado; `undefined` si no es texto o queda vacío. */
export const str = (v: unknown, max = 200): string | undefined => {
    if (typeof v !== "string") return undefined;
    const t = v.trim();
    return t === "" ? undefined : t.slice(0, max);
};
export const entero = (v: unknown): number | undefined =>
    typeof v === "number" && Number.isInteger(v) && v > 0 && v <= Number.MAX_SAFE_INTEGER ? v : undefined;

/** Sin acentos ni mayúsculas, para comparar nombres. */
export const norm = (t: string): string => t.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().trim();

export const esFecha = (v: unknown): v is string => {
    if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return false;
    const d = new Date(`${v}T00:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
};
export const sumarDias = (ymd: string, n: number): string => {
    const d = new Date(`${ymd}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
};
/** Día de la semana ISO: 1 = lunes … 7 = domingo. */
export const isoDow = (ymd: string): number => new Date(`${ymd}T00:00:00Z`).getUTCDay() || 7;
/** Primer día de la semana (según `week_start_day`, 1 = lunes) que contiene `ymd`. */
export const inicioSemana = (ymd: string, weekStartDay: number): string =>
    sumarDias(ymd, -((isoDow(ymd) - weekStartDay + 7) % 7));

/** Un extremo del rango: fecha local (AAAA-MM-DD) y franja (breakfast … dinner). */
export interface PuntoRango {
    fecha: string;
    franja: string;
}
export interface CasillaRango {
    fecha: string;
    franja: string;
}
export interface SemanaRango {
    /** Primer día de la semana (según `week_start_day`). */
    semana: string;
    /** Casillas del rango en esa semana, en orden cronológico. */
    casillas: CasillaRango[];
}

/** Máximo de días que puede abarcar un rango (dos semanas completas). */
export const MAX_DIAS_RANGO = 14;

/**
 * Expande un rango `desde`/`hasta` (ambos inclusive) en casillas, agrupadas por semana. El orden dentro del día es
 * el de `FRANJAS`; solo cuentan las franjas activas del perfil (las desactivadas no generan casilla y, si son un
 * extremo del rango, se avisa). Lógica pura: no lee ni escribe nada.
 */
export const resolverRango = (
    rango: unknown, franjasActivas: readonly string[], weekStartDay = 1,
): { semanas: SemanaRango[]; avisos: string[] } | { error: string } => {
    const r = obj(rango);
    const extremo = (v: unknown, nombre: string): PuntoRango | string => {
        const o = obj(v);
        if (!esFecha(o.fecha)) return `rango.${nombre}.fecha debe tener formato AAAA-MM-DD`;
        const franja = typeof o.franja === "string" ? o.franja : "";
        if (!(FRANJAS as readonly string[]).includes(franja)) return `rango.${nombre}.franja no es válida`;
        return { fecha: o.fecha, franja };
    };
    const desde = extremo(r.desde, "desde");
    if (typeof desde === "string") return { error: desde };
    const hasta = extremo(r.hasta, "hasta");
    if (typeof hasta === "string") return { error: hasta };
    const pos = (f: string) => (FRANJAS as readonly string[]).indexOf(f);
    if (desde.fecha > hasta.fecha || (desde.fecha === hasta.fecha && pos(desde.franja) > pos(hasta.franja))) {
        return { error: "El rango está invertido: `desde` debe ser anterior o igual a `hasta`." };
    }
    if (sumarDias(desde.fecha, MAX_DIAS_RANGO - 1) < hasta.fecha) {
        return { error: `El rango es demasiado largo: como máximo ${MAX_DIAS_RANGO} días.` };
    }
    const avisos: string[] = [];
    for (const [nombre, p] of [["desde", desde], ["hasta", hasta]] as const) {
        if (!franjasActivas.includes(p.franja)) {
            avisos.push(`La franja ${FRANJA_ES[p.franja]} (${nombre} ${p.fecha}) no se planifica en este hogar: no se crea esa casilla.`);
        }
    }
    const semanas = new Map<string, CasillaRango[]>();
    for (let fecha = desde.fecha; fecha <= hasta.fecha; fecha = sumarDias(fecha, 1)) {
        for (const franja of FRANJAS) {
            if (!franjasActivas.includes(franja)) continue;
            if (fecha === desde.fecha && pos(franja) < pos(desde.franja)) continue;
            if (fecha === hasta.fecha && pos(franja) > pos(hasta.franja)) continue;
            const semana = inicioSemana(fecha, weekStartDay);
            const lista = semanas.get(semana) ?? [];
            lista.push({ fecha, franja });
            semanas.set(semana, lista);
        }
    }
    if (semanas.size === 0) avisos.push("El rango no contiene ninguna franja que se planifique en este hogar.");
    return { semanas: [...semanas].map(([semana, casillas]) => ({ semana, casillas })), avisos };
};

export const ERROR_LECTURA = "No he podido leer los datos del menú ahora mismo.";

/** Perfil de comidas del hogar (`GET /meal/profile`); lanza si el api devuelve un error. */
export const leerPerfil = async (leer: Leer): Promise<Obj> => {
    const r = await leer("meal/profile");
    const o = obj(r);
    if (r === null || typeof r !== "object" || "error" in o || !("profile" in o)) throw new Error(ERROR_LECTURA);
    return o;
};

/** Plan de la semana (`GET /meal/plan`): `null` si la semana no tiene plan; lanza si el api devuelve un error. */
export const leerPlan = async (leer: Leer, semana: string): Promise<Obj | null> => {
    const r = await leer("meal/plan", { week_start: semana });
    if (r === null) return null;
    const o = obj(r);
    if ("error" in o || typeof o.id !== "number") throw new Error(ERROR_LECTURA);
    return o;
};

/** Día de inicio de semana del perfil (1 = lunes por defecto). */
export const diaInicio = (perfil: Obj): number => {
    const n = obj(perfil.profile).week_start_day;
    return typeof n === "number" && n >= 1 && n <= 7 ? n : 1;
};

/** Personas que comen en casa ese día y franja, según `meal_schedule` (status distinto de `home` = fuera). */
export const comensalesEn = (perfil: Obj, dia: string, franja: string): { id: number; nombre: string }[] => {
    const wd = isoDow(dia);
    const fuera = new Set(
        arr(perfil.schedule).map(obj)
            .filter((e) => e.weekday === wd && e.slot === franja && e.status !== "home")
            .map((e) => e.home_member_id),
    );
    return arr(perfil.members).map(obj)
        .filter((m) => typeof m.home_member_id === "number" && !fuera.has(m.home_member_id))
        .map((m) => ({ id: m.home_member_id as number, nombre: String(m.name ?? "") }));
};

/** Dieta que obliga a comprobar ingredientes: cualquier valor salvo vacío u `omnivore`. */
const conDieta = (m: Obj): boolean => typeof m.diet === "string" && m.diet.trim() !== "" && m.diet !== "omnivore";

/** Ids de las personas con dieta (vegetariana, vegana, pescetariana, halal, sin cerdo…) o con alguna alergia. */
export const restringidos = (perfil: Obj): Set<number> =>
    new Set(
        arr(perfil.members).map(obj)
            .filter((m) => typeof m.home_member_id === "number" && (conDieta(m) || arr(m.allergies).length > 0))
            .map((m) => m.home_member_id as number),
    );

/**
 * Regla de texto libre: `check_meal_plan` solo evalúa ingredientes con `food_id` del catálogo. Una receta es
 * comprobable si tiene ingredientes y TODOS están enlazados. Si no se puede leer, se trata como no comprobable
 * (falla cerrado).
 */
export const recetaComprobable = async (leer: Leer, id: unknown): Promise<boolean> => {
    try {
        const r = obj(await leer("recipe/detail", { id: String(id) }));
        const ing = arr(r.ingredients).map(obj);
        return ing.length > 0 && ing.every((i) => typeof i.food_id === "number");
    } catch {
        return false;
    }
};

export const AVISO_SIN_CATALOGO =
    "Receta excluida: algún ingrediente no está enlazado a un alimento del catálogo, así que no puedo comprobar su dieta ni sus alergias. No la propongas a quien tenga dieta o alergias; elige otra o guarda la receta con ingredientes del catálogo.";
