// Edge Function `api` — espejo de las rutas de lectura del dashboard (api/src/Controllers/router.php):
// POST /user/auth, GET /event, GET /task. Auth manual (deploy --no-verify-jwt), como middlewareAuth.
//
// El pathname llega con el prefijo de montaje (…/functions/v1/api/user/auth → /api/user/auth y con
// `supabase functions serve` local puede diferir), así que se normaliza a la ruta lógica (R1-09).
//
// p_user_id se deriva server-side del JWT verificado (sub/auth_uid → app_user.id), nunca de los
// parámetros del request (R1-03). Lecturas con el JWT del usuario (RLS activa) y service_role solo
// para materialize_routines_for (como PHP escribe durante la lectura).
//
// Desviaciones documentadas (ambas deliberadas; el dashboard trata error = error, R1-08):
// * token inválido en rutas protegidas: PHP 500 {"error":"Not Found"}, aquí 401 {"error":"Unauthorized"}.
// * email inexistente en /user/auth: PHP 500 {"error":"Not Found"}, aquí 401 {"error":"Invalid credentials"}.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (body: unknown, status = 200): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const error = (message: string, status: number): Response => json({ error: message }, status);

// Router::error de PHP: InvalidArgumentException → 400; el resto → 500 con el mensaje
const rpcError = (body: unknown): Response => {
    const message = (body as { message?: string } | null)?.message ?? "Internal error";
    return error(message, message === "Invalid timezone" ? 400 : 500);
};

const ROUTES = ["user/auth", "event", "task"];

function matchRoute(pathname: string): string | null {
    const path = pathname.replace(/\/+$/, "");
    for (const route of ROUTES) {
        if (path === `/${route}` || path.endsWith(`/${route}`)) return route;
    }
    return null;
}

// getFilterBool de ModelAbstract: FILTER_VALIDATE_BOOLEAN con NULL_ON_FAILURE
function phpBool(v: string | null): boolean | null {
    if (v === null) return null;
    const s = v.toLowerCase();
    if (s === "1" || s === "true" || s === "on" || s === "yes") return true;
    if (s === "0" || s === "false" || s === "off" || s === "no" || s === "") return false;
    return null;
}

// getFilterInt: intval sobre valor truthy; 0 o no numérico = sin filtro
function phpInt(v: string | null): number | null {
    if (v === null) return null;
    const n = parseInt(v, 10);
    return n ? n : null;
}

// getFilterString: trim sobre valor truthy; vacío o '0' = sin filtro
function phpStr(v: string | null): string | null {
    if (v === null || v === "" || v === "0") return null;
    const t = v.trim();
    return t === "" ? null : t;
}

// getFilterTimestamp: epoch de 10 dígitos → 'YYYY-MM-DD HH:MM:SS' en UTC
function phpTimestamp(v: string | null): string | null {
    const s = phpStr(v);
    if (s === null || !/^\d{10}$/.test(s)) return null;
    return new Date(parseInt(s, 10) * 1000).toISOString().slice(0, 19).replace("T", " ");
}

// Routine::cutoff valida el IANA de timezone; inválido → 400 "Invalid timezone"
function validTimezone(tz: string): boolean {
    try {
        new Intl.DateTimeFormat("en-US", { timeZone: tz });
        return true;
    } catch {
        return false;
    }
}

// PostgREST serializa timestamps como ISO ('T' y microsegundos): se recorta al formato PHP
const fmt = (ts: string): string => ts.replace("T", " ").slice(0, 19);

async function appUserRow(uid: string, token: string): Promise<Record<string, unknown> | null> {
    const res = await fetch(
        `${SUPABASE_URL}/rest/v1/app_user?auth_uid=eq.${encodeURIComponent(uid)}&select=id,name,email,created_at,updated_at&limit=1`,
        { headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` } },
    );
    if (!res.ok) return null;
    const rows = await res.json();
    return rows.length ? rows[0] : null;
}

async function rpc(name: string, args: Record<string, unknown>, token: string): Promise<Response> {
    return await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
            apikey: ANON_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(args),
    });
}

// UserAuth.php: 400 sin campos; 401 credenciales inválidas (incluye email inexistente, R1-08)
async function handleAuth(req: Request): Promise<Response> {
    const body = await req.json().catch(() => null);
    const email = body && typeof body.email === "string" ? body.email.trim() : null;
    const password = body && typeof body.password === "string" ? body.password : null;
    if (!email || !password) return error("Email and password are required", 400);

    const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
    });
    if (!res.ok) return error("Invalid credentials", 401);
    const session = await res.json();

    const me = await appUserRow(session.user.id, session.access_token);
    if (me === null) return error("Not Found", 500);

    return json({
        id: me.id,
        name: me.name,
        email: me.email,
        token: session.access_token,
        created_at: fmt(me.created_at as string),
        updated_at: fmt(me.updated_at as string),
    });
}

// EventIndex.php → Event::findWithFilters: materializa rutinas y consulta con los filtros del contrato
async function handleEvent(req: Request, token: string, uid: string): Promise<Response> {
    const q = new URL(req.url).searchParams;
    const tz = q.get("timezone") ?? "UTC";
    if (!validTimezone(tz)) return error("Invalid timezone", 400);

    const me = await appUserRow(uid, token);
    if (me === null) return error("Not Found", 500);

    const mat = await fetch(`${SUPABASE_URL}/rest/v1/rpc/materialize_routines_for`, {
        method: "POST",
        headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_user_id: me.id, p_timezone: tz }),
    });
    if (!mat.ok) return rpcError(await mat.json().catch(() => null));

    const res = await rpc("get_events", {
        p_start_date: phpTimestamp(q.get("start_date")),
        p_end_date: phpTimestamp(q.get("end_date")),
        p_routine: phpBool(q.get("routine")),
        p_timezone: tz,
        p_dashboard: phpBool(q.get("dashboard")),
        p_calendar_id: phpInt(q.get("calendar_id")),
        p_person_id: phpInt(q.get("person_id")),
        p_search: phpStr(q.get("search")),
        p_limit: phpInt(q.get("limit")),
        p_offset: phpInt(q.get("offset")),
        p_order_mode: phpStr(q.get("order_mode"))?.toUpperCase() ?? "ASC",
        p_widget: phpBool(q.get("widget")),
    }, token);
    if (!res.ok) return rpcError(await res.json().catch(() => null));
    return new Response(await res.text(), { headers: { "Content-Type": "application/json" } });
}

// TaskIndex.php: check estricto de pertenencia (TaskListUser::check → "Not Found") + filtros
async function handleTask(req: Request, token: string, uid: string): Promise<Response> {
    const q = new URL(req.url).searchParams;

    const raw = q.get("task_list_id") ?? "";
    if (/^[0-9]+$/.test(raw) && parseInt(raw, 10) !== 0) {
        const chk = await fetch(
            `${SUPABASE_URL}/rest/v1/task_list_user?task_list_id=eq.${parseInt(raw, 10)}&select=id&limit=1`,
            { headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` } },
        );
        const rows = chk.ok ? await chk.json() : [];
        if (!rows.length) return error("Not Found", 500);
    }

    const res = await rpc("get_tasks", {
        p_dashboard: phpBool(q.get("dashboard")),
        p_task_list_id: phpInt(q.get("task_list_id")),
        p_widget: phpBool(q.get("widget")),
    }, token);
    if (!res.ok) return rpcError(await res.json().catch(() => null));
    return new Response(await res.text(), { headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request): Promise<Response> => {
    try {
        const route = matchRoute(new URL(req.url).pathname);
        if (route === null) return error("Not Found", 404);

        if (route === "user/auth") {
            if (req.method !== "POST") return error("Not Found", 404);
            return await handleAuth(req);
        }

        if (req.method !== "GET") return error("Not Found", 404);

        // middlewareAuth: sin Bearer → 401; token inválido → 401 (desviación documentada)
        const m = (req.headers.get("Authorization") ?? "").match(/Bearer\s+(.*)$/i);
        if (m === null) return error("Unauthorized", 401);
        const token = m[1];
        const who = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
            headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` },
        });
        if (!who.ok) return error("Unauthorized", 401);
        const { id: uid } = await who.json();

        return route === "event"
            ? await handleEvent(req, token, uid)
            : await handleTask(req, token, uid);
    } catch (e) {
        return error(e instanceof Error ? e.message : String(e), 500);
    }
});
