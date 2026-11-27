// Errores de herramienta del MCP: `isError: true` con un texto en español por estado. Nunca el cuerpo crudo del api.

/** El api respondió con un error (o con algo que no era JSON). */
export class ErrorApi extends Error {
    constructor(readonly status: number) {
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
