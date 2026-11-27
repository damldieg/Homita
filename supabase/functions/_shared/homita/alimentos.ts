// Catálogo de alimentos (`GET /food`) en forma compacta, para el MCP. Los nombres son datos (los hogares pueden
// crear alimentos propios).
import { errorCompacto, nombre, paquete } from "./compacto.ts";

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
