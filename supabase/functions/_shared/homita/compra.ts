// Compra del hogar (solo lectura), compartida con el MCP: `GET /shopping` (artículos visibles y revisión) y
// `GET /shopping/preview?plan_id=` (lo que entraría en la compra desde un menú, sin guardar nada). Salida compacta
// en español; los nombres de los artículos y de las recetas los escriben las personas del hogar: son datos.
import { errorCompacto, MAX_ITEMS, nombre, paquete } from "./compacto.ts";
import { leerDe } from "./tipos.ts";
import type { LecturaCtx } from "./tipos.ts";

type Obj = Record<string, unknown>;

const obj = (v: unknown): Obj => (v !== null && typeof v === "object" && !Array.isArray(v) ? v as Obj : {});

const ESTADO: Record<string, string> = { pending: "pendiente", checked: "comprado", skipped: "ya lo tengo" };

const cantidad = (v: unknown): number | null => {
    const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
    return Number.isFinite(n) ? n : null;
};

/** Artículo de la compra (`fn_shopping_item_json`). */
export const compactarArticulo = (a: unknown): Obj => {
    const o = obj(a);
    return {
        id: o.id,
        articulo: nombre(o.label),
        cantidad: cantidad(o.quantity),
        unidad: typeof o.unit === "string" ? o.unit : null,
        seccion: typeof o.section === "string" ? o.section : null,
        estado: typeof o.state === "string" ? (ESTADO[o.state] ?? o.state) : null,
        de_menu: o.plan_id !== null && o.plan_id !== undefined,
    };
};

/** Línea de la previsualización (`preview_meal_shopping`): lo que pediría el menú, con las recetas que lo usan. */
export const compactarLineaPrevia = (a: unknown): Obj => {
    const o = obj(a);
    const recetas = [...new Set((Array.isArray(o.sources) ? o.sources : []).map((s) => nombre(obj(s).name)).filter((n) => n !== ""))];
    return {
        articulo: nombre(o.label),
        cantidad: cantidad(o.quantity),
        unidad: typeof o.unit === "string" ? o.unit : null,
        seccion: typeof o.section === "string" ? o.section : null,
        recetas: recetas.slice(0, 10),
    };
};

export interface EntradaCompra {
    /** Id de un menú: devuelve la previsualización de lo que entraría en la compra desde él. */
    plan_id?: number;
    /** Solo los artículos pendientes (sin los comprados ni los «ya lo tengo»). */
    solo_pendientes?: boolean;
}

/** Compra actual del hogar, o la previsualización de un menú si hay `plan_id`. Los errores del api los lanza el lector. */
export const verCompra = async (input: EntradaCompra, ctx: LecturaCtx): Promise<Obj> => {
    const leer = leerDe(ctx);
    if (input.plan_id !== undefined) {
        const crudo = obj(await leer("shopping/preview", { plan_id: String(input.plan_id) }));
        if (!Array.isArray(crudo.items)) return errorCompacto(crudo);
        return { tipo: "previsualizacion", plan_id: crudo.plan_id ?? input.plan_id, ...paquete(crudo.items.map(compactarLineaPrevia)) };
    }
    const crudo = obj(await leer("shopping"));
    if (!Array.isArray(crudo.items)) return errorCompacto(crudo);
    const filas = input.solo_pendientes === true ? crudo.items.filter((a) => obj(a).state === "pending") : crudo.items;
    return { tipo: "compra", revision: crudo.revision ?? null, ...paquete(filas.map(compactarArticulo), {}, filas.length > MAX_ITEMS) };
};
