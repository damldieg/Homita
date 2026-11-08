import { phpBool, phpInt, phpStr, phpTimestamp } from "../_shared/contract.ts";
import { errInvalidTimezone, errPhpNotFound, rpcError } from "../_shared/errors.ts";
import { appUserRow, materializeRoutines, rpc } from "../_shared/supabase.ts";

// Routine::cutoff valida el IANA de timezone; inválido → 400 "Invalid timezone"
function validTimezone(tz: string): boolean {
    try {
        new Intl.DateTimeFormat("en-US", { timeZone: tz });
        return true;
    } catch {
        return false;
    }
}

// EventIndex.php → Event::findWithFilters: materializa rutinas y consulta con los filtros del contrato
export const handleEvent = async (req: Request, token: string, uid: string): Promise<Response> => {
    const q = new URL(req.url).searchParams;
    const tz = q.get("timezone") ?? "UTC";
    if (!validTimezone(tz)) return errInvalidTimezone();

    const me = await appUserRow(uid, token);
    if (me === null) return errPhpNotFound();

    const mat = await materializeRoutines(me.id, tz);
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
};
