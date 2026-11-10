// Edge Function `api` — contrato (a) PHP-compat de las 43 rutas legacy del backend (D-008;
// inventario: .dorch/archive/control-api/contract-inventory.md) + las 9 rutas /home/* de 1.4/1.5
// (diseño §5.2, flag `home: true` en ROUTES; 1.5 añade /home/member/*).
// Auth manual (deploy --no-verify-jwt), como middlewareAuth. user/auth, user/create y config son
// públicas; el resto exige Bearer (token inválido → 401, desviación documentada).
//
// Routing EXACTO por tabla {metodo, ruta} (sin endsWith: `user` vs `calendar/user` etc. eran
// frágiles con 43 rutas). El pathname llega con el prefijo de montaje (…/functions/v1/api/user/auth
// → /api/user/auth y con `supabase functions serve` local puede diferir), así que se normaliza a la
// ruta lógica antes de mirar en la tabla.
//
// Contexto de hogar (X-Home-Id, §2.2): en rutas autenticadas la cabecera opcional se valida
// (400 Invalid home), se comprueba la membresía (500 Not Found en legacy / 404 en /home/*) y se
// fija en un AsyncLocalStorage para que el transporte la propague a PostgREST (S10). Sin cabecera,
// cero coste y respuestas idénticas a las de antes de 1.4.
//
// p_user_id se deriva server-side del JWT verificado (sub/auth_uid → app_user.id), nunca de los
// parámetros del request (R1-03). Lecturas con el JWT del usuario (RLS activa) y service_role solo
// para materialize_routines_for (lecturas); las escrituras materializan dentro de sus RPC
// (0006/0007) sin service_role.
//
// Desviaciones documentadas (contract-inventory.md §Desviaciones): token inválido 401 vs 500 PHP;
// email inexistente en /user/auth 401 vs 500 PHP; owner-only 403 {"error":"Not Allowed"} (Q5);
// event/create solo text → 400 (Gemini diferido, T14); refresh_token aditivo en /user/auth;
// config flag desde ALLOW_REGISTRATION (default false).
//
// Layout: entrypoint fino (routing + guard Bearer + dispatch) + usecases/{auth,calendars,persons,
// routines,events,task-lists,tasks}.ts + _shared/{supabase,contract,errors,validate}.ts.

import { error, errInvalidHome, errPhpNotFound, errRouteHomeNotFound, errRouteNotFound, errUnauthorized } from "./_shared/errors.ts";
import { checkHomeMember, parseHomeHeader, runWithHome } from "./_shared/home.ts";
import { verifyUser } from "./_shared/supabase.ts";
import {
    handleConfig, handleUserAuth, handleUserCreate, handleUserUpdate,
} from "./usecases/auth.ts";
import {
    handleCalendarCreate, handleCalendarDelete, handleCalendarDetail, handleCalendarIndex,
    handleCalendarUpdate, handleCalendarUserCreate, handleCalendarUserDelete, handleCalendarUserIndex,
} from "./usecases/calendars.ts";
import { handlePersonCreate, handlePersonDelete, handlePersonIndex, handlePersonUpdate } from "./usecases/persons.ts";
import {
    handleRoutineAlarm, handleRoutineCreate, handleRoutineDelete, handleRoutineDetail,
    handleRoutineIndex, handleRoutineUpdate,
} from "./usecases/routines.ts";
import {
    handleEvent, handleEventAlarm, handleEventCreate, handleEventDelete, handleEventDetail,
    handleEventUpdate,
} from "./usecases/events.ts";
import {
    handleTaskListCreate, handleTaskListDelete, handleTaskListDetail, handleTaskListIndex,
    handleTaskListUpdate, handleTaskListUserCreate, handleTaskListUserDelete, handleTaskListUserIndex,
} from "./usecases/task-lists.ts";
import {
    handleTask, handleTaskComplete, handleTaskCreate, handleTaskDelete, handleTaskDetail,
    handleTaskOrder, handleTaskUpdate,
} from "./usecases/tasks.ts";
import {
    handleHomeCreate, handleHomeDefault, handleHomeDetail, handleHomeIndex, handleHomeMemberCreate,
    handleHomeMemberIndex, handleHomeMemberUpdate, handleHomeMembership, handleHomeMembershipRemove,
    handleHomeMembershipRole, handleHomeMembershipTransfer, handleHomeUpdate,
} from "./usecases/homes.ts";

type Handler = (req: Request, token: string, uid: string) => Promise<Response> | Response;

// `home: true` (rutas /home/*, 1.4): el "no miembro" del contexto X-Home-Id se mapea a 404
// (D16) en vez del 500 legacy (errPhpNotFound).
const ROUTES: Record<string, { auth: boolean; home?: boolean; handler: Handler }> = {
    "GET /config": { auth: false, handler: () => handleConfig() },
    "POST /user/create": { auth: false, handler: (req) => handleUserCreate(req) },
    "POST /user/auth": { auth: false, handler: (req) => handleUserAuth(req) },
    "PATCH /user/update": { auth: true, handler: (req, t, u) => handleUserUpdate(req, t, u) },

    "GET /calendar": { auth: true, handler: (req, t) => handleCalendarIndex(req, t) },
    "GET /calendar/detail": { auth: true, handler: (req, t) => handleCalendarDetail(req, t) },
    "POST /calendar/create": { auth: true, handler: (req, t) => handleCalendarCreate(req, t) },
    "PATCH /calendar/update": { auth: true, handler: (req, t) => handleCalendarUpdate(req, t) },
    "DELETE /calendar/delete": { auth: true, handler: (req, t) => handleCalendarDelete(req, t) },
    "GET /calendar/user": { auth: true, handler: (req, t) => handleCalendarUserIndex(req, t) },
    "POST /calendar/user": { auth: true, handler: (req, t) => handleCalendarUserCreate(req, t) },
    "DELETE /calendar/user": { auth: true, handler: (req, t) => handleCalendarUserDelete(req, t) },

    "GET /person": { auth: true, handler: (req, t) => handlePersonIndex(req, t) },
    "POST /person/create": { auth: true, handler: (req, t) => handlePersonCreate(req, t) },
    "PATCH /person/update": { auth: true, handler: (req, t) => handlePersonUpdate(req, t) },
    "DELETE /person/delete": { auth: true, handler: (req, t) => handlePersonDelete(req, t) },

    "GET /routine": { auth: true, handler: (req, t, u) => handleRoutineIndex(req, t, u) },
    "GET /routine/detail": { auth: true, handler: (req, t, u) => handleRoutineDetail(req, t, u) },
    "POST /routine/create": { auth: true, handler: (req, t) => handleRoutineCreate(req, t) },
    "PATCH /routine/update": { auth: true, handler: (req, t) => handleRoutineUpdate(req, t) },
    "PATCH /routine/alarm": { auth: true, handler: (req, t) => handleRoutineAlarm(req, t) },
    "DELETE /routine/delete": { auth: true, handler: (req, t) => handleRoutineDelete(req, t) },

    "GET /event": { auth: true, handler: (req, t, u) => handleEvent(req, t, u) },
    "GET /event/detail": { auth: true, handler: (req, t, u) => handleEventDetail(req, t, u) },
    "POST /event/create": { auth: true, handler: (req, t) => handleEventCreate(req, t) },
    "PATCH /event/update": { auth: true, handler: (req, t) => handleEventUpdate(req, t) },
    "DELETE /event/delete": { auth: true, handler: (req, t) => handleEventDelete(req, t) },
    "PATCH /event/alarm": { auth: true, handler: (req, t) => handleEventAlarm(req, t) },

    "GET /task-list": { auth: true, handler: (req, t) => handleTaskListIndex(req, t) },
    "GET /task-list/detail": { auth: true, handler: (req, t) => handleTaskListDetail(req, t) },
    "POST /task-list/create": { auth: true, handler: (req, t) => handleTaskListCreate(req, t) },
    "PATCH /task-list/update": { auth: true, handler: (req, t) => handleTaskListUpdate(req, t) },
    "DELETE /task-list/delete": { auth: true, handler: (req, t) => handleTaskListDelete(req, t) },
    "GET /task-list/user": { auth: true, handler: (req, t) => handleTaskListUserIndex(req, t) },
    "POST /task-list/user": { auth: true, handler: (req, t) => handleTaskListUserCreate(req, t) },
    "DELETE /task-list/user": { auth: true, handler: (req, t) => handleTaskListUserDelete(req, t) },

    "GET /task": { auth: true, handler: (req, t) => handleTask(req, t) },
    "GET /task/detail": { auth: true, handler: (req, t) => handleTaskDetail(req, t) },
    "POST /task/create": { auth: true, handler: (req, t) => handleTaskCreate(req, t) },
    "PATCH /task/update": { auth: true, handler: (req, t) => handleTaskUpdate(req, t) },
    "PATCH /task/complete": { auth: true, handler: (req, t) => handleTaskComplete(req, t) },
    "PATCH /task/order": { auth: true, handler: (req, t) => handleTaskOrder(req, t) },
    "DELETE /task/delete": { auth: true, handler: (req, t) => handleTaskDelete(req, t) },

    "GET /home": { auth: true, home: true, handler: (req, t) => handleHomeIndex(req, t) },
    "POST /home/create": { auth: true, home: true, handler: (req, t) => handleHomeCreate(req, t) },
    "GET /home/detail": { auth: true, home: true, handler: (req, t) => handleHomeDetail(req, t) },
    "PATCH /home/update": { auth: true, home: true, handler: (req, t) => handleHomeUpdate(req, t) },
    "PATCH /home/default": { auth: true, home: true, handler: (req, t) => handleHomeDefault(req, t) },
    "GET /home/membership": { auth: true, home: true, handler: (req, t) => handleHomeMembership(req, t) },
    "PATCH /home/membership/role": { auth: true, home: true, handler: (req, t) => handleHomeMembershipRole(req, t) },
    "POST /home/membership/transfer": { auth: true, home: true, handler: (req, t) => handleHomeMembershipTransfer(req, t) },
    "DELETE /home/membership": { auth: true, home: true, handler: (req, t) => handleHomeMembershipRemove(req, t) },
    "GET /home/member": { auth: true, home: true, handler: (req, t) => handleHomeMemberIndex(req, t) },
    "POST /home/member/create": { auth: true, home: true, handler: (req, t) => handleHomeMemberCreate(req, t) },
    "PATCH /home/member/update": { auth: true, home: true, handler: (req, t) => handleHomeMemberUpdate(req, t) },
};

// Ruta lógica sin el prefijo de montaje (…/functions/v1/api/… o …/api/…) — sin endsWith
function logicalPath(pathname: string): string {
    let p = pathname.replace(/\/+$/, "");
    const i = p.indexOf("/functions/v1");
    if (i >= 0) p = p.slice(i + "/functions/v1".length);
    const segs = p.split("/").filter(Boolean);
    if (segs[0] === "api") segs.shift();
    return "/" + segs.join("/");
}

Deno.serve(async (req: Request): Promise<Response> => {
    try {
        const route = ROUTES[`${req.method} ${logicalPath(new URL(req.url).pathname)}`];
        if (route === undefined) return errRouteNotFound();

        // middlewareAuth: sin Bearer → 401; token inválido → 401 (desviación documentada)
        let token = "";
        let uid = "";
        if (route.auth) {
            const m = (req.headers.get("Authorization") ?? "").match(/Bearer\s+(.*)$/i);
            if (m === null) return errUnauthorized();
            token = m[1];
            const who = await verifyUser(token);
            if (who === null) return errUnauthorized();
            uid = who.id as string;
        }

        // Contexto X-Home-Id (§2.2, pasos 3–6): solo rutas autenticadas (auth:false lo ignora).
        // Orden A10: sesión → cabecera/membresía → handler (validación de entrada → RPC).
        let activeHome: string | null = null;
        if (route.auth) {
            const hp = parseHomeHeader(req);
            if (hp === "INVALID") return errInvalidHome();
            if (hp.present) {
                if (!(await checkHomeMember(hp.id, token))) {
                    return route.home ? errRouteHomeNotFound() : errPhpNotFound();
                }
                activeHome = hp.id;
            }
        }
        return await runWithHome(activeHome, () => route.handler(req, token, uid));
    } catch (e) {
        return error(e instanceof Error ? e.message : String(e), 500);
    }
});
