// Handler HTTP del MCP: CORS, metadatos OAuth del recurso protegido, autenticación y MCP (Streamable HTTP sin estado:
// un McpServer nuevo por petición con `createMcpHandler`). Sin Deno.serve ni env: todo entra por `HandlerDeps`
// (los tests inyectan falsos; el cableado real está en index.ts).
import { createMcpHandler } from "./deps.ts";
import { bearerDe, verificarToken } from "./auth.ts";
import type { UserInfo } from "./auth.ts";
import type { Entorno } from "./entorno.ts";
import { crearServidor } from "./tools/registro.ts";

export interface HandlerDeps extends Omit<Entorno, "token" | "uid"> {
    userInfo: UserInfo;
    /** Audiencia esperada de los tokens (`MCP_TOKEN_AUDIENCE`). */
    audience: string;
    /** URL pública del MCP (`MCP_PUBLIC_URL`); sin ella se deduce de la petición. */
    publicUrl?: string;
    /** URL del servidor de autorización (`MCP_AUTH_URL`); sin ella, `<origen público>/auth/v1`. */
    authUrl?: string;
}

const RUTA_METADATOS = "/.well-known/oauth-protected-resource";

const CORS: Record<string, string> = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, content-type, mcp-protocol-version, accept",
    "Access-Control-Expose-Headers": "WWW-Authenticate",
};

const HOST_OK = /^[a-z0-9.\-]+(:[0-9]{1,5})?$|^\[[0-9a-f:]+\](:[0-9]{1,5})?$/i;

/** Origen público (esquema y host) según el proxy del Edge; si las cabeceras no valen, el de la URL de la petición. */
const origenPublico = (req: Request): string => {
    const url = new URL(req.url);
    const h = req.headers;
    const proto = h.get("x-forwarded-proto") === "https" ? "https" : h.get("x-forwarded-proto") === "http" ? "http" : url.protocol.replace(":", "");
    const host = h.get("x-forwarded-host") ?? "";
    if (!HOST_OK.test(host)) return `${proto}://${url.host}`;
    const puerto = h.get("x-forwarded-port") ?? "";
    const defecto = proto === "https" ? "443" : "80";
    const conPuerto = host.includes(":") || !/^[0-9]{1,5}$/.test(puerto) || puerto === defecto ? host : `${host}:${puerto}`;
    return `${proto}://${conPuerto}`;
};

const sinBarraFinal = (s: string): string => s.replace(/\/+$/, "");

export const urlsPublicas = (req: Request, deps: Pick<HandlerDeps, "publicUrl" | "authUrl">): { recurso: string; auth: string } => {
    const origen = origenPublico(req);
    const recurso = deps.publicUrl ? sinBarraFinal(deps.publicUrl) : `${origen}/functions/v1/mcp`;
    const auth = deps.authUrl ? sinBarraFinal(deps.authUrl) : `${new URL(recurso).origin}/auth/v1`;
    return { recurso, auth };
};

const conCors = (res: Response): Response => {
    const headers = new Headers(res.headers);
    for (const [k, v] of Object.entries(CORS)) headers.set(k, v);
    return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
};

const json = (cuerpo: unknown, status = 200, extra: Record<string, string> = {}): Response =>
    new Response(JSON.stringify(cuerpo), { status, headers: { "Content-Type": "application/json", ...CORS, ...extra } });

export const createHandler = (deps: HandlerDeps) => async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const { recurso, auth } = urlsPublicas(req, deps);
    const ruta = new URL(req.url).pathname;

    // Metadatos del recurso protegido (RFC 9728): sin autenticación.
    if (ruta.endsWith(RUTA_METADATOS)) {
        if (req.method !== "GET") return json({ error: "Method not allowed" }, 405);
        return json({
            resource: recurso,
            authorization_servers: [auth],
            bearer_methods_supported: ["header"],
            resource_name: "Homita",
        });
    }

    const desafio = (error?: string): Response =>
        json({ error: error ?? "unauthorized" }, 401, {
            "WWW-Authenticate": `Bearer ${error ? `error="${error}", ` : ""}resource_metadata="${recurso}${RUTA_METADATOS}"`,
        });

    const token = bearerDe(req);
    if (token === null) return desafio();
    const quien = await verificarToken(token, { userInfo: deps.userInfo, audience: deps.audience });
    if (quien === null) return desafio("invalid_token");

    const env: Entorno = {
        token,
        uid: quien.uid,
        leerRuta: deps.leerRuta,
        checkHomeMember: deps.checkHomeMember,
        runInHome: deps.runInHome,
        appUserId: deps.appUserId,
        now: deps.now,
    };
    try {
        const mcp = createMcpHandler(() => crearServidor(env), {
            onerror: () => console.error("mcp: error del protocolo"),
        });
        return conCors(await mcp.fetch(req, { authInfo: { token, clientId: quien.clientId, scopes: [] } }));
    } catch {
        console.error("mcp: error al servir la petición");
        return json({ jsonrpc: "2.0", error: { code: -32603, message: "Error interno" }, id: null }, 500);
    }
};
