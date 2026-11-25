// handler.ts — Lógica de la Edge Function `asistente` (change kito-asistente). Sin efectos al importar:
// auth, hogar, BD de uso, modelo y entorno se inyectan (index.ts hace el cableado; los tests usan falsos).
//
// Orden (cada paso corta si falla):
//   1. POST → si no, 405. 2. Bearer + verifyUser → 401. 3. X-Home-Id válido y membresía → 400 / 404.
//   4. Body {messages, timezone} validado (≤20 mensajes, ≤2000 caracteres, último de usuario) → 400.
//   5. Modelo configurado (ANTHROPIC_API_KEY) → 500 sin consumir (falla cerrada).
//   6. Usuario de app (app_user) → 404. 7. Límite diario: consume antes de llamar al modelo → 429 sin llamar.
//   8. Bucle con el modelo dentro del hogar activo. Fallo del modelo → refund del mensaje y 502.
//   9. Tokens sumados (assistant_record_usage) → 200 {texto, tarjetas, cambios, uso}. Un `refusal` del modelo devuelve el mensaje.
// Logs: solo operación y estado; nunca texto de usuario, tokens de sesión ni cabeceras.

import { confirmar } from "./skills/organizar/confirmar.ts";
import { secretoDe } from "./skills/organizar/confirmacion.ts";
import { CallModel, Escribir, Leer, ModelError, MAX_CHARS, MAX_HISTORY, Mensaje, runKito, Skill, Tokens } from "./core.ts";

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
    /** Nombre del usuario (para la ficha de contexto); opcional. */
    appUserNombre?(uid: string, token: string): Promise<string | null>;
    /** Crea el lector del api para esta petición; sin él, las herramientas de datos no funcionan. */
    crearLector?(token: string, uid: string, timezone: string): Leer;
    /** Crea el escritor del api (skill `organizar`); sin él, las herramientas de escritura no funcionan. */
    crearEscritor?(token: string, uid: string, timezone: string, homeId: string): Escribir;
    checkHomeMember(homeId: string, token: string): Promise<boolean>;
    /** Ejecuta fn con el hogar activo en el contexto (null = sin hogar). */
    runInHome<T>(homeId: string | null, fn: () => Promise<T>): Promise<T>;
    usage: UsageDb;
    /** Modelo: se llama solo si la configuración existe. */
    callModel: CallModel;
    model: string;
    /** low | medium | high; por defecto low (ver `resolverEffort` en core.ts). */
    effort?: string;
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

/** Resultado de autenticar: sesión, usuario y hogar activo ya comprobados. */
export interface Autenticado {
    token: string;
    who: { uid: string };
    homeId: string;
}

/**
 * Tramo común de Kito y de /confirmar, en este orden: 405 si no es POST, 401 sin Bearer válido, 400 si
 * X-Home-Id no es válido y 404 si el usuario no es miembro del hogar.
 */
export const autenticar = async (req: Request, deps: HandlerDeps): Promise<Autenticado | Response> => {
    if (req.method !== "POST") return json(405, { error: "Método no permitido" });
    const token = bearer(req);
    if (token === null) return json(401, { error: "No autorizado" });
    const who = await deps.verifyUser(token);
    if (who === null) return json(401, { error: "No autorizado" });
    // Hogar activo: obligatorio (las consultas y las acciones son del hogar).
    const hogarRaw = req.headers.get("X-Home-Id") ?? "";
    if (!HOME_RE.test(hogarRaw)) return json(400, { error: "Cabecera X-Home-Id no válida" });
    const homeId = BigInt(hogarRaw).toString();
    if (!(await deps.checkHomeMember(homeId, token))) return json(404, { error: "Hogar no encontrado" });
    return { token, who, homeId };
};

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
    const log = deps.log ?? ((m: string) => console.error(m));

    return async (req: Request): Promise<Response> => {
        try {
            // 1-3. Método, sesión y hogar activo (común a Kito y a /confirmar).
            const auth = await autenticar(req, deps);
            if (auth instanceof Response) return auth;
            const { token, who, homeId } = auth;

            // POST /asistente/confirmar: ejecuta lo que firmó una tarjeta; sin modelo ni cupo.
            if (new URL(req.url).pathname.endsWith("/confirmar")) return await confirmar(req, deps, auth, log);

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

            const nombreUsuario = (await deps.appUserNombre?.(who.uid, token).catch(() => null)) ?? undefined;

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
                        ctx: {
                            token, uid: who.uid, homeId, timezone: parsed.timezone, now: deps.now(),
                            appUserId, nombreUsuario, leer: deps.crearLector?.(token, who.uid, parsed.timezone),
                            escribir: deps.crearEscritor?.(token, who.uid, parsed.timezone, homeId),
                            secretoConfirmacion: secretoDe((k) => deps.env(k)),
                        },
                        skills: deps.skills,
                        callModel: deps.callModel,
                        model: deps.model,
                        effort: deps.effort,
                        env: deps.env,
                    }));

                // 9. Tokens (si falla, la respuesta ya es válida: solo se registra).
                try {
                    // `sinCoste` (refusal, Q10): se suman los tokens pero el mensaje no cuenta para el cupo.
                    await deps.usage.record(appUserId, uso.day, res.tokens, res.sinCoste === true);
                } catch {
                    log("asistente: no se pudieron registrar los tokens");
                }
                return json(200, {
                    texto: res.texto,
                    tarjetas: res.tarjetas,
                    cambios: res.cambios,
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
