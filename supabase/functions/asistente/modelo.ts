// modelo.ts — Llamada HTTP a la API de Anthropic con un reintento (change kito-calidad-consulta).
// Reintenta una sola vez ante 429, 529 o 5xx respetando `retry-after` (tope 3 s, Q9). Cada fetch tiene como
// plazo el menor entre 30 s y lo que queda del presupuesto de la petición; si no queda margen para el
// reintento, falla con ModelError (el handler responde 502 y devuelve el mensaje al cupo).
import { ModelError } from "./core.ts";
import type { CallModel, ModelResponse } from "./core.ts";

export const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
export const FETCH_TIMEOUT_MS = 30000;
export const RETRY_MAX_MS = 3000;
export const RETRY_POR_DEFECTO_MS = 1000;

export interface ModeloDeps {
    fetch?: (url: string, init: RequestInit) => Promise<Response>;
    sleep?: (ms: number) => Promise<void>;
}

const reintentable = (status: number): boolean => status === 429 || status === 529 || status >= 500;

/** Espera del `retry-after` (segundos o fecha HTTP), acotada a 3 s; sin cabecera, 1 s. */
export const esperaReintento = (cabecera: string | null): number => {
    if (cabecera === null || cabecera.trim() === "") return RETRY_POR_DEFECTO_MS;
    const s = Number(cabecera);
    const ms = Number.isFinite(s) ? s * 1000 : Date.parse(cabecera) - Date.now();
    if (!Number.isFinite(ms)) return RETRY_POR_DEFECTO_MS;
    return Math.min(RETRY_MAX_MS, Math.max(0, ms));
};

export const crearCallModel = (apiKey: string, deps: ModeloDeps = {}): CallModel => {
    const doFetch = deps.fetch ?? ((url, init) => fetch(url, init));
    const sleep = deps.sleep ?? ((ms) => new Promise<void>((r) => setTimeout(r, ms)));

    const intento = async (body: Record<string, unknown>, plazoMs: number): Promise<Response> => {
        try {
            return await doFetch(ANTHROPIC_URL, {
                method: "POST",
                headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
                body: JSON.stringify(body),
                signal: AbortSignal.timeout(plazoMs),
            });
        } catch {
            throw new ModelError("red");
        }
    };

    return async (body, opts) => {
        const restante = opts?.restanteMs ?? (() => Number.POSITIVE_INFINITY);
        if (restante() <= 0) throw new ModelError("presupuesto agotado");
        let res = await intento(body, Math.min(FETCH_TIMEOUT_MS, restante()));
        if (!res.ok && reintentable(res.status)) {
            const espera = esperaReintento(res.headers.get("retry-after"));
            await res.body?.cancel().catch(() => {});
            // Tiene que quedar margen tras la espera para que el reintento pueda completarse.
            if (restante() <= espera) throw new ModelError(`http ${res.status} sin presupuesto para reintentar`);
            await sleep(espera);
            res = await intento(body, Math.min(FETCH_TIMEOUT_MS, restante()));
        }
        if (!res.ok) throw new ModelError(`http ${res.status}`);
        try {
            return await res.json() as ModelResponse;
        } catch {
            throw new ModelError("respuesta no válida");
        }
    };
};
