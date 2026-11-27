// Edge Function `api` — contrato (a) PHP-compat de las 43 rutas legacy del backend (D-008;
// inventario: .dorch/archive/control-api/contract-inventory.md) + las 19 rutas /home/* de
// 1.4–1.15 (diseño §5.2, flag `home: true` en ROUTES; 1.5 añade /home/member/*, 1.6
// /home/membership/*, 1.9 /home/permission y /home/audit, 1.15 /home/invitation*).
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
// cero coste y respuestas idénticas a las de antes de 1.4. Excepción (1.15, D-015):
// POST /home/invitation/accept (`homeContext: false`) valida el formato de la cabecera, pero no
// comprueba la membresía ni la propaga: quien acepta aún no es miembro y el hogar lo fija el código.
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
// routines,events,task-lists,tasks,homes,meals}.ts + _shared/{supabase,contract,errors,validate}.ts.

import { error, errInvalidHome, errNotFound500, errRouteHomeNotFound, errRouteNotFound, errUnauthorized } from "./_shared/errors.ts";
import { checkHomeMember, parseHomeHeader, runWithHome } from "./_shared/home.ts";
import { verifyUser } from "./_shared/supabase.ts";
import {
    handleConfig, handleUserAuth, handleUserCreate, handleUserRefresh, handleUserUpdate,
} from "./usecases/auth.ts";
import {
    handleCalendarCreate, handleCalendarDelete, handleCalendarDetail, handleCalendarIndex,
    handleCalendarUpdate, handleCalendarUserAccess, handleCalendarUserCreate, handleCalendarUserDelete, handleCalendarUserIndex,
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
    handleTaskListOrder, handleTaskListUpdate, handleTaskListUserAccess, handleTaskListUserCreate, handleTaskListUserDelete, handleTaskListUserIndex,
} from "./usecases/task-lists.ts";
import {
    handleTask, handleTaskComplete, handleTaskCreate, handleTaskDelete, handleTaskDetail,
    handleTaskOrder, handleTaskUpdate,
} from "./usecases/tasks.ts";
import { handleFeedbackCreate } from "./usecases/feedback.ts";
import {
    handleDisplayConfig, handleDisplayLinkConfirm, handleDisplayLinkPoll, handleDisplayLinkStart,
    handleDisplayList, handleDisplayRevoke, handleDisplayUpdate, handleDisplayReleaseCheck, handleDisplaySetChannel,
} from "./usecases/displays.ts";
import {
    handleHomeCreate, handleHomeDefault, handleHomeDetail, handleHomeIndex, handleHomeMemberCreate,
    handleHomeMemberIndex, handleHomeMemberUpdate, handleHomeMembership, handleHomeMembershipRemove,
    handleHomeMembershipRole, handleHomeMembershipTransfer, handleHomeUpdate,
    handleHomePermissionIndex, handleHomePermissionUpdate, handleHomeAudit,
    handleHomeInvitationAccept, handleHomeInvitationCreate, handleHomeInvitationIndex,
    handleHomeInvitationRevoke,
} from "./usecases/homes.ts";
import {
    handleMealProfileGet, handleMealProfileMemberUpdate, handleMealProfileUpdate, handleMealScheduleSet,
    handleMealSlotsSet, handleMealPlanAccept, handleMealPlanArchive, handleMealPlanCheck, handleMealPlanCopy,
    handleMealPlanGet, handleMealPlanItems, handleMealToday,
} from "./usecases/meals.ts";
import {
    handleShoppingClearChecked, handleShoppingItemCheck, handleShoppingItemCreate, handleShoppingItemDelete,
    handleShoppingItemQty, handleShoppingList, handleShoppingPreview, handleShoppingSync,
} from "./usecases/shopping.ts";
import {
    handleFoodCreate, handleFoodDelete, handleFoodSearch, handleFoodUpdate, handleRecipeCreate,
    handleRecipeDelete, handleRecipeDetail, handleRecipeIndex, handleRecipeUpdate,
} from "./usecases/recipes.ts";

type Handler = (req: Request, token: string, uid: string) => Promise<Response> | Response;

// `home: true` (rutas /home/*, 1.4): el "no miembro" del contexto X-Home-Id se mapea a 404
// (D16) en vez del 500 legacy (errNotFound500). `homeContext: false` (1.15, D-015): la ruta
// ignora el contexto de hogar (sin comprobar membresía ni propagar la cabecera a PostgREST).
const ROUTES: Record<string, { auth: boolean; home?: boolean; homeContext?: boolean; handler: Handler }> = {
    "GET /config": { auth: false, handler: () => handleConfig() },
    "POST /user/create": { auth: false, handler: (req) => handleUserCreate(req) },
    "POST /user/auth": { auth: false, handler: (req) => handleUserAuth(req) },
    // dashboard-sesion: ruta aditiva (D-008) para que la pantalla renueve su sesión sin la anon key.
    "POST /user/refresh": { auth: false, handler: (req) => handleUserRefresh(req) },
    "PATCH /user/update": { auth: true, handler: (req, t, u) => handleUserUpdate(req, t, u) },

    "GET /calendar": { auth: true, handler: (req, t) => handleCalendarIndex(req, t) },
    "GET /calendar/detail": { auth: true, handler: (req, t) => handleCalendarDetail(req, t) },
    "POST /calendar/create": { auth: true, handler: (req, t) => handleCalendarCreate(req, t) },
    "PATCH /calendar/update": { auth: true, handler: (req, t) => handleCalendarUpdate(req, t) },
    "DELETE /calendar/delete": { auth: true, handler: (req, t) => handleCalendarDelete(req, t) },
    "GET /calendar/user": { auth: true, handler: (req, t) => handleCalendarUserIndex(req, t) },
    "POST /calendar/user": { auth: true, handler: (req, t) => handleCalendarUserCreate(req, t) },
    "DELETE /calendar/user": { auth: true, handler: (req, t) => handleCalendarUserDelete(req, t) },
    "PATCH /calendar/user": { auth: true, handler: (req, t) => handleCalendarUserAccess(req, t) },

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
    // lista-prioritaria-inicio: ruta aditiva (D-008) para ordenar las listas; sin X-Home-Id (D-012).
    "PATCH /task-list/order": { auth: true, handler: (req, t) => handleTaskListOrder(req, t) },
    "PATCH /task-list/update": { auth: true, handler: (req, t) => handleTaskListUpdate(req, t) },
    "DELETE /task-list/delete": { auth: true, handler: (req, t) => handleTaskListDelete(req, t) },
    "GET /task-list/user": { auth: true, handler: (req, t) => handleTaskListUserIndex(req, t) },
    "POST /task-list/user": { auth: true, handler: (req, t) => handleTaskListUserCreate(req, t) },
    "DELETE /task-list/user": { auth: true, handler: (req, t) => handleTaskListUserDelete(req, t) },
    "PATCH /task-list/user": { auth: true, handler: (req, t) => handleTaskListUserAccess(req, t) },

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
    "GET /home/permission": { auth: true, home: true, handler: (req, t) => handleHomePermissionIndex(req, t) },
    "PATCH /home/permission": { auth: true, home: true, handler: (req, t) => handleHomePermissionUpdate(req, t) },
    "GET /home/audit": { auth: true, home: true, handler: (req, t) => handleHomeAudit(req, t) },
    "GET /home/invitation": { auth: true, home: true, handler: (req, t) => handleHomeInvitationIndex(req, t) },
    "POST /home/invitation/create": { auth: true, home: true, handler: (req, t) => handleHomeInvitationCreate(req, t) },
    "POST /home/invitation/accept": { auth: true, homeContext: false, handler: (req, t) => handleHomeInvitationAccept(req, t) },
    "POST /home/invitation/revoke": { auth: true, home: true, handler: (req, t) => handleHomeInvitationRevoke(req, t) },

    // change menus-perfil-hogar (0043): rutas aditivas (D-008) del perfil de comidas; X-Home-Id o regla de
    // fn_home_for_root_create (404 si la cabecera no es de un hogar propio).
    "GET /meal/profile": { auth: true, home: true, handler: (req, t) => handleMealProfileGet(req, t) },
    "PATCH /meal/profile": { auth: true, home: true, handler: (req, t) => handleMealProfileUpdate(req, t) },
    "PATCH /meal/profile/member": { auth: true, home: true, handler: (req, t) => handleMealProfileMemberUpdate(req, t) },
    "PUT /meal/schedule": { auth: true, home: true, handler: (req, t) => handleMealScheduleSet(req, t) },
    "PUT /meal/slots": { auth: true, home: true, handler: (req, t) => handleMealSlotsSet(req, t) },

    // change menus-semana (0044): recetas, catálogo de alimentos y menú semanal (rutas aditivas D-008);
    // X-Home-Id o regla de fn_home_for_root_create. 409 solo en 'Stale meal plan revision' y 'Meal plan exists'.
    "GET /recipe": { auth: true, home: true, handler: (req, t) => handleRecipeIndex(req, t) },
    "GET /recipe/detail": { auth: true, home: true, handler: (req, t) => handleRecipeDetail(req, t) },
    "POST /recipe/create": { auth: true, home: true, handler: (req, t) => handleRecipeCreate(req, t) },
    "PATCH /recipe/update": { auth: true, home: true, handler: (req, t) => handleRecipeUpdate(req, t) },
    "DELETE /recipe/delete": { auth: true, home: true, handler: (req, t) => handleRecipeDelete(req, t) },
    "GET /food": { auth: true, home: true, handler: (req, t) => handleFoodSearch(req, t) },
    "POST /food/create": { auth: true, home: true, handler: (req, t) => handleFoodCreate(req, t) },
    "PATCH /food/update": { auth: true, home: true, handler: (req, t) => handleFoodUpdate(req, t) },
    "DELETE /food/delete": { auth: true, home: true, handler: (req, t) => handleFoodDelete(req, t) },
    "GET /meal/plan": { auth: true, home: true, handler: (req, t) => handleMealPlanGet(req, t) },
    "PATCH /meal/plan/items": { auth: true, home: true, handler: (req, t) => handleMealPlanItems(req, t) },
    "POST /meal/plan/accept": { auth: true, home: true, handler: (req, t) => handleMealPlanAccept(req, t) },
    "POST /meal/plan/archive": { auth: true, home: true, handler: (req, t) => handleMealPlanArchive(req, t) },
    "POST /meal/plan/copy": { auth: true, home: true, handler: (req, t) => handleMealPlanCopy(req, t) },
    "GET /meal/plan/check": { auth: true, home: true, handler: (req, t) => handleMealPlanCheck(req, t) },
    "GET /meal/today": { auth: true, home: true, handler: (req, t) => handleMealToday(req, t) },

    // change menus-compra (0045): la Compra del hogar (rutas aditivas D-008); X-Home-Id o regla de
    // fn_home_for_root_create. Lectura con menu.view; escrituras con menu.shopping.edit (guest → 403).
    "GET /shopping": { auth: true, home: true, handler: (req, t) => handleShoppingList(req, t) },
    "GET /shopping/preview": { auth: true, home: true, handler: (req, t) => handleShoppingPreview(req, t) },
    "POST /shopping/sync": { auth: true, home: true, handler: (req, t) => handleShoppingSync(req, t) },
    "POST /shopping/item/create": { auth: true, home: true, handler: (req, t) => handleShoppingItemCreate(req, t) },
    "PATCH /shopping/item/check": { auth: true, home: true, handler: (req, t) => handleShoppingItemCheck(req, t) },
    "PATCH /shopping/item/update": { auth: true, home: true, handler: (req, t) => handleShoppingItemQty(req, t) },
    "DELETE /shopping/item/delete": { auth: true, home: true, handler: (req, t) => handleShoppingItemDelete(req, t) },
    "DELETE /shopping/checked": { auth: true, home: true, handler: (req, t) => handleShoppingClearChecked(req, t) },

    // dashboard-pantalla-hogar (0049, D-008): pantallas del hogar. La vinculación empieza sin sesión (la pantalla
    // muestra un código); confirmar y gestionar exigen X-Home-Id y display.manage (o calendar.manage) en la RPC.
    "POST /home/display/link-start": { auth: false, handler: () => handleDisplayLinkStart() },
    "POST /home/display/link-poll": { auth: false, handler: (req) => handleDisplayLinkPoll(req) },
    "POST /home/display/link-confirm": { auth: true, home: true, handler: (req, t) => handleDisplayLinkConfirm(req, t) },
    "GET /home/display": { auth: true, home: true, handler: (req, t) => handleDisplayList(req, t) },
    "PATCH /home/display/update": { auth: true, home: true, handler: (req, t) => handleDisplayUpdate(req, t) },
    "POST /home/display/revoke": { auth: true, home: true, handler: (req, t) => handleDisplayRevoke(req, t) },
    // La pantalla lee su propia configuración con su sesión; no envía cabecera de hogar.
    "GET /display/config": { auth: true, homeContext: false, handler: (req, t) => handleDisplayConfig(req, t) },
    "GET /display/update": { auth: true, homeContext: false, handler: (req, t) => handleDisplayReleaseCheck(req, t) },
    "PATCH /home/display/channel": { auth: true, home: true, handler: (req, t) => handleDisplaySetChannel(req, t) },

    // change control-ios-feedback: ruta aditiva (D-008), fuera de las 43 legacy; sin X-Home-Id.
    "POST /feedback": { auth: true, handler: (req, t) => handleFeedbackCreate(req, t) },
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
            if (hp.present && route.homeContext !== false) {
                if (!(await checkHomeMember(hp.id, token))) {
                    return route.home ? errRouteHomeNotFound() : errNotFound500();
                }
                activeHome = hp.id;
            }
        }
        return await runWithHome(activeHome, () => route.handler(req, token, uid));
    } catch (e) {
        return error(e instanceof Error ? e.message : String(e), 500);
    }
});
