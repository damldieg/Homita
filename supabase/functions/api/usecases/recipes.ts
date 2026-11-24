// /recipe* y /food* (0044, change menus-semana; D-008 rutas aditivas): recetas y catálogo de
// alimentos. Casos de uso finos sobre las RPC search_food, create/update/delete_food, list_recipes,
// get_recipe y create/update/delete_recipe: la Edge solo comprueba la forma (ids enteros, tipos de
// los campos opcionales); permisos, hogar (X-Home-Id o fn_home_for_root_create) y valores los valida
// la RPC. Errores por rpcPassHome: Not Found → 404, Not Allowed → 403, Invalid recipe|food → 400.
import { contractBodyOnly, contractInput, inputInt, inputString } from "../_shared/contract.ts";
import {
    errFoodIdRequired, errInvalidFood, errInvalidRecipe, errRecipeIdRequired, rpcPassHome,
} from "../_shared/errors.ts";
import { rpc } from "../_shared/supabase.ts";

const isIntId = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v > 0;

// id por query string o body (DELETE y PATCH); ausente o no entero positivo → null
const queryId = (req: Request, key = "id"): number | null => {
    const raw = new URL(req.url).searchParams.get(key);
    return raw !== null && /^[0-9]+$/.test(raw) && Number(raw) > 0 ? Number(raw) : null;
};

const isStringArray = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === "string");

// ── catálogo de alimentos ──

// GET /food?q=&limit= — común + del hogar por nombre normalizado
export const handleFoodSearch = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const args: Record<string, unknown> = {};
    const q = inputString(input, "q");
    if (q !== null) args.p_q = q;
    const limit = inputInt(input, "limit");
    if (limit !== null) args.p_limit = limit;
    return rpcPassHome(await rpc("search_food", args, token));
};

// POST /food/create {name, section?, allergens?, default_unit?, grams_per_unit?}
export const handleFoodCreate = async (req: Request, token: string): Promise<Response> => {
    const b = await contractBodyOnly(req);
    if (typeof b.name !== "string") return errInvalidFood();
    const args: Record<string, unknown> = { p_name: b.name };
    if (b.section !== undefined) args.p_section = b.section;
    if (b.allergens !== undefined) {
        if (b.allergens !== null && !isStringArray(b.allergens)) return errInvalidFood();
        args.p_allergens = b.allergens;
    }
    if (b.default_unit !== undefined) args.p_default_unit = b.default_unit;
    if (b.grams_per_unit !== undefined) args.p_grams_per_unit = b.grams_per_unit;
    return rpcPassHome(await rpc("create_food", args, token), 201);
};

// PATCH /food/update {id, …campos a cambiar}
export const handleFoodUpdate = async (req: Request, token: string): Promise<Response> => {
    const { id, ...data } = await contractBodyOnly(req);
    if (!isIntId(id)) return errFoodIdRequired();
    return rpcPassHome(await rpc("update_food", { p_id: id, p_data: data }, token));
};

// DELETE /food/delete?id= (o body {id})
export const handleFoodDelete = async (req: Request, token: string): Promise<Response> => {
    const id = queryId(req) ?? inputInt(await contractBodyOnly(req), "id");
    if (id === null || !isIntId(id)) return errFoodIdRequired();
    return rpcPassHome(await rpc("delete_food", { p_id: id }, token));
};

// ── recetas ──

// GET /recipe?q=&slot=&max_minutes=
export const handleRecipeIndex = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const args: Record<string, unknown> = {};
    const q = inputString(input, "q");
    if (q !== null) args.p_q = q;
    const slot = inputString(input, "slot");
    if (slot !== null) args.p_slot = slot;
    if (input.max_minutes !== undefined) {
        const m = inputInt(input, "max_minutes");
        if (m === null) return errInvalidRecipe();
        args.p_max_minutes = m;
    }
    return rpcPassHome(await rpc("list_recipes", args, token));
};

// GET /recipe/detail?id=
export const handleRecipeDetail = async (req: Request, token: string): Promise<Response> => {
    const id = inputInt(await contractInput(req), "id");
    if (id === null || !isIntId(id)) return errRecipeIdRequired();
    return rpcPassHome(await rpc("get_recipe", { p_id: id }, token));
};

// POST /recipe/create {name, servings?, minutes?, slots?, steps?, ingredients?}
export const handleRecipeCreate = async (req: Request, token: string): Promise<Response> => {
    const b = await contractBodyOnly(req);
    if (typeof b.name !== "string") return errInvalidRecipe();
    for (const k of ["slots", "steps"] as const) {
        if (b[k] !== undefined && b[k] !== null && !isStringArray(b[k])) return errInvalidRecipe();
    }
    if (b.ingredients !== undefined && b.ingredients !== null && !Array.isArray(b.ingredients)) {
        return errInvalidRecipe();
    }
    const args: Record<string, unknown> = { p_name: b.name };
    if (b.servings !== undefined) args.p_servings = b.servings;
    if (b.minutes !== undefined) args.p_minutes = b.minutes;
    if (b.slots !== undefined) args.p_slots = b.slots;
    if (b.steps !== undefined) args.p_steps = b.steps;
    if (b.ingredients !== undefined) args.p_ingredients = b.ingredients;
    return rpcPassHome(await rpc("create_recipe", args, token), 201);
};

// PATCH /recipe/update {id, …campos; ingredients reemplaza la lista completa}
export const handleRecipeUpdate = async (req: Request, token: string): Promise<Response> => {
    const { id, ...data } = await contractBodyOnly(req);
    if (!isIntId(id)) return errRecipeIdRequired();
    if (data.ingredients !== undefined && data.ingredients !== null && !Array.isArray(data.ingredients)) {
        return errInvalidRecipe();
    }
    return rpcPassHome(await rpc("update_recipe", { p_id: id, p_data: data }, token));
};

// DELETE /recipe/delete?id= (o body {id})
export const handleRecipeDelete = async (req: Request, token: string): Promise<Response> => {
    const id = queryId(req) ?? inputInt(await contractBodyOnly(req), "id");
    if (id === null || !isIntId(id)) return errRecipeIdRequired();
    return rpcPassHome(await rpc("delete_recipe", { p_id: id }, token));
};
