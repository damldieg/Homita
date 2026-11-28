// Lectura de argumentos y lecturas auxiliares de «organizar», con el lector y el escritor recibidos (no `ToolCtx`).
import type { Leer } from "../tipos.ts";
import { ErrorLectura, esNoExiste, traducir } from "./errores.ts";
import type { Input, Obj, OrgCtx } from "./tipos.ts";

export type { Input, Obj };

export const texto = (i: Input, k: string): string | undefined => {
    const v = i[k];
    return typeof v === "string" && v.trim() !== "" ? v.trim() : undefined;
};
export const entero = (i: Input, k: string): number | undefined => {
    const v = i[k];
    if (typeof v === "number" && Number.isInteger(v) && v > 0) return v;
    if (typeof v === "string" && /^[1-9]\d{0,17}$/.test(v.trim())) return Number(v.trim());
    return undefined;
};
export const enteroNoNeg = (i: Input, k: string): number | undefined => {
    const v = i[k];
    return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : undefined;
};
export const booleano = (i: Input, k: string): boolean | undefined => (typeof i[k] === "boolean" ? i[k] as boolean : undefined);
export const lista = (i: Input, k: string): unknown[] | undefined => (Array.isArray(i[k]) ? i[k] as unknown[] : undefined);
/** Ids enteros positivos; `null` si algún elemento no lo es. */
export const ids = (i: Input, k: string): number[] | null | undefined => {
    const l = lista(i, k);
    if (l === undefined) return undefined;
    const r = l.filter((x): x is number => typeof x === "number" && Number.isInteger(x) && x > 0);
    return r.length === l.length ? [...new Set(r)] : null;
};

export const objeto = (v: unknown): Obj => (v !== null && typeof v === "object" ? v as Obj : {});

/** Respuesta de «falta algo»: no se llama al api y quien llama lo pregunta. */
export const falta = (campos: string[], extra: Obj = {}): Obj => ({ falta: campos, ...extra });

/** Lista del api, o null si el lector devolvió un error o una forma inesperada. */
export const filas = async (leer: Leer | undefined, ruta: string): Promise<Obj[] | null> => {
    if (!leer) return null;
    const r = await leer(ruta);
    return Array.isArray(r) ? r.filter((x): x is Obj => x !== null && typeof x === "object") : null;
};

export const YA_NO_EXISTE = { ok: false, error: "Ya no existe." };

/** Una fila de una lista del api por id, o `null` si ya no existe. Lanza si no hay lector o falla la lectura. */
export const filaPorId = async (c: OrgCtx, ruta: string, id: number): Promise<Obj | null> => {
    const todas = await filas(c.leer, ruta);
    if (todas === null) throw new ErrorLectura("No he podido leer los datos ahora mismo.");
    return todas.find((f) => Number(f.id) === id) ?? null;
};

/** Lee el detalle de un elemento con el escritor (GET). `null` si ya no existe; lanza ante otros fallos. */
export const detalle = async (c: OrgCtx, ruta: string, id: number): Promise<Obj | null> => {
    const r = await c.escribir!("GET", ruta, { id });
    if (r.ok) return objeto(r.data);
    if (esNoExiste(r.status, r.error)) return null;
    throw new ErrorLectura(traducir(r.status, r.error));
};

/**
 * Elemento de destino (lista, calendario) de un alta: el indicado o, si solo hay uno donde se pueda escribir,
 * ese. Con varios y sin indicar, `falta` lleva las opciones para preguntar al usuario.
 */
export const resolverDestino = async (
    c: OrgCtx,
    ruta: string,
    singular: string,
    id: number | undefined,
): Promise<{ id: number; nombre: string } | { falta: Obj } | { error: string }> => {
    const todas = await filas(c.leer, ruta);
    if (todas === null) return { error: `No he podido leer tus ${singular}s ahora mismo.` };
    if (id !== undefined) {
        const x = todas.find((f) => Number(f.id) === id);
        return x ? { id, nombre: String(x.name) } : { error: "Ya no existe." };
    }
    const editables = todas.filter((f) => f.can_edit !== false);
    if (editables.length === 0) return { error: `No tienes ningún ${singular} donde puedas escribir.` };
    if (editables.length === 1) return { id: Number(editables[0].id), nombre: String(editables[0].name) };
    return { falta: falta([singular], { opciones: editables.map((f) => ({ id: f.id, nombre: f.name })) }) };
};
