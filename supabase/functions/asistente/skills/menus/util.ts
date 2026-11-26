// Utilidades de la skill `menus`: lectura de argumentos, fechas de semana (aritmética en UTC, sin zona) y lectores
// del perfil y del plan con el lector del usuario (`ctx.leer`). Sin dependencias de `api`.
import type { Escribir, Leer, RespuestaApi, ToolCtx } from "../../core.ts";
import type { Tool } from "../../core.ts";

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

export const leerDe = (ctx: ToolCtx): Leer => {
    if (!ctx.leer) throw new Error("lectura de datos no disponible");
    return ctx.leer;
};
export const escribirDe = (ctx: ToolCtx): Escribir => {
    if (!ctx.escribir) throw new Error("escritura de datos no disponible");
    return ctx.escribir;
};

/** Esquema de entrada de una herramienta: sin propiedades extra y sin uniones con null (strict se desactiva). */
export const esquema = (properties: Record<string, unknown>, required: string[] = []): Tool["input_schema"] =>
    ({ type: "object", properties, required, additionalProperties: false });

/** Respuesta de «falta algo»: no se llama al api y Kito lo pregunta. */
export const falta = (campos: string[], extra: Obj = {}): Obj => ({ falta: campos, ...extra });

export const ERROR_LECTURA = "No he podido leer los datos del menú ahora mismo.";

/** Perfil de comidas del hogar (`GET /meal/profile`); lanza si el api devuelve un error. */
export const leerPerfil = async (ctx: ToolCtx): Promise<Obj> => {
    const r = await leerDe(ctx)("meal/profile");
    const o = obj(r);
    if (r === null || typeof r !== "object" || "error" in o || !("profile" in o)) throw new Error(ERROR_LECTURA);
    return o;
};

/** Plan de la semana (`GET /meal/plan`): `null` si la semana no tiene plan; lanza si el api devuelve un error. */
export const leerPlan = async (ctx: ToolCtx, semana: string): Promise<Obj | null> => {
    const r = await leerDe(ctx)("meal/plan", { week_start: semana });
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

/** Frase para el modelo a partir de un error del api (sin detalles técnicos). */
export const errorEscritura = (r: RespuestaApi): Obj => {
    if (r.status === 409) {
        return { ok: false, revision_vieja: true, error: "El menú ha cambiado desde que lo leí. Léelo otra vez con leer_semana y vuelve a intentarlo." };
    }
    if (r.status === 403) return { ok: false, error: "No tienes permiso para hacer eso en el menú del hogar." };
    if (r.status === 404 || (r.status === 500 && r.error === "Not Found")) return { ok: false, error: "Ya no existe." };
    if (r.status === 400) {
        const motivo = typeof r.error === "string" && r.error.trim() !== "" ? r.error.trim().slice(0, 160) : "datos no válidos";
        return { ok: false, error: `No se ha podido guardar: ${motivo}.` };
    }
    return { ok: false, error: "No he podido guardarlo ahora mismo." };
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
export const recetaComprobable = async (ctx: ToolCtx, id: unknown): Promise<boolean> => {
    try {
        const r = obj(await leerDe(ctx)("recipe/detail", { id: String(id) }));
        const ing = arr(r.ingredients).map(obj);
        return ing.length > 0 && ing.every((i) => typeof i.food_id === "number");
    } catch {
        return false;
    }
};

export const AVISO_SIN_CATALOGO =
    "Receta excluida: algún ingrediente no está enlazado a un alimento del catálogo, así que no puedo comprobar su dieta ni sus alergias. No la propongas a quien tenga dieta o alergias; elige otra o guarda la receta con ingredientes del catálogo.";
