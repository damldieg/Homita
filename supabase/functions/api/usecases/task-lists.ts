// task-list + task-list/user (TaskList*.php). Matriz §3 owner/viewer en las RPC (0006/0008).
import { inputBool, inputEmail, inputInt, inputString, json, phpEmpty, phpInput, fmt } from "../_shared/contract.ts";
import {
    errPhpNotFound, errTaskListCreateRequired, errTaskListIdRequired, errTaskListSort,
    errTaskListUpdateRequired, errTaskListUserCreateRequired, errTaskListUserDeleteRequired,
    errTaskListUserIdRequired, rpcPass,
} from "../_shared/errors.ts";
import { rpc, selectRows } from "../_shared/supabase.ts";

const SORTS = ["updated_at", "title", "custom"];
const TL_COLS = "id,name,color,token,sort,created_at,updated_at";

const tlRow = (r: Record<string, unknown>): Record<string, unknown> => ({
    ...r,
    created_at: fmt(r.created_at as string),
    updated_at: fmt(r.updated_at as string),
});

// GET /task-list (TaskListIndex.php → TaskList::findByUser)
export const handleTaskListIndex = async (_req: Request, token: string): Promise<Response> =>
    rpcPass(await rpc("get_task_lists", {}, token));

// GET /task-list/detail (TaskListDetail.php): id → M (RLS) → TaskList::findById (sin flags/count)
export const handleTaskListDetail = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errTaskListIdRequired();
    const rows = await selectRows("task_list", `id=eq.${id}&select=${TL_COLS}&limit=1`, token);
    if (rows.length === 0) return errPhpNotFound();
    return json(tlRow(rows[0]));
};

// POST /task-list/create (TaskListCreate.php): creador = owner; color con fallback ?: '#6923E2'
export const handleTaskListCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const name = inputString(input, "name");
    const color = inputString(input, "color");
    const sort = inputString(input, "sort", "updated_at");
    const widget = inputBool(input, "widget", true);
    const dashboard = inputBool(input, "dashboard", true);
    if (phpEmpty(name)) return errTaskListCreateRequired();
    if (!SORTS.includes(sort as string)) return errTaskListSort();
    return rpcPass(await rpc("create_task_list", {
        p_name: name,
        p_color: phpEmpty(color) ? "#6923E2" : color,
        p_sort: sort,
        p_widget: widget,
        p_dashboard: dashboard,
    }, token), 201);
};

// PATCH /task-list/update (TaskListUpdate.php): name/color/sort compartidos → owner (403 si
// viewer y cambian); widget/dashboard → self-row (matriz §3)
export const handleTaskListUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    const name = inputString(input, "name");
    const color = inputString(input, "color");
    const sort = inputString(input, "sort");
    const widget = inputBool(input, "widget", true);
    const dashboard = inputBool(input, "dashboard", true);
    if (phpEmpty(id) || phpEmpty(name) || phpEmpty(color) || phpEmpty(sort)) return errTaskListUpdateRequired();
    if (!SORTS.includes(sort as string)) return errTaskListSort();
    return rpcPass(await rpc("update_task_list", {
        p_id: id, p_name: name, p_color: color, p_sort: sort,
        p_widget: widget, p_dashboard: dashboard,
    }, token));
};

// DELETE /task-list/delete (TaskListDelete.php): M + owner (desviación Q5)
export const handleTaskListDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errTaskListIdRequired();
    return rpcPass(await rpc("delete_task_list", { p_id: id }, token));
};

// GET /task-list/user (TaskListUserIndex.php): quirk PHP `=== 0 || === null`
export const handleTaskListUserIndex = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const taskListId = inputInt(input, "task_list_id");
    if (taskListId === 0 || taskListId === null) return errTaskListUserIdRequired();
    return rpcPass(await rpc("get_task_list_users", { p_task_list_id: taskListId }, token));
};

// POST /task-list/user (TaskListUserCreate.php): M + owner; rol insertado 'viewer' (Q6 lookup)
export const handleTaskListUserCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const taskListId = inputInt(input, "task_list_id");
    const email = inputEmail(input, "email");
    if (phpEmpty(taskListId) || phpEmpty(email)) return errTaskListUserCreateRequired();
    return rpcPass(await rpc("add_task_list_user", { p_task_list_id: taskListId, p_email: email }, token));
};

// DELETE /task-list/user (TaskListUserDelete.php): M → S (400) → O (403) en la RPC (matriz §3)
export const handleTaskListUserDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const taskListId = inputInt(input, "task_list_id");
    const userId = inputInt(input, "user_id");
    if (phpEmpty(taskListId) || phpEmpty(userId)) return errTaskListUserDeleteRequired();
    return rpcPass(await rpc("remove_task_list_user", { p_task_list_id: taskListId, p_user_id: userId }, token));
};
