// Errores de herramienta del MCP: `isError: true` con un texto en español por estado. Nunca el cuerpo crudo del api.

/** El api respondió con un error (o con algo que no era JSON). */
export class ErrorApi extends Error {
    constructor(readonly status: number) {
        super(`api ${status}`);
    }
}

/** Una escritura del api falló (estado HTTP y, si lo hay, el mensaje breve del api, p. ej. «Invalid recipe»). */
export class ErrorEscritura extends Error {
    constructor(readonly status: number, readonly detalle?: string) {
        super(`api ${status}`);
    }
}

/** Resultado de herramienta (la parte del protocolo que usamos). */
export interface ResultadoTool {
    content: { type: "text"; text: string }[];
    isError?: boolean;
    [clave: string]: unknown;
}

export const textoDeEstado = (status: number): string => {
    if (status === 401) return "La sesión ha caducado: vuelve a conectar Homita desde Claude.";
    if (status === 403) return "No tienes permiso para ver eso en este hogar.";
    if (status === 404) return "Eso no existe o no tienes acceso.";
    return "No he podido leer los datos de Homita ahora mismo.";
};

/** Texto para el modelo de una escritura fallida, sin detalles internos. */
export const textoDeEscritura = (status: number, detalle?: string): string => {
    if (status === 401) return textoDeEstado(401);
    if (status === 403) return "No tienes permiso para hacer eso en este hogar.";
    if (status === 404 || (status === 500 && detalle === "Not Found")) return "Eso ya no existe o no tienes acceso.";
    if (status === 409) return "Ha cambiado desde que lo leíste. Vuelve a leerlo y repite el cambio con la revisión nueva.";
    if (status === 400) {
        const motivo = typeof detalle === "string" && detalle.trim() !== "" ? detalle.trim().slice(0, 160) : "datos no válidos";
        return `No se ha podido guardar: ${motivo}.`;
    }
    return "No he podido guardarlo ahora mismo.";
};

export const errorTool = (mensaje: string): ResultadoTool => ({ content: [{ type: "text", text: mensaje }], isError: true });

/**
 * JSON compacto como texto. Si el valor trae un `error` en texto en la raíz (error de entrada o de lectura de la
 * lógica compartida), el resultado se marca como error.
 */
export const resultadoJson = (valor: unknown): ResultadoTool => {
    const raiz = valor !== null && typeof valor === "object" ? valor as Record<string, unknown> : {};
    const esError = typeof raiz.error === "string";
    return { content: [{ type: "text", text: JSON.stringify(valor ?? null) }], ...(esError ? { isError: true } : {}) };
};
