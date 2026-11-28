// /shopping* (0045, change menus-compra; D-008 rutas aditivas): la Compra del hogar, sincronizada con el
// menú aceptado. Casos de uso finos sobre las RPC list_shopping, preview_meal_shopping, sync_meal_shopping,
// create_shopping_item, set_shopping_item_state, update_shopping_item_qty, delete_shopping_item y
// clear_checked_shopping: la Edge solo comprueba la forma (ids enteros, estado, client_request_id);
// permisos (menu.view lee, menu.shopping.edit escribe), hogar (X-Home-Id o fn_home_for_root_create) y valores
// los valida la RPC. Errores por rpcPassHome: Not Found → 404, Not Allowed → 403, Invalid shopping item |
// Invalid meal plan | Invalid client_request_id → 400.
import { contractBodyOnly } from "../_shared/contract.ts";
import {
    errInvalidShoppingItem, errMealPlanIdRequired, errShoppingItemIdRequired, rpcPassHome,
} from "../_shared/errors.ts";
import { rpc } from "../_shared/supabase.ts";
import { clientRequestIdOf } from "../_shared/validate.ts";

const isIntId = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v > 0 && v <= Number.MAX_SAFE_INTEGER;
const isOptNumber = (v: unknown): boolean => v === null || (typeof v === "number" && Number.isFinite(v));
const isOptString = (v: unknown): boolean => v === null || typeof v === "string";

// id positivo por query string; ausente o no entero positivo → null
const queryId = (req: Request, key: string): number | null => {
    const raw = new URL(req.url).searchParams.get(key);
    return raw !== null && /^[0-9]+$/.test(raw) && Number(raw) > 0 && Number(raw) <= Number.MAX_SAFE_INTEGER
        ? Number(raw)
        : null;
};

// GET /shopping — {revision, items} del hogar (sin los ocultos)
export const handleShoppingList = async (_req: Request, token: string): Promise<Response> =>
    rpcPassHome(await rpc("list_shopping", {}, token));

// GET /shopping/preview?plan_id= — lo que entraría en la compra desde el plan (solo lectura)
export const handleShoppingPreview = async (req: Request, token: string): Promise<Response> => {
    const planId = queryId(req, "plan_id");
    if (planId === null) return errMealPlanIdRequired();
    return rpcPassHome(await rpc("preview_meal_shopping", { p_plan_id: planId }, token));
};

// POST /shopping/sync {plan_id, client_request_id?} → {added, updated, removed}
export const handleShoppingSync = async (req: Request, token: string): Promise<Response> => {
    const input = await contractBodyOnly(req);
    if (!isIntId(input.plan_id)) return errMealPlanIdRequired();
    const clientRequestId = clientRequestIdOf(input);
    if (clientRequestId instanceof Response) return clientRequestId;
    const args: Record<string, unknown> = { p_plan_id: input.plan_id };
    if (clientRequestId !== undefined) args.p_client_request_id = clientRequestId;
    return rpcPassHome(await rpc("sync_meal_shopping", args, token));
};

// POST /shopping/item/create {label?, quantity?, unit?, section?, food_id?, client_request_id?} — 201 también en replay
export const handleShoppingItemCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractBodyOnly(req);
    if (!isOptString(input.label ?? null) || !isOptNumber(input.quantity ?? null) || !isOptString(input.unit ?? null)
        || !isOptString(input.section ?? null) || !(input.food_id == null || isIntId(input.food_id))) {
        return errInvalidShoppingItem();
    }
    // con food_id el label es opcional (toma el nombre del alimento); sin él, la RPC exige label
    if (input.label == null && input.food_id == null) return errInvalidShoppingItem();
    const clientRequestId = clientRequestIdOf(input);
    if (clientRequestId instanceof Response) return clientRequestId;
    const args: Record<string, unknown> = { p_label: input.label ?? null };
    if (input.quantity != null) args.p_quantity = input.quantity;
    if (input.unit != null) args.p_unit = input.unit;
    if (input.section != null) args.p_section = input.section;
    if (input.food_id != null) args.p_food_id = input.food_id;
    if (clientRequestId !== undefined) args.p_client_request_id = clientRequestId;
    return rpcPassHome(await rpc("create_shopping_item", args, token), 201);
};

// PATCH /shopping/item/check {id, state: pending|checked|skipped} — marca, desmarca o «ya lo tengo»
// PATCH /shopping/item/check {id, state, client_request_id?} (0055): la pantalla puede pasar pending ↔ checked; con
// client_request_id, un reenvío de la cola sin red no repite el cambio.
export const handleShoppingItemCheck = async (req: Request, token: string): Promise<Response> => {
    const input = await contractBodyOnly(req);
    if (!isIntId(input.id)) return errShoppingItemIdRequired();
    if (typeof input.state !== "string") return errInvalidShoppingItem();
    const clientRequestId = clientRequestIdOf(input);
    if (clientRequestId instanceof Response) return clientRequestId;
    const args: Record<string, unknown> = { p_item_id: input.id, p_state: input.state };
    if (clientRequestId !== undefined) args.p_client_request_id = clientRequestId;
    return rpcPassHome(await rpc("set_shopping_item_state", args, token));
};

// PATCH /shopping/item/update {id, quantity, unit?} — la cantidad editada deja de sincronizarse
export const handleShoppingItemQty = async (req: Request, token: string): Promise<Response> => {
    const input = await contractBodyOnly(req);
    if (!isIntId(input.id)) return errShoppingItemIdRequired();
    if (typeof input.quantity !== "number" || !Number.isFinite(input.quantity) || !isOptString(input.unit ?? null)) {
        return errInvalidShoppingItem();
    }
    const args: Record<string, unknown> = { p_item_id: input.id, p_quantity: input.quantity };
    if (input.unit != null) args.p_unit = input.unit;
    return rpcPassHome(await rpc("update_shopping_item_qty", args, token));
};

// DELETE /shopping/item/delete?id= (o body {id}) — manual: se borra; de origen menu: «ya lo tengo» y oculto
export const handleShoppingItemDelete = async (req: Request, token: string): Promise<Response> => {
    const id = queryId(req, "id") ?? (await contractBodyOnly(req)).id;
    if (!isIntId(id)) return errShoppingItemIdRequired();
    return rpcPassHome(await rpc("delete_shopping_item", { p_item_id: id }, token));
};

// DELETE /shopping/checked — vacía solo los comprados (checked); devuelve {cleared}
export const handleShoppingClearChecked = async (_req: Request, token: string): Promise<Response> =>
    rpcPassHome(await rpc("clear_checked_shopping", {}, token));
