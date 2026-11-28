// Errores del `api` traducidos a frases para el usuario (organizar). Sin dependencias de `api`.

/** El api devuelve el «Not Found» de una RPC como 500 (errNotFound500), no como 404. */
export const esNoExiste = (status: number, error: unknown): boolean =>
    status === 404 || (status === 500 && error === "Not Found");

/**
 * Frase para el usuario a partir de la respuesta de error del api. `nombre` es el elemento afectado
 * («Compra», «Fútbol») para el mensaje de permisos.
 */
export const traducir = (status: number, error: unknown, nombre?: string): string => {
    if (status === 403) return `No tienes permiso de edición en ${nombre ? `«${nombre}»` : "eso"}.`;
    if (esNoExiste(status, error)) return "Ya no existe.";
    if (status === 400) {
        const motivo = typeof error === "string" && error.trim() !== "" ? error.trim().slice(0, 160) : "datos no válidos";
        return `No se ha podido hacer: ${motivo}.`;
    }
    return "No he podido hacerlo ahora mismo.";
};
