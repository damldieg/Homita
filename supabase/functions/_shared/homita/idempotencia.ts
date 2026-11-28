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
