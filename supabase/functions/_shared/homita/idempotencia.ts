// `client_request_id` deterministas de las escrituras del MCP. Salen del contenido (más la revisión del plan o el día),
// así que reintentar la misma llamada no duplica. Llevan el prefijo `mcp-` para no colisionar con los de Kito.
import { uuidDe } from "./uuid.ts";

/** Borrador de una semana: misma propuesta sobre la misma revisión = mismo UUID. */
export const idBorrador = (user: string, home: string, semana: string, revision: number, items: unknown): Promise<string> =>
    uuidDe(`mcp-borrador|${user}|${home}|${semana}|${revision}|${JSON.stringify(items)}`);

/** Cambios de casillas de un plan sobre una revisión. */
export const idCambios = (user: string, home: string, planId: number, revision: number, items: unknown): Promise<string> =>
    uuidDe(`mcp-cambios|${user}|${home}|${planId}|${revision}|${JSON.stringify(items)}`);

/** Receta: por contenido (el cuerpo lleva el `food_id` ya resuelto). */
export const idReceta = (user: string, home: string, cuerpo: unknown): Promise<string> =>
    uuidDe(`mcp-receta|${user}|${home}|${JSON.stringify(cuerpo)}`);

/** Artículo de compra: mismo artículo (normalizado) el mismo día local = mismo UUID; otro día, otro. */
export const idCompra = (user: string, home: string, dia: string, articulo: unknown): Promise<string> =>
    uuidDe(`mcp-compra|${user}|${home}|${dia}|${JSON.stringify(articulo)}`);

/** JSON con las claves de los objetos ordenadas recursivamente y sin `undefined`: la misma entrada da el mismo texto. */
const canonico = (valor: unknown): string => {
    const orden = (v: unknown): unknown => {
        if (Array.isArray(v)) return v.map(orden);
        if (v !== null && typeof v === "object") {
            const o = v as Record<string, unknown>;
            const r: Record<string, unknown> = {};
            for (const k of Object.keys(o).sort()) if (o[k] !== undefined) r[k] = orden(o[k]);
            return r;
        }
        return v;
    };
    return JSON.stringify(orden(valor));
};

/**
 * Alta de una lista o de una tarea desde el MCP: mismo usuario, hogar, herramienta y cuerpo ya resuelto (sin
 * `client_request_id`) en el mismo minuto = mismo UUID. Un reintento dentro del minuto no duplica; uno que cruza el
 * minuto sí, y dos altas idénticas e intencionadas en el mismo minuto colapsan en una.
 */
export const idOrganizar = (user: string, home: string, herramienta: string, cuerpo: Record<string, unknown>, ahora: Date): Promise<string> => {
    const { client_request_id: _omitido, ...sinClave } = cuerpo;
    return uuidDe(`mcp-organizar|${user}|${home}|${herramienta}|${canonico(sinClave)}|${Math.floor(ahora.getTime() / 60000)}`);
};
