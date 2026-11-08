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
//
// Layout: entrypoint fino (routing + guard Bearer + dispatch) + usecases/{auth,events,tasks}.ts +
// _shared/{supabase,contract,errors}.ts; imports relativos empaquetados por el deploy (sin build step).

import { error, errRouteNotFound, errUnauthorized } from "./_shared/errors.ts";
import { verifyUser } from "./_shared/supabase.ts";
import { handleAuth } from "./usecases/auth.ts";
import { handleEvent } from "./usecases/events.ts";
import { handleTask } from "./usecases/tasks.ts";

const ROUTES = ["user/auth", "event", "task"];

function matchRoute(pathname: string): string | null {
    const path = pathname.replace(/\/+$/, "");
    for (const route of ROUTES) {
        if (path === `/${route}` || path.endsWith(`/${route}`)) return route;
    }
    return null;
}

Deno.serve(async (req: Request): Promise<Response> => {
    try {
        const route = matchRoute(new URL(req.url).pathname);
        if (route === null) return errRouteNotFound();

        if (route === "user/auth") {
            if (req.method !== "POST") return errRouteNotFound();
            return await handleAuth(req);
        }

        if (req.method !== "GET") return errRouteNotFound();

        // middlewareAuth: sin Bearer → 401; token inválido → 401 (desviación documentada)
        const m = (req.headers.get("Authorization") ?? "").match(/Bearer\s+(.*)$/i);
        if (m === null) return errUnauthorized();
        const token = m[1];
        const who = await verifyUser(token);
        if (who === null) return errUnauthorized();
        const uid = who.id as string;

        return route === "event"
            ? await handleEvent(req, token, uid)
            : await handleTask(req, token, uid);
    } catch (e) {
        return error(e instanceof Error ? e.message : String(e), 500);
    }
});
