// Verificador de tokens del MCP: acepta SOLO tokens OAuth de Supabase Auth emitidos a un cliente (Claude).
// Un JWT de sesión de la app (password grant) no sirve: no lleva `client_id`.
//
// Independiente de `api/_shared/supabase.ts` (la verificación de usuario de `api` no se toca ni se usa aquí). Pasos:
//  1. Se lee el payload sin verificar la firma y se exigen `aud` (la esperada) y `client_id` (cadena no vacía).
//     Solo sirve para descartar rápido: nada de lo leído se da por bueno todavía.
//  2. `GET /auth/v1/user` con el Bearer: es Supabase Auth quien valida firma, caducidad y sesión, y devuelve el id.
//  3. `sub` del token == `id` de Auth.
// Nunca se loguea el token ni el payload.

/** Audiencia que llevan los tokens de Supabase Auth (también los OAuth). Se puede cambiar con MCP_TOKEN_AUDIENCE. */
export const AUDIENCIA_POR_DEFECTO = "authenticated";

/** Supabase Auth no ha podido responder (5xx, 429 o fallo de red): no se sabe si el token es válido. */
export class AuthNoDisponible extends Error {}

export interface TokenOAuth {
    uid: string;
    clientId: string;
}

/** Pregunta a Supabase Auth por el usuario del token; `null` si Auth lo rechaza (token inválido). Lanza si no responde. */
export type UserInfo = (token: string) => Promise<{ id: string } | null>;

export interface AuthDeps {
    userInfo: UserInfo;
    audience: string;
}

const payloadDe = (token: string): Record<string, unknown> | null => {
    const partes = token.split(".");
    if (partes.length !== 3) return null;
    try {
        const b64 = partes[1].replace(/-/g, "+").replace(/_/g, "/");
        const json = new TextDecoder().decode(Uint8Array.from(atob(b64.padEnd(Math.ceil(b64.length / 4) * 4, "=")), (c) => c.charCodeAt(0)));
        const o = JSON.parse(json);
        return o !== null && typeof o === "object" && !Array.isArray(o) ? o as Record<string, unknown> : null;
    } catch {
        return null;
    }
};

const audienciaOk = (aud: unknown, esperada: string): boolean =>
    typeof aud === "string" ? aud === esperada : Array.isArray(aud) && aud.includes(esperada);

/** `{uid, clientId}` si el token es un token OAuth válido para el MCP; `null` si no lo es. Lanza `AuthNoDisponible` si Auth no responde. */
export const verificarToken = async (token: string, deps: AuthDeps): Promise<TokenOAuth | null> => {
    const claims = payloadDe(token);
    if (claims === null) return null;
    if (!audienciaOk(claims.aud, deps.audience)) return null;
    const clientId = claims.client_id;
    if (typeof clientId !== "string" || clientId.trim() === "") return null;
    const sub = claims.sub;
    if (typeof sub !== "string" || sub === "") return null;
    let quien: { id: string } | null;
    try {
        quien = await deps.userInfo(token);
    } catch {
        throw new AuthNoDisponible("auth no disponible");
    }
    if (quien === null || typeof quien.id !== "string" || quien.id !== sub) return null;
    return { uid: sub, clientId };
};

/** Token del `Authorization: Bearer …`, o `null`. */
export const bearerDe = (req: Request): string | null => {
    const m = /^Bearer\s+(\S+)\s*$/i.exec(req.headers.get("Authorization") ?? "");
    return m ? m[1] : null;
};
