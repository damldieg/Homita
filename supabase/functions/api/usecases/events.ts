// event (Event*.php). GET /event materializa con service_role (como PHP escribe durante la
// lectura); los writes materializan dentro de la RPC (fn_materialize_my_routines, sin service_role).
import {
    filterBool, getInput, inputDateHour, inputInt, inputString, inputTimezone, phpEmpty, phpInput,
    phpInt, phpStr, phpTimestamp,
} from "../_shared/contract.ts";
import {
    errCalendarIdRequired, errEventAlarmIdRequired, errEventIdRequired, errEventTextOnly,
    errEventUpdateRequired, errInvalidTimezone, errPhpNotFound, rpcError, rpcPass,
} from "../_shared/errors.ts";
import { appUserRow, materializeRoutines, rpc } from "../_shared/supabase.ts";
import { personIdsOf, validateAlarm } from "../_shared/validate.ts";

// getFilterString de ModelAbstract: truthy → trim(strval); vacío/'0' → sin filtro
const filterString = (input: Record<string, unknown>, key: string): string | null => {
    const v = getInput(input, key);
    return v ? phpStr(String(v)) : null;
};

// getFilterBool: sin key (o null) → null; resto filter_var ?? null
const filterBoolOrNull = (input: Record<string, unknown>, key: string): boolean | null => {
    const v = getInput(input, key);
    return v === null ? null : filterBool(v);
};

const materialize = async (uid: string, token: string, tz: string): Promise<Response | null> => {
    const me = await appUserRow(uid, token);
    if (me === null) return errPhpNotFound();
    const mat = await materializeRoutines(me.id, tz);
    if (!mat.ok) return rpcError(await mat.json().catch(() => null));
    return null;
};

// GET /event (EventIndex.php → Event::findWithFilters): filtros del contrato. `q` se ignora como
// en PHP (solo existe `search`, Event.php:96) — T3.
export const handleEvent = async (req: Request, token: string, uid: string): Promise<Response> => {
    const input = await phpInput(req);
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const fail = await materialize(uid, token, tz);
    if (fail) return fail;

    const res = await rpc("get_events", {
        p_start_date: phpTimestamp(filterString(input, "start_date")),
        p_end_date: phpTimestamp(filterString(input, "end_date")),
        p_routine: filterBoolOrNull(input, "routine"),
        p_timezone: tz,
        p_dashboard: filterBoolOrNull(input, "dashboard"),
        p_calendar_id: phpInt(filterString(input, "calendar_id")),
        p_person_id: phpInt(filterString(input, "person_id")),
        p_search: filterString(input, "search"),
        p_limit: phpInt(filterString(input, "limit")),
        p_offset: phpInt(filterString(input, "offset")),
        p_order_mode: phpStr(filterString(input, "order_mode"))?.toUpperCase() ?? "ASC",
        p_widget: filterBoolOrNull(input, "widget"),
    }, token);
    if (!res.ok) return rpcError(await res.json().catch(() => null));
    return new Response(await res.text(), { headers: { "Content-Type": "application/json" } });
};

// GET /event/detail (EventDetail.php): tz → materializa → id → Event::findByIdAndUser
export const handleEventDetail = async (req: Request, token: string, uid: string): Promise<Response> => {
    const input = await phpInput(req);
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const fail = await materialize(uid, token, tz);
    if (fail) return fail;
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errEventIdRequired();
    return rpcPass(await rpc("get_event_detail", { p_id: id }, token));
};

// POST /event/create (EventCreate.php): alarm → person_ids → calendar_id → title/date_at → M. T14:
// el camino `text` (Gemini) está diferido → 400 con el mensaje PHP (desviación documentada).
export const handleEventCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const calendarId = inputInt(input, "calendar_id");
    const text = inputString(input, "text");
    const title = inputString(input, "title");
    const dateAt = inputDateHour(input, "date_at");
    // Routine::validateAlarm ANTES de person_ids y del resto de checks (EventCreate.php:20-22):
    // alarm negativo → 400 `Alarm must be nonnegative minutes or null` con precedencia PHP.
    const alarm = validateAlarm(inputInt(input, "alarm"));
    if (alarm instanceof Response) return alarm;
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;

    if (phpEmpty(calendarId)) return errCalendarIdRequired();
    if (phpEmpty(text) && (phpEmpty(title) || phpEmpty(dateAt))) return errEventTextOnly();
    // PHP: $title && $dateAt → manual; si no → Gemini (diferido, Q2)
    if (phpEmpty(title) || dateAt === null) return errEventTextOnly();

    return rpcPass(await rpc("create_event", {
        p_calendar_id: calendarId,
        p_title: title,
        p_date_at: dateAt,
        p_alarm: alarm,
        p_person_ids: personIds,
    }, token));
};

// PATCH /event/update (EventUpdate.php): person_ids → id/title/date_at → M → exception si sesión
export const handleEventUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const id = inputInt(input, "id");
    const title = inputString(input, "title");
    const dateAt = inputDateHour(input, "date_at");
    // Routine::validateAlarm ANTES de person_ids (EventUpdate.php:19-21): alarm negativo → 400
    const alarm = validateAlarm(inputInt(input, "alarm"));
    if (alarm instanceof Response) return alarm;
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;

    if (phpEmpty(id) || phpEmpty(title) || phpEmpty(dateAt)) return errEventUpdateRequired();
    return rpcPass(await rpc("update_event", {
        p_id: id, p_title: title, p_date_at: dateAt, p_alarm: alarm,
        p_person_ids: personIds, p_timezone: tz,
    }, token));
};

// DELETE /event/delete (EventDelete.php): id → M → exception cancelled si sesión
export const handleEventDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errEventIdRequired();
    return rpcPass(await rpc("delete_event", { p_id: id, p_timezone: tz }, token));
};

// PATCH /event/alarm (EventAlarm.php): event_id → M → EventUser::apply (rutina: routine_event_alarm
// + event_user; manual: null borra, si no upsert). La validación de `alarm` NO se hace aquí: en PHP
// la hace EventUser::apply:18 DESPUÉS del lookup M (EventAlarm.php:22-24) — vive en
// fn_apply_event_alarm (0006) para conservar la precedencia (M 500 antes que alarm 400).
export const handleEventAlarm = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const eventId = inputInt(input, "event_id");
    const alarm = inputInt(input, "alarm");
    if (phpEmpty(eventId)) return errEventAlarmIdRequired();
    return rpcPass(await rpc("set_event_alarm", {
        p_event_id: eventId, p_alarm: alarm, p_timezone: tz,
    }, token));
};
