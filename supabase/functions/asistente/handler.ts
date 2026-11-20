// handler.ts — Lógica de la Edge Function `asistente` (change kito-asistente). Sin efectos al importar:
// auth, hogar, BD de uso, modelo y entorno se inyectan (index.ts hace el cableado; los tests usan falsos).
//
// Orden (cada paso corta si falla):
//   1. POST → si no, 405. 2. Bearer + verifyUser → 401. 3. X-Home-Id válido y membresía → 400 / 404.
//   4. Body {messages, timezone} validado (≤20 mensajes, ≤2000 caracteres, último de usuario) → 400.
//   5. Modelo configurado (ANTHROPIC_API_KEY) → 500 sin consumir (falla cerrada).
//   6. Usuario de app (app_user) → 404. 7. Límite diario: consume antes de llamar al modelo → 429 sin llamar.
//   8. Bucle con el modelo dentro del hogar activo. Fallo del modelo → refund del mensaje y 502.
//   9. Tokens sumados (assistant_record_usage) → 200 {texto, tarjetas, uso}.
// Logs: solo operación y estado; nunca texto de usuario, tokens de sesión ni cabeceras.

import { CallModel, ModelError, MAX_CHARS, MAX_HISTORY, Mensaje, runKito, Skill, Tokens } from "./core.ts";

export interface UsoResultado {
    allowed: boolean;
    used: number;
    limit: number;
    day: string;
}

export interface UsageDb {
    consume(appUserId: string, timezone: string): Promise<UsoResultado>;
    record(appUserId: string, day: string, tokens: Tokens, refund: boolean): Promise<void>;
}

export interface HandlerDeps {
    /** Devuelve el uid del JWT o null si el token no es válido. */
    verifyUser(token: string): Promise<{ uid: string } | null>;
    /** app_user.id del uid, o null si no existe. */
    appUserId(uid: string, token: string): Promise<string | null>;
    checkHomeMember(homeId: string, token: string): Promise<boolean>;
    /** Ejecuta fn con el hogar activo en el contexto (null = sin hogar). */
    runInHome<T>(homeId: string | null, fn: () => Promise<T>): Promise<T>;
    usage: UsageDb;
    /** Modelo: se llama solo si la configuración existe. */
    callModel: CallModel;
    model: string;
    skills: Skill[];
    env(name: string): string | undefined;
    now(): Date;
    log?: (msg: string) => void;
}

const json = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });

const HOME_RE = /^[0-9]{1,18}$/;

export const validTimezone = (tz: unknown): tz is string => {
    if (typeof tz !== "string" || tz === "") return false;
    try {
        new Intl.DateTimeFormat("en-US", { timeZone: tz });
        return true;
    } catch {
        return false;
    }
};

/** Valida el body. Devuelve la lista de mensajes o un error legible para el cliente. */
export const parseBody = (raw: unknown): { mensajes: Mensaje[]; timezone: string } | string => {
    if (typeof raw !== "object" || raw === null) return "El cuerpo debe ser un objeto JSON";
    const { messages, timezone } = raw as { messages?: unknown; timezone?: unknown };
    if (!validTimezone(timezone)) return "Zona horaria no válida";
    if (!Array.isArray(messages) || messages.length === 0) return "Falta messages";
    if (messages.length > MAX_HISTORY) return `Como máximo ${MAX_HISTORY} mensajes`;
    const mensajes: Mensaje[] = [];
    for (const m of messages) {
        if (typeof m !== "object" || m === null) return "Mensaje no válido";
        const { role, content } = m as { role?: unknown; content?: unknown };
        if (role !== "user" && role !== "assistant") return "Rol no válido";
        if (typeof content !== "string" || content.trim() === "") return "Mensaje vacío";
        if (content.length > MAX_CHARS) return `Cada mensaje admite como máximo ${MAX_CHARS} caracteres`;
        mensajes.push({ role, content });
    }
    if (mensajes[mensajes.length - 1].role !== "user") return "El último mensaje debe ser del usuario";
    return { mensajes, timezone };
};

const bearer = (req: Request): string | null => {
    const m = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i);
    return m ? m[1] : null;
};

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
    const log = deps.log ?? ((m: string) => console.error(m));

    return async (req: Request): Promise<Response> => {
        try {
            // 1. Método.
            if (req.method !== "POST") return json(405, { error: "Método no permitido" });

            // 2. Sesión.
            const token = bearer(req);
            if (token === null) return json(401, { error: "No autorizado" });
            const who = await deps.verifyUser(token);
            if (who === null) return json(401, { error: "No autorizado" });

            // 3. Hogar activo: obligatorio para Kito (las consultas son del hogar).
            const hogarRaw = req.headers.get("X-Home-Id") ?? "";
            if (!HOME_RE.test(hogarRaw)) return json(400, { error: "Cabecera X-Home-Id no válida" });
            const homeId = BigInt(hogarRaw).toString();
            if (!(await deps.checkHomeMember(homeId, token))) return json(404, { error: "Hogar no encontrado" });

            // 4. Body.
            let raw: unknown;
            try {
                raw = await req.json();
            } catch {
                return json(400, { error: "El cuerpo no es JSON válido" });
            }
            const parsed = parseBody(raw);
            if (typeof parsed === "string") return json(400, { error: parsed });

            // 5. Configuración del modelo: falla cerrada antes de tocar el contador.
            if ((deps.env("ANTHROPIC_API_KEY") ?? "") === "") {
                log("asistente: ANTHROPIC_API_KEY no configurada");
                return json(500, { error: "Kito no está configurado en el servidor" });
            }

            // 6. Usuario de app.
            const appUserId = await deps.appUserId(who.uid, token);
            if (appUserId === null) return json(404, { error: "Usuario no encontrado" });

            // 7. Límite diario, antes de llamar al modelo.
            const uso = await deps.usage.consume(appUserId, parsed.timezone);
            if (!uso.allowed) {
                return json(429, {
                    error: "Límite diario alcanzado",
                    texto: `Has llegado a ${uso.limit} mensajes hoy. Podrás volver a escribirme mañana.`,
                    uso: { usados: uso.used, limite: uso.limit },
                });
            }

            // 8. Bucle con el modelo dentro del hogar activo.
            try {
                const res = await deps.runInHome(homeId, () =>
                    runKito({
                        mensajes: parsed.mensajes,
                        ctx: { token, uid: who.uid, homeId, timezone: parsed.timezone, now: deps.now() },
                        skills: deps.skills,
                        callModel: deps.callModel,
                        model: deps.model,
                    }));

                // 9. Tokens (si falla, la respuesta ya es válida: solo se registra).
                try {
                    await deps.usage.record(appUserId, uso.day, res.tokens, false);
                } catch {
                    log("asistente: no se pudieron registrar los tokens");
                }
                return json(200, {
                    texto: res.texto,
                    tarjetas: res.tarjetas,
                    uso: { usados: uso.used, limite: uso.limit },
                });
            } catch (e) {
                // Fallo del modelo: el mensaje no cuenta para el tope.
                try {
                    await deps.usage.record(appUserId, uso.day, { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, true);
                } catch {
                    log("asistente: no se pudo devolver el mensaje tras fallo del modelo");
                }
                const tipo = e instanceof ModelError ? "modelo" : "interno";
                log(`asistente: fallo ${tipo}`);
                return json(502, { error: "Kito no puede responder ahora", texto: "Kito no puede responder ahora. Inténtalo de nuevo en un momento." });
            }
        } catch (e) {
            log(`asistente: error inesperado (${e instanceof Error ? e.name : "desconocido"})`);
            return json(500, { error: "Error interno" });
        }
    };
}
