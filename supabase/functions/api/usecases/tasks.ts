// task (Task*.php): M de la lista (cualquier rol) — matriz §3.
import { getInput, inputBool, inputInt, inputString, contractEmpty, contractInput, contractIntval } from "../_shared/contract.ts";
import {
    errNotFound500, errTaskCompleteRequired, errTaskCreateRequired, errTaskIdRequired,
    errTaskOrderNegative, errTaskOrderRequired, errTaskUpdateRequired, rpcError, rpcPass,
} from "../_shared/errors.ts";
import { hasTaskListAccess, rpc } from "../_shared/supabase.ts";
import { personIdsOf } from "../_shared/validate.ts";

// GET /task (TaskIndex.php): task_list_id de body+query con precedencia del body
// (ControllerAbstract.php:31) — si llega → check estricto de pertenencia (TaskListUser::check →
// "Not Found") + filtro. `q` se ignora como en PHP (no hay filtro de búsqueda) — T3.
export const handleTask = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req); // body + $_GET con body primero: contractInput

    // TaskIndex.php:12-16: getInputInt('task_list_id') sobre body+query; truthy → M-check
    const taskListId = inputInt(input, "task_list_id");
    if (taskListId) {
        const allowed = await hasTaskListAccess(token, taskListId);
        if (!allowed) return errNotFound500();
    }

    // Task.php:79-81: getFilterInt — intval del valor truthy; 0 = sin filtro (como get_tasks)
    const rawList = getInput(input, "task_list_id");
    const res = await rpc("get_tasks", {
        p_dashboard: contractBoolOf(input, "dashboard"),
        p_task_list_id: contractEmpty(rawList) ? null : contractIntval(rawList),
        p_widget: contractBoolOf(input, "widget"),
    }, token);
    if (!res.ok) return rpcError(await res.json().catch(() => null));
    return new Response(await res.text(), { headers: { "Content-Type": "application/json" } });
};

// getFilterBool de ModelAbstract (para widget/dashboard de GET /task)
function contractBoolOf(input: Record<string, unknown>, key: string): boolean | null {
    const v = getInput(input, key);
    if (v === null) return null;
    const s = String(v).toLowerCase();
    if (s === "1" || s === "true" || s === "on" || s === "yes") return true;
    if (s === "0" || s === "false" || s === "off" || s === "no" || s === "") return false;
    return null;
}

// GET /task/detail (TaskDetail.php): Task::findByIdAndUser
export const handleTaskDetail = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    if (contractEmpty(id)) return errTaskIdRequired();
    return rpcPass(await rpc("get_task_detail", { p_id: id }, token));
};

// POST /task/create (TaskCreate.php): 201; insert + Task::reorderByList
export const handleTaskCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const taskListId = inputInt(input, "task_list_id");
    const title = inputString(input, "title");
    if (contractEmpty(taskListId) || contractEmpty(title)) return errTaskCreateRequired();
    // person_ids opcional (tareas con personas, 0025): null = sin asignar.
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;
    return rpcPass(await rpc("create_task", { p_task_list_id: taskListId, p_title: title, p_person_ids: personIds }, token), 201);
};

// PATCH /task/update (TaskUpdate.php): update + reorderByList
export const handleTaskUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    const title = inputString(input, "title");
    if (contractEmpty(id) || contractEmpty(title)) return errTaskUpdateRequired();
    // Sin person_ids no se tocan las personas; con array se sincronizan (0025).
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;
    return rpcPass(await rpc("update_task", { p_id: id, p_title: title, p_person_ids: personIds }, token));
};

// PATCH /task/complete (TaskComplete.php): completed bool requerido (getInputBool sin default)
export const handleTaskComplete = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    const completed = inputBool(input, "completed");
    if (contractEmpty(id) || completed === null) return errTaskCompleteRequired();
    return rpcPass(await rpc("complete_task", { p_id: id, p_completed: completed }, token));
};

// PATCH /task/order (TaskOrder.php): position con intval() de PHP; moveToPosition en la RPC
export const handleTaskOrder = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    const raw = getInput(input, "position");
    if (contractEmpty(id) || raw === null) return errTaskOrderRequired();
    const position = contractIntval(raw);
    if (position < 0) return errTaskOrderNegative();
    return rpcPass(await rpc("task_order", { p_id: id, p_position: position }, token));
};

// DELETE /task/delete (TaskDelete.php)
export const handleTaskDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    if (contractEmpty(id)) return errTaskIdRequired();
    return rpcPass(await rpc("delete_task", { p_id: id }, token));
};
