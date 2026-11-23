// task (Task*.php): M de la lista (cualquier rol) — matriz §3.
import { getInput, inputBool, inputInt, inputString, contractEmpty, contractInput, contractIntval } from "../_shared/contract.ts";
import {
    errNotFound500, errTaskCompleteRequired, errTaskCreateRequired, errTaskIdRequired,
    errTaskOrderNegative, errTaskOrderRequired, errTaskUpdateRequired, rpcError, rpcPass,
} from "../_shared/errors.ts";
import { hasTaskListAccess, rpc } from "../_shared/supabase.ts";
import { clientRequestIdOf, dueAtOf, personIdsOf, priorityOf } from "../_shared/validate.ts";

// GET /task (TaskIndex.php): task_list_id de body+query con precedencia del body
// (ControllerAbstract.php:31) — si llega → check estricto de pertenencia (TaskListUser::check →
// "Not Found") + filtro. `q` se ignora como en PHP (no hay filtro de búsqueda) — T3.
// 0037 (D-026): `priority` opcional filtra (inválida → 400) y `sort=priority` ordena alta > media >
// baja (desempate por order e id); otro `sort` se ignora. Sin ellos el payload RPC es el de siempre
// (la Edge funciona sobre la BD sin 0037). Kito (asistente, ver_tareas) llama aquí sin ninguno.
export const handleTask = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req); // body + $_GET con body primero: contractInput

    // TaskIndex.php:12-16: getInputInt('task_list_id') sobre body+query; truthy → M-check
    const taskListId = inputInt(input, "task_list_id");
    if (taskListId) {
        const allowed = await hasTaskListAccess(token, taskListId);
        if (!allowed) return errNotFound500();
    }

    // Task.php:79-81: getFilterInt — intval del valor truthy; 0 = sin filtro (como get_tasks)
    const priority = priorityOf(input);
    if (priority instanceof Response) return priority;
    const rawList = getInput(input, "task_list_id");
    const args: Record<string, unknown> = {
        p_dashboard: contractBoolOf(input, "dashboard"),
        p_task_list_id: contractEmpty(rawList) ? null : contractIntval(rawList),
        p_widget: contractBoolOf(input, "widget"),
    };
    if (priority !== undefined) args.p_priority = priority;
    if (getInput(input, "sort") === "priority") args.p_sort = "priority";
    const res = await rpc("get_tasks", args, token);
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
    // client_request_id opcional (0035): idempotencia del alta; el replay responde también 201.
    const clientRequestId = clientRequestIdOf(input);
    if (clientRequestId instanceof Response) return clientRequestId;
    // priority opcional (0037): ausente → la RPC guarda 'media'.
    const priority = priorityOf(input);
    if (priority instanceof Response) return priority;
    // person_ids opcional (tareas con personas, 0025): null = sin asignar.
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;
    const args: Record<string, unknown> = { p_task_list_id: taskListId, p_title: title, p_person_ids: personIds };
    if (clientRequestId !== undefined) args.p_client_request_id = clientRequestId;
    if (priority !== undefined) args.p_priority = priority;
    return rpcPass(await rpc("create_task", args, token), 201);
};

// PATCH /task/update (TaskUpdate.php): update + reorderByList
export const handleTaskUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    const title = inputString(input, "title");
    if (contractEmpty(id) || contractEmpty(title)) return errTaskUpdateRequired();
    // priority opcional (0037): ausente → se conserva la guardada.
    const priority = priorityOf(input);
    if (priority instanceof Response) return priority;
    // Sin person_ids no se tocan las personas; con array se sincronizan (0025).
    const personIds = await personIdsOf(input, token);
    if (personIds instanceof Response) return personIds;
    // due_at opcional (0041): ausente/null → no se toca; '' → se borra; fecha → se fija
    const dueAt = dueAtOf(input);
    if (dueAt instanceof Response) return dueAt;
    const args: Record<string, unknown> = { p_id: id, p_title: title, p_person_ids: personIds };
    if (priority !== undefined) args.p_priority = priority;
    // 0041: la fecha va en task_due_set (update_task no cambia de firma: la cadena de rollbacks depende de ella).
    // Las dos escrituras son idempotentes: si la segunda falla, reenviar la op la deja bien.
    const res = await rpc("update_task", args, token);
    if (!res.ok || dueAt === undefined) return rpcPass(res);
    const dueArgs = dueAt.clear ? { p_id: id, p_clear_due: true } : { p_id: id, p_due_at: dueAt.value };
    return rpcPass(await rpc("task_due_set", dueArgs, token));
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
