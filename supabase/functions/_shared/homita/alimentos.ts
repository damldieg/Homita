// Catálogo de alimentos (`GET /food`) en forma compacta, para el MCP. Los nombres son datos (los hogares pueden
// crear alimentos propios).
import { errorCompacto, nombre, paquete } from "./compacto.ts";
import { norm } from "./menus.ts";
import type { Leer } from "./tipos.ts";

const obj = (v: unknown): Record<string, unknown> => (v !== null && typeof v === "object" ? v as Record<string, unknown> : {});

export const compactarAlimentos = (crudo: unknown): Record<string, unknown> => {
    if (!Array.isArray(crudo)) return errorCompacto(crudo);
    return paquete(crudo.map((f) => {
        const o = obj(f);
        return {
            id: o.id,
            nombre: nombre(o.name),
            seccion: typeof o.section === "string" ? o.section : null,
            alergenos: Array.isArray(o.allergens) ? o.allergens.filter((a): a is string => typeof a === "string").slice(0, 20) : [],
            unidad: typeof o.default_unit === "string" ? o.default_unit : null,
            del_hogar: o.home_id !== null && o.home_id !== undefined,
        };
    }));
};

/**
 * Alimento del catálogo (comunes y del hogar) con ese nombre exacto (sin acentos ni mayúsculas); sin coincidencia
 * exacta no se adivina. Es la misma regla que usa Kito al enlazar ingredientes. `null` si no hay o si la lectura falla.
 */
export const alimentoPorNombre = async (leer: Leer, nombreBuscado: string): Promise<Record<string, unknown> | null> => {
    const r = await leer("food", { q: nombreBuscado, limit: "50" }).catch(() => null);
    if (!Array.isArray(r)) return null;
    const n = norm(nombreBuscado);
    const hit = r.map(obj).find((f) => typeof f.name === "string" && norm(f.name) === n && typeof f.id === "number");
    return hit ?? null;
};
