// Tipos comunes de la lógica de «organizar» (listas, tareas, eventos, rutinas, calendarios). La comparten Kito
// (`asistente/skills/organizar`) y el MCP: nada de aquí importa de ellos.
import type { EscribirFn } from "../escritor.ts";
import type { Leer } from "../tipos.ts";

export type Obj = Record<string, unknown>;
export type Input = Record<string, unknown>;

/** Qué ha cambiado una escritura, para que la app recargue (aditivo en la respuesta de Kito). */
export interface Cambio {
    tipo: "tarea" | "lista" | "evento" | "rutina" | "calendario" | "menu" | "receta" | "compra";
    id: number | string | null;
    op: "crear" | "editar" | "borrar";
}

/** Una acción = {op, args}: `args` es el cuerpo que recibe el caso de uso del api (más claves de altas compuestas). */
export interface Accion {
    op: string;
    args: Obj;
    /** Nombre del elemento (solo para frases de permisos y de resultado); no cambia lo que se ejecuta. */
    nombre?: string;
}

export interface ResultadoAccion {
    ok: boolean;
    /** Borrado de algo que ya no existía: se da por hecho. */
    yaEstaba?: boolean;
    id: number | string | null;
    cambios: Cambio[];
    /** Frase de lo hecho (o del error si `ok` es false). */
    texto: string;
    /** Fallos parciales de una alta compuesta (fecha límite, compartir). */
    avisos: string[];
}

/**
 * Lo que necesitan las funciones `preparar*`. Es un subconjunto estructural de `ToolCtx` de Kito; el MCP construye
 * uno propio. `escribir` solo se usa para los GET de detalle.
 */
export interface OrgCtx {
    homeId: string | null;
    timezone: string;
    now: Date;
    /** app_user.id numérico del usuario. */
    appUserId?: string;
    leer?: Leer;
    escribir?: EscribirFn;
}

/**
 * Resultado de preparar una herramienta: o una acción lista para ejecutar (con la frase de la tarjeta de Kito y los
 * datos extra para el modelo) o un resultado ya terminado (`falta`, error, «ya no existe»), que no llama al api.
 */
export type Preparacion = { accion: Accion; frase?: string; extra?: Obj } | { valor: unknown };

export const listo = (valor: unknown): Preparacion => ({ valor });

/**
 * Calcula el `client_request_id` de un alta a partir del cuerpo ya resuelto (sin la clave). Kito lo deriva del
 * `tool_use.id` e ignora el cuerpo; el MCP lo deriva del contenido y del minuto. `undefined` = sin clave.
 */
export type ClaveFn = (cuerpo: Obj) => Promise<string | undefined> | string | undefined;
