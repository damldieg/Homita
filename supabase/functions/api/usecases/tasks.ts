import { phpBool, phpInt } from "../_shared/contract.ts";
import { errPhpNotFound, rpcError } from "../_shared/errors.ts";
import { hasTaskListAccess, rpc } from "../_shared/supabase.ts";

// TaskIndex.php: check estricto de pertenencia (TaskListUser::check → "Not Found") + filtros
export const handleTask = async (req: Request, token: string, uid: string): Promise<Response> => {
    const q = new URL(req.url).searchParams;

    const raw = q.get("task_list_id") ?? "";
    if (/^[0-9]+$/.test(raw) && parseInt(raw, 10) !== 0) {
        const allowed = await hasTaskListAccess(token, parseInt(raw, 10));
        if (!allowed) return errPhpNotFound();
    }

    const res = await rpc("get_tasks", {
        p_dashboard: phpBool(q.get("dashboard")),
        p_task_list_id: phpInt(q.get("task_list_id")),
        p_widget: phpBool(q.get("widget")),
    }, token);
    if (!res.ok) return rpcError(await res.json().catch(() => null));
    return new Response(await res.text(), { headers: { "Content-Type": "application/json" } });
};
