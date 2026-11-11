// user/auth, user/create, user/update y config (UserAuth/UserCreate/UserUpdate/Config.php).
import { fmt, inputEmail, inputString, json, contractEmpty, contractInput } from "../_shared/contract.ts";
import {
    errAuthFieldsRequired, errEmailExists, errInvalidCredentials, errNameLength, errNotAllowed,
    errPasswordLength, errNotFound500, errProfileFieldsRequired, errUserFieldsRequired, error, rpcPass,
} from "../_shared/errors.ts";
import { appUserRow, passwordGrant, rpc, signup, updateAuthUser } from "../_shared/supabase.ts";

// Config::key('public','allow_registration') → env ALLOW_REGISTRATION (default false, Q3)
export const allowRegistration = (): boolean =>
    (Deno.env.get("ALLOW_REGISTRATION") ?? "false").toLowerCase() === "true";

// mb_strlen de PHP (UserCreate.php:24,28 / UserUpdate.php:17,21): codepoints UTF-8, no unidades
// UTF-16 de String.length (un nombre de 30 emojis son 30 caracteres para ambos, R1-04)
const mbLen = (s: string): number => [...s].length;

// GET /config (Config.php): objeto de la config pública
export const handleConfig = (): Response => json({ allow_registration: allowRegistration() });

// POST /user/auth (UserAuth.php): 400 sin campos; 401 credenciales inválidas (incluye email
// inexistente, R1-08). + refresh_token aditivo (solo aquí, §4).
export const handleUserAuth = async (req: Request): Promise<Response> => {
    const input = await contractInput(req);
    const email = inputEmail(input, "email");
    const password = inputString(input, "password");
    if (contractEmpty(email) || contractEmpty(password)) return errAuthFieldsRequired();

    const res = await passwordGrant(email as string, password as string);
    if (!res.ok) return errInvalidCredentials();
    const session = await res.json();

    const me = await appUserRow(session.user.id, session.access_token);
    if (me === null) return errNotFound500();

    return json({
        id: me.id,
        name: me.name,
        email: me.email,
        token: session.access_token,
        refresh_token: session.refresh_token,
        created_at: fmt(me.created_at as string),
        updated_at: fmt(me.updated_at as string),
    });
};

// POST /user/create (UserCreate.php): flag → validaciones → alta GoTrue (trigger 0004 crea
// app_user). Q4: confirmación de email desactivada; si GoTrue no devuelve sesión → error explícito.
export const handleUserCreate = async (req: Request): Promise<Response> => {
    if (!allowRegistration()) return errNotAllowed(); // UserCreate.php:13 (verbatim)

    const input = await contractInput(req);
    const name = inputString(input, "name");
    const email = inputEmail(input, "email");
    const password = inputString(input, "password");
    if (contractEmpty(name) || contractEmpty(email) || contractEmpty(password)) return errUserFieldsRequired();
    if (mbLen(name as string) < 3 || mbLen(name as string) > 50) return errNameLength();
    if (mbLen(password as string) < 8) return errPasswordLength();

    const res = await signup(name as string, email as string, password as string);
    if (!res.ok) {
        const body = await res.json().catch(() => null) as { msg?: string; message?: string } | null;
        const msg = String(body?.msg ?? body?.message ?? "");
        if (/already/i.test(msg)) return errEmailExists(); // UserCreate.php:33
        // Desviación: GoTrue valida el formato del email; PHP aceptaba cualquier string
        return error(msg || "Internal error", 400);
    }
    const session = await res.json();
    if (!session.access_token) return error("Email confirmation is pending", 400);
    const me = await appUserRow(session.user.id, session.access_token);
    if (me === null) return errNotFound500();

    return json({
        id: me.id,
        name: me.name,
        email: me.email,
        token: session.access_token,
        created_at: fmt(me.created_at as string),
        updated_at: fmt(me.updated_at as string),
    }, 201);
};

// PATCH /user/update (UserUpdate.php + User.php:157-196): GoTrue PUT /auth/v1/user con el JWT del
// usuario; app_user lo sincroniza el trigger 0010. La respuesta es la forma PHP de user/update
// (get_user_me, sin token). Cambio de email efectivo tras confirmación GoTrue (Q9).
export const handleUserUpdate = async (req: Request, token: string, uid: string): Promise<Response> => {
    const input = await contractInput(req);
    const me = await appUserRow(uid, token);
    if (me === null) return errNotFound500();

    const name = inputString(input, "name", me.name as string);
    const email = inputEmail(input, "email", me.email as string);
    const password = inputString(input, "password");
    if (contractEmpty(name) || contractEmpty(email)) return errProfileFieldsRequired();
    if (mbLen(name as string) < 3 || mbLen(name as string) > 50) return errNameLength();
    if (password && mbLen(password) < 8) return errPasswordLength();

    const body: Record<string, unknown> = { data: { name } };
    if (email !== me.email) body.email = email;
    if (password) body.password = password;
    const res = await updateAuthUser(token, body);
    if (!res.ok) {
        const b = await res.json().catch(() => null) as { msg?: string; message?: string } | null;
        return error(String(b?.msg ?? b?.message ?? "Internal error"), 500);
    }
    return rpcPass(await rpc("get_user_me", {}, token));
};
