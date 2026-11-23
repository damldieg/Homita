// Edge Function `asistente` (change kito-asistente). Solo cableado: la lógica está en handler.ts y core.ts.
// Se despliega con --no-verify-jwt (auth manual, como `api`): el Bearer del usuario se verifica en handler.ts.
// Secretos: ANTHROPIC_API_KEY (obligatorio; sin él la función falla cerrada) y KITO_MODEL (por defecto
// claude-haiku-5-5). No usa CLAUDE_MODEL, que es del feedback.
import { ModelError } from "./core.ts";
import type { CallModel, ModelResponse } from "./core.ts";
import { createHandler } from "./handler.ts";
import type { UsageDb, UsoResultado } from "./handler.ts";
import { SKILLS } from "./skills/registry.ts";
import { crearLector } from "./skills/consulta/api.ts";
import { appUserRow, verifyUser } from "../api/_shared/supabase.ts";
import { checkHomeMember, runWithHome } from "../api/_shared/home.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL = "claude-haiku-5-5";
const MODEL_TIMEOUT_MS = 30000;

// Uso (tope diario y tokens): solo service_role; las RPC no tienen grants para anon/authenticated.
const rpcServicio = (name: string, args: Record<string, unknown>): Promise<Response> =>
    fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(args),
    });

const usage: UsageDb = {
    async consume(appUserId: string, timezone: string): Promise<UsoResultado> {
        const res = await rpcServicio("assistant_consume", { p_app_user_id: Number(appUserId), p_timezone: timezone });
        if (!res.ok) throw new Error(`assistant_consume ${res.status}`);
        return await res.json() as UsoResultado;
    },
    async record(appUserId, day, t, refund) {
        const res = await rpcServicio("assistant_record_usage", {
            p_app_user_id: Number(appUserId),
            p_day: day,
            p_input: t.input,
            p_output: t.output,
            p_cache_read: t.cacheRead,
            p_cache_write: t.cacheWrite,
            p_refund: refund,
        });
        if (!res.ok) throw new Error(`assistant_record_usage ${res.status}`);
    },
};

const callModel = (apiKey: string): CallModel => async (body) => {
    let res: Response;
    try {
        res = await fetch(ANTHROPIC_URL, {
            method: "POST",
            headers: {
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(MODEL_TIMEOUT_MS),
        });
    } catch {
        throw new ModelError("red");
    }
    if (!res.ok) throw new ModelError(`http ${res.status}`);
    try {
        return await res.json() as ModelResponse;
    } catch {
        throw new ModelError("respuesta no válida");
    }
};

const nombres = new Map<string, string | null>();
const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

Deno.serve(createHandler({
    verifyUser: async (token) => {
        const who = await verifyUser(token);
        return who === null ? null : { uid: String(who.id) };
    },
    appUserId: async (uid, token) => {
        const row = await appUserRow(uid, token);
        if (row !== null) nombres.set(uid, typeof row.name === "string" ? row.name : null);
        return row === null ? null : String(row.id);
    },
    // El nombre sale de la misma fila que appUserId (se lee una vez por petición).
    appUserNombre: (uid) => {
        const n = nombres.get(uid) ?? null;
        nombres.delete(uid);
        return Promise.resolve(n);
    },
    crearLector,
    checkHomeMember,
    runInHome: (homeId, fn) => runWithHome(homeId, fn),
    usage,
    callModel: callModel(apiKey),
    model: Deno.env.get("KITO_MODEL") || DEFAULT_MODEL,
    skills: SKILLS,
    env: (name) => Deno.env.get(name),
    now: () => new Date(),
}));
