// Tipos comunes de la lectura de Homita (los comparten Kito y el MCP). Este módulo no importa nada de
// `asistente/` ni de `mcp/`: son ellos los que importan de aquí.

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
