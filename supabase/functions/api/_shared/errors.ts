// Errores del contrato PHP: strings exactos de ControllerAbstract/UserAuth/middlewareAuth/router
// (inventario: .dorch/archive/control-api/contract-inventory.md).
import { json } from "./contract.ts";

export const error = (message: string, status: number): Response => json({ error: message }, status);

// Mensajes que PHP emite como InvalidArgumentException → 400 (Router.php:62-67). Los que salen de
// una RPC (validación de person tras lookup) se mapean aquí; 'Not Allowed' es el owner-only de la
// matriz §3 (desviación Q5, 403) y el resto → 500 (como Database.php:56).
const RPC_STATUS: Record<string, number> = {
    "Not Allowed": 403,
    "User cannot remove themselves": 400,
    "Invalid timezone": 400,
    "Name is required (max 50 characters)": 400,
    "Color must be #RRGGBB": 400,
    "Alarm must be nonnegative minutes or null": 400,
    "Invalid person": 400,
    "Title and date_at are required if text is not provided": 400,
    "Event ID, title, and date_at are required": 400,
    "task_list_id and title are required": 400,
    "Task ID and title are required": 400,
    // D-1 (1.4): diferidas de 1.3. 'Invalid home' = fn_active_home_id (0012) si la cabecera llega
    // mal formada a SQL (la Edge la valida antes: defensa); 'Home header required' =
    // fn_home_for_root_create (0012) con 2+ hogares sin default y sin cabecera.
    "Invalid home": 400,
    "Home header required": 400,
    "Name is required": 400,
    // 1.5: kind/status inválido o pet vinculado (0017; plan §4.5, §6.1)
    "Invalid member": 400,
    // 1.6: rol fuera de admin/member y transferencia a la propia membresía (0018; plan §3.5)
    "Invalid role": 400,
    "Invalid membership": 400,
    // 1.9: código fuera del catálogo o shape de permissions inválido (0021; plan §4.3)
    "Invalid permission": 400,
    // 1.15: aceptar una invitación de un hogar del que ya se es miembro (0022; sin consumirla)
    "Already member": 400,
    // 1.15 + 0026: email de invitación ausente o mal formado (create)
    "Invalid email": 400,
};

// Router::error de PHP: InvalidArgumentException → 400; el resto → 500 con el mensaje
export const rpcError = (body: unknown): Response => {
    const message = (body as { message?: string } | null)?.message ?? "Internal error";
    return error(message, RPC_STATUS[message] ?? 500);
};

// Pasa el JSON de la RPC tal cual (forma PHP) o mapea su error a los status del contrato
export const rpcPass = async (res: Response, status = 200): Promise<Response> => {
    if (!res.ok) return rpcError(await res.json().catch(() => null));
    return new Response(await res.text(), { status, headers: { "Content-Type": "application/json" } });
};

// Como rpcPass para las rutas /home/* (D16, §6.2): 'Not Found' → 404 (no visible/no miembro);
// el resto por RPC_STATUS ('Not Allowed' 403, 'Invalid home'/'Home header required'/validación 400)
export const rpcPassHome = async (res: Response, status = 200): Promise<Response> => {
    if (!res.ok) {
        const message = ((await res.json().catch(() => null)) as { message?: string } | null)?.message
            ?? "Internal error";
        return error(message, message === "Not Found" ? 404 : (RPC_STATUS[message] ?? 500));
    }
    return new Response(await res.text(), { status, headers: { "Content-Type": "application/json" } });
};

export const errAuthFieldsRequired = (): Response => error("Email and password are required", 400);
export const errInvalidCredentials = (): Response => error("Invalid credentials", 401);
export const errUnauthorized = (): Response => error("Unauthorized", 401);
export const errRouteNotFound = (): Response => error("Not Found", 404);
export const errNotFound500 = (): Response => error("Not Found", 500);
export const errInvalidTimezone = (): Response => error("Invalid timezone", 400);
export const errNotAllowed = (): Response => error("Not Allowed", 403);
export const errUserCannotRemoveThemselves = (): Response => error("User cannot remove themselves", 400);

// home (rutas /home/*, §6.2): validación de entrada y errores de contexto X-Home-Id
export const errHomeIdRequired = (): Response => error("Home ID is required", 400);
export const errRouteHomeNotFound = (): Response => error("Not Found", 404);
export const errInvalidHome = (): Response => error("Invalid home", 400);

// home/member (1.5 §6.1): id de miembro; los tipos JSON no-string de kind/status emiten
// 'Invalid member' desde homes.ts (el mensaje vive una sola vez en errors.ts: RPC_STATUS)
export const errHomeMemberIdRequired = (): Response => error("Member ID is required", 400);

// home/membership (1.6 §6.1): id de home_membership (lo devuelve GET /home/membership) y role
export const errHomeMembershipIdRequired = (): Response => error("Membership ID is required", 400);
export const errInvalidRole = (): Response => error("Invalid role", 400);

// home/permission (1.9 §4.2): permissions ausente, no array o con elemento no string, y códigos
// fuera del catálogo (rechazo en la Edge sin llamar a la RPC; la RPC repite la barrera)
export const errInvalidPermission = (): Response => error("Invalid permission", 400);

// home/invitation (1.15): code ausente/vacío en accept e id de invitación en revoke. Un código
// presente pero mal formado NO usa estos errores: responde el mismo 404 que la RPC (sin oráculo)
export const errInvitationCodeRequired = (): Response => error("Invitation code is required", 400);
export const errInvitationIdRequired = (): Response => error("Invitation ID is required", 400);
// 0026: el admin indica el email del invitado (obligatorio y con formato válido).
export const errInvalidEmail = (): Response => error("Invalid email", 400);
// 0026: registro con código. Código no válido (inexistente, caducado, usado, revocado, hogar
// archivado o sin email en la invitación) → 404; email distinto al de la invitación → 403.
export const errInvitationNotValidForSignup = (): Response => error("Invitation code is not valid", 404);
export const errInvitationEmailMismatch = (): Response =>
    error("The invitation was sent to another email address", 403);

// user/create (UserCreate.php)
export const errUserFieldsRequired = (): Response => error("Name, email and password are required", 400);
export const errNameLength = (): Response => error("Name must be between 3 and 50 characters", 400);
export const errPasswordLength = (): Response => error("Password must be at least 8 characters", 400);
export const errEmailExists = (): Response => error("Email already exists", 400);

// user/update (UserUpdate.php)
export const errProfileFieldsRequired = (): Response => error("Name and email cannot be empty", 400);

// calendar (Calendar*.php)
export const errNameRequired = (): Response => error("Name is required", 400);
export const errCalendarIdRequired = (): Response => error("Calendar ID is required", 400);
export const errCalendarUpdateRequired = (): Response => error("Calendar ID, name and color are required", 400);
export const errCalendarUserIdRequired = (): Response => error("calendar_id is required", 400);
export const errCalendarUserCreateRequired = (): Response => error("Calendar ID and email are required", 400);
export const errCalendarUserDeleteRequired = (): Response => error("calendar_id and user_id are required", 400);

// person (Person.php / PersonControllerAbstract.php)
export const errPersonIdRequired = (): Response => error("Person ID is required", 400);
export const errPersonNameRequired = (): Response => error("Name is required (max 50 characters)", 400);
export const errPersonColorInvalid = (): Response => error("Color must be #RRGGBB", 400);
export const errPersonIdsList = (): Response => error("person_ids must be a list", 400);
export const errPersonIdsIds = (): Response => error("person_ids must be a list of IDs", 400);
export const errPersonInvalid = (): Response => error("Invalid person", 400);

// routine (Routine.php / RoutineControllerAbstract.php)
export const errRoutineIdRequired = (): Response => error("Routine ID is required", 400);
export const errRoutineCalendarRequired = (): Response => error("Calendar ID is required", 400);
export const errRoutineTitleRequired = (): Response => error("Title is required", 400);
export const errRoutineFrequency = (): Response => error("Frequency must be daily, weekly or monthly", 400);
export const errRoutineInterval = (): Response => error("Interval must be 1 to 99", 400);
export const errRoutineDaysRequired = (): Response => error("Title and selected days are required", 400);
export const errRoutineDaysRange = (): Response => error("Days must be ISO weekdays 1 to 7", 400);
export const errRoutineTime = (): Response => error("Invalid time", 400);
export const errRoutineDate = (): Response => error("Invalid date", 400);
export const errRoutineDateRange = (): Response => error("Invalid date range", 400);
export const errRoutineActive = (): Response => error("Active must be boolean", 400);
export const errAlarmInvalid = (): Response => error("Alarm must be nonnegative minutes or null", 400);

// event (Event*.php)
export const errEventIdRequired = (): Response => error("Event ID is required", 400);
export const errEventUpdateRequired = (): Response => error("Event ID, title, and date_at are required", 400);
export const errEventAlarmIdRequired = (): Response => error("event_id is required", 400);
export const errEventTextOnly = (): Response => error("Title and date_at are required if text is not provided", 400);

// task-list (TaskList*.php)
export const errTaskListIdRequired = (): Response => error("Task list ID is required", 400);
export const errTaskListCreateRequired = (): Response => error("Name is required", 400);
export const errTaskListSort = (): Response => error("Sort must be updated_at, title or custom", 400);
export const errTaskListUpdateRequired = (): Response => error("Task list ID, name, color and sort are required", 400);
export const errTaskListUserIdRequired = (): Response => error("task_list_id is required", 400);
export const errTaskListUserCreateRequired = (): Response => error("Task list ID and email are required", 400);
export const errTaskListUserDeleteRequired = (): Response => error("task_list_id and user_id are required", 400);

// task (Task*.php)
export const errTaskIdRequired = (): Response => error("Task ID is required", 400);
export const errTaskCreateRequired = (): Response => error("task_list_id and title are required", 400);
export const errTaskUpdateRequired = (): Response => error("Task ID and title are required", 400);
export const errTaskCompleteRequired = (): Response => error("Task ID and completed are required", 400);
export const errTaskOrderRequired = (): Response => error("id and position are required", 400);
export const errTaskOrderNegative = (): Response => error("position must be zero or positive", 400);
