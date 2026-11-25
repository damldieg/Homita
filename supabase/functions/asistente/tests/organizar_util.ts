// Utilidades de los tests de la skill `organizar`: escritor y lector falsos, contexto y modelo falso.
import type { CallOpts, Escribir, Leer, ModelResponse, RespuestaApi, ToolCtx } from "../core.ts";

export interface Llamada {
    metodo: string;
    ruta: string;
    cuerpo: Record<string, unknown>;
}

export type Respuestas = Record<string, RespuestaApi | ((c: Llamada) => RespuestaApi)>;

export const ok = (data: unknown, status = 200): RespuestaApi => ({ ok: true, status, data });
export const fallo = (status: number, error: string): RespuestaApi => ({ ok: false, status, data: { error }, error });

/** Escritor falso: registra las llamadas; `respuestas` se indexa por «METODO ruta» (por defecto, ok con id 1). */
export const escritorFalso = (respuestas: Respuestas = {}) => {
    const llamadas: Llamada[] = [];
    const escribir: Escribir = (metodo, ruta, cuerpo = {}) => {
        const c = { metodo, ruta, cuerpo };
        llamadas.push(c);
        const r = respuestas[`${metodo} ${ruta}`];
        return Promise.resolve(typeof r === "function" ? r(c) : (r ?? ok({ id: 1 })));
    };
    return { escribir, llamadas };
};

export const lectorFalso = (datos: Record<string, unknown>): Leer => (ruta) => Promise.resolve(datos[ruta] ?? []);

export const SECRETO = "secreto-de-prueba";

export const ctxDe = (over: Partial<ToolCtx> = {}): ToolCtx => ({
    token: "jwt",
    uid: "uid-1",
    homeId: "7",
    timezone: "Europe/Madrid",
    now: new Date("2026-11-25T10:00:00Z"),
    appUserId: "501",
    ...over,
});

export const texto = (t: string): ModelResponse => ({ stop_reason: "end_turn", content: [{ type: "text", text: t }] });
export const usa = (...usos: { name: string; input: Record<string, unknown>; id?: string }[]): ModelResponse => ({
    stop_reason: "tool_use",
    content: usos.map((u, i) => ({ type: "tool_use", id: u.id ?? `toolu_${i + 1}`, name: u.name, input: u.input })),
});

export const modeloFalso = (respuestas: ModelResponse[]) => {
    const cuerpos: Record<string, unknown>[] = [];
    let i = 0;
    const call = (body: Record<string, unknown>, _o?: CallOpts): Promise<ModelResponse> => {
        cuerpos.push(JSON.parse(JSON.stringify(body)));
        const r = respuestas[Math.min(i, respuestas.length - 1)];
        i++;
        return Promise.resolve(r);
    };
    return { call, cuerpos };
};
