// Ayudas de los tests del MCP: tokens falsos, dependencias falsas y cliente JSON-RPC contra el handler real
// (`createMcpHandler` de verdad, sin red: el api es un `leerRuta` falso). El hogar activo se comprueba con el
// `runWithHome`/`currentHome` reales de `api`.
import { createHandler } from "../handler.ts";
import type { HandlerDeps } from "../handler.ts";
import { currentHome, runWithHome } from "../../api/_shared/home.ts";

export const URL_MCP = "https://x.test/functions/v1/mcp";
export const UID = "11111111-1111-1111-1111-111111111111";
export const CLIENTE = "22222222-2222-2222-2222-222222222222";

const b64 = (o: unknown): string => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/** JWT falso (la firma no se valida aquí: lo hace `userInfo`). Por defecto, un token OAuth válido. */
export const jwt = (claims: Record<string, unknown> = {}): string =>
    `${b64({ alg: "ES256", typ: "JWT" })}.${b64({ sub: UID, aud: "authenticated", role: "authenticated", client_id: CLIENTE, ...claims })}.firma`;

export const TOKEN = jwt();

export interface Llamada {
    ruta: string;
    params: Record<string, string | undefined>;
    token: string;
    uid: string;
    tz: string;
    /** Hogar activo (`currentHome()`) en el momento de la llamada. */
    hogar: string | null;
}

/** Una escritura que hizo una herramienta (con el hogar activo en ese momento). */
export interface Escritura {
    metodo: string;
    ruta: string;
    cuerpo: Record<string, unknown>;
    token: string;
    uid: string;
    tz: string;
    hogar: string | null;
}

/** Respuesta falsa de una escritura: valor fijo o función del cuerpo y del nº de llamada a esa ruta. */
export type RespuestaEscrituraFalsa = { ok: boolean; status: number; data: unknown; error?: string };
export type EscrituraFalsa = RespuestaEscrituraFalsa | ((cuerpo: Record<string, unknown>, n: number) => RespuestaEscrituraFalsa);

export interface Mundo {
    /** Escrituras recibidas por el escritor falso, en orden. */
    escrituras: Escritura[];
    /** Orden de TODAS las llamadas (lecturas y escrituras): `GET ruta` / `METODO ruta`. */
    orden: string[];
    deps: HandlerDeps;
    llamadas: Llamada[];
    /** Hogares a los que pertenece el usuario (`checkHomeMember`). */
    miembroDe: Set<string>;
    comprobaciones: string[];
    userInfoLlamadas: string[];
}

export const HOGARES = [
    { home_id: 7, name: "Casa", role: "admin", is_default: true, is_personal: true },
    { home_id: 8, name: "Abuelos", role: "member", is_default: false, is_personal: false },
];

export const crearMundo = (
    respuestas: Record<string, unknown> = {},
    over: Partial<HandlerDeps> = {},
    fallos: Record<string, number> = {},
    escrituraFalsa: Record<string, EscrituraFalsa> = {},
): Mundo => {
    const escrituras: Escritura[] = [];
    const orden: string[] = [];
    const contadores = new Map<string, number>();
    const llamadas: Llamada[] = [];
    const comprobaciones: string[] = [];
    const userInfoLlamadas: string[] = [];
    const miembroDe = new Set(["7", "8"]);
    const deps: HandlerDeps = {
        userInfo: (token) => {
            userInfoLlamadas.push(token);
            return Promise.resolve({ id: UID });
        },
        audience: "authenticated",
        publicUrl: URL_MCP,
        authUrl: "https://x.test/auth/v1",
        leerRuta: (ruta, params, token, uid, tz) => {
            llamadas.push({ ruta, params, token, uid, tz, hogar: currentHome() });
            orden.push(`GET ${ruta}`);
            const status = fallos[ruta];
            if (status !== undefined) return Promise.resolve({ ok: false, status, body: { error: "interno secreto" }, texto: "", json: true });
            const body = ruta in respuestas ? respuestas[ruta] : ruta === "home" ? HOGARES : [];
            return Promise.resolve({ ok: true, status: 200, body, texto: JSON.stringify(body), json: true });
        },
        crearEscritor: (token, uid, tz) => (metodo, ruta, cuerpo = {}) => {
            escrituras.push({ metodo, ruta, cuerpo: { ...cuerpo }, token, uid, tz, hogar: currentHome() });
            orden.push(`${metodo} ${ruta}`);
            const clave = `${metodo} ${ruta}`;
            const n = (contadores.get(clave) ?? 0) + 1;
            contadores.set(clave, n);
            const f = escrituraFalsa[clave];
            if (f === undefined) return Promise.resolve({ ok: false, status: 500, data: null });
            return Promise.resolve(typeof f === "function" ? f(cuerpo, n) : f);
        },
        checkHomeMember: (homeId) => {
            comprobaciones.push(homeId);
            return Promise.resolve(miembroDe.has(homeId));
        },
        runInHome: (homeId, fn) => runWithHome(homeId, fn),
        appUserId: () => Promise.resolve("5"),
        now: () => new Date("2030-01-07T10:00:00Z"),
        ...over,
    };
    return { deps, llamadas, miembroDe, comprobaciones, userInfoLlamadas, escrituras, orden };
};

export const peticion = (body: unknown, token: string | null = TOKEN, extra: Record<string, string> = {}): Request =>
    new Request(URL_MCP, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Accept: "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-06-18",
            ...(token === null ? {} : { Authorization: `Bearer ${token}` }),
            ...extra,
        },
        body: JSON.stringify(body),
    });

/** Cuerpo JSON-RPC de una respuesta (JSON o SSE con un `data:`). */
export const rpcDe = async (res: Response): Promise<{ result?: Record<string, unknown>; error?: Record<string, unknown> }> => {
    const texto = await res.text();
    const linea = texto.split("\n").find((l) => l.startsWith("data:"));
    return JSON.parse(linea ? linea.slice(5).trim() : texto);
};

export interface ResultadoLlamada {
    isError?: boolean;
    content: { type: string; text: string }[];
}

/** Llama a una herramienta con un token y devuelve `{res, resultado, datos}`; `datos` es el JSON del texto si lo es. */
export const llamarTool = async (mundo: Mundo, nombre: string, args: Record<string, unknown> = {}, token = TOKEN) => {
    const handler = createHandler(mundo.deps);
    const res = await handler(peticion({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: nombre, arguments: args } }, token));
    const rpc = await rpcDe(res);
    const resultado = rpc.result as unknown as ResultadoLlamada | undefined;
    let datos: unknown = null;
    try {
        datos = JSON.parse(resultado?.content?.[0]?.text ?? "null");
    } catch { /* texto plano */ }
    return { res, rpc, resultado, datos };
};
