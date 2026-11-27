// Tipos comunes de la lectura de Homita (los comparten Kito y el MCP). Este módulo no importa nada de
// Kito ni del MCP: son ellos los que importan de aquí.

/** Lectura de una ruta GET del `api` (con el JWT y la zona del usuario). Un error HTTP vuelve como `{error, detalle}`. */
export type Leer = (ruta: string, params?: Record<string, string | undefined>) => Promise<unknown>;

/**
 * Lo que necesita la lógica de lectura de quien la llama. Es un subconjunto estructural de `ToolCtx` de Kito,
 * así que `ToolCtx` se pasa tal cual; el MCP construye uno propio.
 */
export interface LecturaCtx {
    homeId: string | null;
    timezone: string;
    now: Date;
    /** app_user.id numérico del usuario (para localizar sus personas en el hogar activo). */
    appUserId?: string;
    /** Códigos de permiso del usuario en el hogar activo. Hoy ni Kito ni el MCP los rellenan: la salud se omite. */
    permisos?: string[];
    /** Lector del api. */
    leer?: Leer;
}

/** Argumento no válido (fecha mal escrita, valor fuera de lista…): el mensaje, en español, se puede enseñar tal cual. */
export class ErrorEntrada extends Error {}

/** Lector del contexto; lanza si quien llama no lo ha inyectado. */
export const leerDe = (ctx: LecturaCtx): Leer => {
    if (!ctx.leer) throw new Error("lectura de datos no disponible");
    return ctx.leer;
};
