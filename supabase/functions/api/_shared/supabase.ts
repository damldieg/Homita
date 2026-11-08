// Clientes HTTP a Supabase (env con nombres intactos; lecturas con el JWT del usuario, RLS activa).
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export const passwordGrant = (email: string, password: string): Promise<Response> =>
    fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
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

export const rpc = async (name: string, args: Record<string, unknown>, token: string): Promise<Response> => {
    return await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
            apikey: ANON_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
        },
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
