// Traducción de un error del api a una frase para el modelo (sin detalles técnicos). La usan Kito y, como base, el MCP.
// Movido sin cambios desde `asistente/skills/menus/util.ts`.
import type { Obj } from "./menus.ts";

/** Respuesta de una escritura al api (forma estructural de `RespuestaApi` de Kito). */
export interface RespuestaEscritura {
    ok: boolean;
    status: number;
    data: unknown;
    error?: string;
}

/** Frase para el modelo a partir de un error del api (sin detalles técnicos). */
export const errorEscritura = (r: RespuestaEscritura): Obj => {
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
