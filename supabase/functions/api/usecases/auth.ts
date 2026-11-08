import { fmt, json } from "../_shared/contract.ts";
import { errAuthFieldsRequired, errInvalidCredentials, errPhpNotFound } from "../_shared/errors.ts";
import { appUserRow, passwordGrant } from "../_shared/supabase.ts";

// UserAuth.php: 400 sin campos; 401 credenciales inválidas (incluye email inexistente, R1-08)
export const handleAuth = async (req: Request): Promise<Response> => {
    const body = await req.json().catch(() => null);
    const email = body && typeof body.email === "string" ? body.email.trim() : null;
    const password = body && typeof body.password === "string" ? body.password : null;
    if (!email || !password) return errAuthFieldsRequired();

    const res = await passwordGrant(email, password);
    if (!res.ok) return errInvalidCredentials();
    const session = await res.json();

    const me = await appUserRow(session.user.id, session.access_token);
    if (me === null) return errPhpNotFound();

    return json({
        id: me.id,
        name: me.name,
        email: me.email,
        token: session.access_token,
        created_at: fmt(me.created_at as string),
        updated_at: fmt(me.updated_at as string),
    });
};
