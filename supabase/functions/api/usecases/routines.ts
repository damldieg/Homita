// routine (Routine*.php). Orden PHP literal por ruta (ver contract-inventory.md):
// index: tz → materializa; detail/create/update/alarm/delete: id/M → … → validaciones.
import { getInput, inputInt, phpInput, inputTimezone } from "../_shared/contract.ts";
import {
    errInvalidTimezone, errPhpNotFound, errRoutineCalendarRequired, errRoutineIdRequired,
    rpcError, rpcPass,
} from "../_shared/errors.ts";
import { appUserRow, materializeRoutines, rpc } from "../_shared/supabase.ts";
import { personIdsOf, validateAlarm, validateRoutine } from "../_shared/validate.ts";

const materialize = async (uid: string, token: string, tz: string): Promise<Response | null> => {
    const me = await appUserRow(uid, token);
    if (me === null) return errPhpNotFound();
    const mat = await materializeRoutines(me.id, tz);
    if (!mat.ok) return rpcError(await mat.json().catch(() => null));
    return null;
};

// GET /routine (RoutineIndex.php → findByUser materializa)
export const handleRoutineIndex = async (req: Request, token: string, uid: string): Promise<Response> => {
    const input = await phpInput(req);
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const fail = await materialize(uid, token, tz);
    if (fail) return fail;
    return rpcPass(await rpc("get_routines", {}, token));
};

// GET /routine/detail (RoutineDetail.php): id → M → tz → materializa; devuelve la fila previa a la
// materialización (como PHP, que captura $routine antes)
export const handleRoutineDetail = async (req: Request, token: string, uid: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (!id) return errRoutineIdRequired();
    const detail = await rpc("get_routine_detail", { p_id: id }, token);
    if (!detail.ok) return rpcError(await detail.json().catch(() => null));
    const row = await detail.json();
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const fail = await materialize(uid, token, tz);
    if (fail) return fail;
    return rpcPass(new Response(JSON.stringify(row), { headers: { "Content-Type": "application/json" } }));
};

// POST /routine/create (RoutineCreate.php): calendar_id → person_ids → tz → validate → alarm → M
export const handleRoutineCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const calendarId = inputInt(input, "calendar_id");
    if (!calendarId) return errRoutineCalendarRequired();
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const v = validateRoutine(input, null);
    if ("err" in v) return v.err;
    const alarm = validateAlarm(getInput(input, "alarm"));
    if (alarm instanceof Response) return alarm;
    return rpcPass(await rpc("create_routine", {
        p_calendar_id: calendarId,
        p_title: v.values.title,
        p_frequency: v.values.frequency,
        p_interval: v.values.interval,
        p_days: v.values.days,
        p_time: v.values.time,
        p_start_date: v.values.start_date,
        p_end_date: v.values.end_date,
        p_active: v.values.active,
        p_alarm: alarm,
        p_person_ids: personIds,
        p_timezone: tz,
    }, token));
};

// PATCH /routine/update (RoutineUpdate.php): id → M → person_ids → tz → validate(current) →
// reconcile interno en la RPC
export const handleRoutineUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (!id) return errRoutineIdRequired();
    const detail = await rpc("get_routine_detail", { p_id: id }, token); // M → 500 Not Found
    if (!detail.ok) return rpcError(await detail.json().catch(() => null));
    const current = await detail.json();
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    const v = validateRoutine(input, { frequency: current.frequency, interval: current.interval });
    if ("err" in v) return v.err;
    return rpcPass(await rpc("update_routine", {
        p_id: id,
        p_title: v.values.title,
        p_frequency: v.values.frequency,
        p_interval: v.values.interval,
        p_days: v.values.days,
        p_time: v.values.time,
        p_start_date: v.values.start_date,
        p_end_date: v.values.end_date,
        p_active: v.values.active,
        p_person_ids: personIds,
        p_timezone: tz,
    }, token));
};

// PATCH /routine/alarm (RoutineAlarm.php): id → M → alarm (strict) → tz → setAlarm + syncAlarms
export const handleRoutineAlarm = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (!id) return errRoutineIdRequired();
    const detail = await rpc("get_routine_detail", { p_id: id }, token); // M
    if (!detail.ok) return rpcError(await detail.json().catch(() => null));
    const alarm = validateAlarm(getInput(input, "alarm"));
    if (alarm instanceof Response) return alarm;
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    return rpcPass(await rpc("set_routine_alarm", { p_id: id, p_alarm: alarm, p_timezone: tz }, token));
};

// DELETE /routine/delete (RoutineDelete.php): id → M → tz → delete (con cascadas de PHP)
export const handleRoutineDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (!id) return errRoutineIdRequired();
    const detail = await rpc("get_routine_detail", { p_id: id }, token); // M
    if (!detail.ok) return rpcError(await detail.json().catch(() => null));
    const tz = inputTimezone(input);
    if (tz === "INVALID") return errInvalidTimezone();
    return rpcPass(await rpc("delete_routine", { p_id: id, p_timezone: tz }, token));
};
