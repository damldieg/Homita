// Clientes HTTP a Supabase (env con nombres intactos; lecturas con el JWT del usuario, RLS activa).
import { currentHome } from "./home.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Contexto X-Home-Id (§2.2/S10): la cabecera solo viaja si hay hogar activo en la petición
const homeHeaders = (): Record<string, string> =>
    currentHome() === null ? {} : { "X-Home-Id": currentHome() as string };

export const passwordGrant = (email: string, password: string): Promise<Response> =>
    fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
    });

// User::create (alta): GoTrue signup con anon key; el trigger on_auth_user_created crea app_user
// 0027: con invitationPending viaja solo un marcador booleano (nunca el código en claro, R2-03)
// y el trigger no crea hogar personal.
export const signup = (
    name: string, email: string, password: string, invitationPending = false,
): Promise<Response> =>
    fetch(`${SUPABASE_URL}/auth/v1/signup`, {
        method: "POST",
        headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, data: invitationPending ? { name, invitation_pending: true } : { name } }),
    });

// User::update (perfil): PUT /auth/v1/user con el JWT del usuario (Q8/Q9); app_user lo sincroniza
// el trigger on_auth_user_updated (0010)
export const updateAuthUser = (token: string, body: Record<string, unknown>): Promise<Response> =>
    fetch(`${SUPABASE_URL}/auth/v1/user`, {
        method: "PUT",
        headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
    });

export const verifyUser = async (token: string): Promise<Record<string, unknown> | null> => {
    const who = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` },
    });
    if (!who.ok) return null;
    return await who.json();
};

export const appUserRow = async (uid: string, token: string): Promise<Record<string, unknown> | null> => {
    const res = await fetch(
        `${SUPABASE_URL}/rest/v1/app_user?auth_uid=eq.${encodeURIComponent(uid)}&select=id,name,email,created_at,updated_at&limit=1`,
        { headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` } },
    );
    if (!res.ok) return null;
    const rows = await res.json();
    return rows.length ? rows[0] : null;
};

// SELECT puntual sobre una tabla (RLS activa): [] si no visible (PHP → 500 Not Found)
export const selectRows = async (
    table: string,
    query: string,
    token: string,
): Promise<Record<string, unknown>[]> => {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, {
        headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}`, ...homeHeaders() },
    });
    if (!res.ok) return [];
    return await res.json();
};

export const rpc = async (name: string, args: Record<string, unknown>, token: string): Promise<Response> => {
    return await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
            apikey: ANON_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
            ...homeHeaders(),
        },
        body: JSON.stringify(args),
    });
};

// RPC pública (sin sesión, rol anon): solo para funciones con GRANT a anon (0026, registro con
// código). No envía cabeceras de hogar.
export const rpcAnon = async (name: string, args: Record<string, unknown>): Promise<Response> => {
    return await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify(args),
    });
};

// service_role solo para materialize_routines_for (como PHP escribe durante la lectura)
export const materializeRoutines = async (userId: unknown, timezone: string): Promise<Response> => {
    return await fetch(`${SUPABASE_URL}/rest/v1/rpc/materialize_routines_for`, {
        method: "POST",
        headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
            ...homeHeaders(),
        },
        body: JSON.stringify({ p_user_id: userId, p_timezone: timezone }),
    });
};

// TaskListUser::check: !ok o 0 filas = sin acceso
export const hasTaskListAccess = async (token: string, taskListId: number): Promise<boolean> => {
    const chk = await fetch(
        `${SUPABASE_URL}/rest/v1/task_list_user?task_list_id=eq.${taskListId}&select=id&limit=1`,
        { headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` } },
    );
    const rows = chk.ok ? await chk.json() : [];
    return rows.length > 0;
};
