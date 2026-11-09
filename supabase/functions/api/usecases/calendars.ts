// calendar + calendar/user (Calendar*.php). Matriz §3 owner/viewer en las RPC (0006/0008).
import { fmt, inputBool, inputEmail, inputInt, inputString, json, phpEmpty, phpInput } from "../_shared/contract.ts";
import {
    errCalendarIdRequired, errCalendarUpdateRequired, errCalendarUserCreateRequired,
    errCalendarUserIdRequired, errCalendarUserDeleteRequired, errNameRequired, errPhpNotFound,
    error, rpcPass,
} from "../_shared/errors.ts";
import { rpc, selectRows } from "../_shared/supabase.ts";
import { currentHome } from "../_shared/home.ts";

const CAL_COLS = "id,name,color,token,created_at,updated_at,home_id";

// PHP quirk: Calendar::create($name, $color) con color null → TypeError 500 (CalendarCreate.php:21
// no hace fallback como TaskListCreate: pasa null explícito, el default '#6923E2' de la firma NO
// aplica). Mensaje = TypeError del motor con su sufijo de traza, replicado byte a byte salvo la
// ruta del sufijo: PHP imprime la absoluta de su despliegue y la Edge la canónica del repo
// (desviación documentada en contract-inventory.md / ARCHITECTURE.md).
const PHP_COLOR_TYPE_ERROR =
    "App\\Models\\Calendar::create(): Argument #2 ($color) must be of type string, null given, " +
    "called in api/src/Controllers/CalendarCreate.php on line 21";

const calRow = (r: Record<string, unknown>): Record<string, unknown> => ({
    ...r,
    created_at: fmt(r.created_at as string),
    updated_at: fmt(r.updated_at as string),
});

// GET /calendar (CalendarIndex.php → Calendar::findByUser)
export const handleCalendarIndex = async (_req: Request, token: string): Promise<Response> =>
    rpcPass(await rpc("get_calendars", {}, token));

// GET /calendar/detail (CalendarDetail.php): id → M (RLS) → Calendar::findById (sin flags/count).
// Con X-Home-Id el recurso debe ser del hogar activo (§2.2/D-2): filtro home_id=eq (sin
// cabecera, sin filtro).
export const handleCalendarDetail = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errCalendarIdRequired();
    const homeFilter = currentHome() === null ? "" : `&home_id=eq.${currentHome()}`;
    const rows = await selectRows("calendar", `id=eq.${id}&select=${CAL_COLS}&limit=1${homeFilter}`, token);
    if (rows.length === 0) return errPhpNotFound();
    return json(calRow(rows[0]));
};

// POST /calendar/create (CalendarCreate.php): creador = owner; respuesta 201 con Calendar::findById
export const handleCalendarCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const name = inputString(input, "name");
    const color = inputString(input, "color");
    const widget = inputBool(input, "widget", true);
    const dashboard = inputBool(input, "dashboard", true);
    if (phpEmpty(name)) return errNameRequired();
    if (color === null) return error(PHP_COLOR_TYPE_ERROR, 500);
    return rpcPass(
        await rpc("create_calendar",
            { p_name: name, p_color: color, p_widget: widget, p_dashboard: dashboard }, token),
        201,
    );
};

// PATCH /calendar/update (CalendarUpdate.php): name/color compartidos → owner (403 si viewer y
// cambian); widget/dashboard → self-row (matriz §3)
export const handleCalendarUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    const name = inputString(input, "name");
    const color = inputString(input, "color");
    const widget = inputBool(input, "widget", true);
    const dashboard = inputBool(input, "dashboard", true);
    if (phpEmpty(id) || phpEmpty(name) || phpEmpty(color)) return errCalendarUpdateRequired();
    return rpcPass(
        await rpc("update_calendar",
            { p_id: id, p_name: name, p_color: color, p_widget: widget, p_dashboard: dashboard }, token),
    );
};

// DELETE /calendar/delete (CalendarDelete.php): M + owner (desviación Q5)
export const handleCalendarDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errCalendarIdRequired();
    return rpcPass(await rpc("delete_calendar", { p_id: id }, token));
};

// GET /calendar/user (CalendarUserIndex.php): quirk PHP `=== 0` — id ausente llega al check de
// membresía → 500 Not Found (como PHP)
export const handleCalendarUserIndex = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const calendarId = inputInt(input, "calendar_id");
    if (calendarId === 0) return errCalendarUserIdRequired();
    return rpcPass(await rpc("get_calendar_users", { p_calendar_id: calendarId }, token));
};

// POST /calendar/user (CalendarUserCreate.php): M + owner; User::findByEmail → 500 Not Found (Q6)
export const handleCalendarUserCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const calendarId = inputInt(input, "calendar_id");
    const email = inputEmail(input, "email");
    if (phpEmpty(calendarId) || phpEmpty(email)) return errCalendarUserCreateRequired();
    return rpcPass(await rpc("add_calendar_user", { p_calendar_id: calendarId, p_email: email }, token));
};

// DELETE /calendar/user (CalendarUserDelete.php): quirk `=== 0` + M → S (400) → O (403) en la RPC
export const handleCalendarUserDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const calendarId = inputInt(input, "calendar_id");
    const userId = inputInt(input, "user_id");
    if (calendarId === 0 || userId === 0) return errCalendarUserDeleteRequired();
    return rpcPass(await rpc("remove_calendar_user", { p_calendar_id: calendarId, p_user_id: userId }, token));
};
