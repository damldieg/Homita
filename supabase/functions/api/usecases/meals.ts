// /meal/* (0043, change menus-perfil-hogar; D-008 rutas aditivas): perfil de hogar del planificador
// de comidas. Casos de uso finos sobre las RPC get_meal_profile, update_meal_profile,
// update_meal_profile_member, set_meal_schedule y set_meal_slot_settings: la Edge solo comprueba la
// forma de la petición (objeto/array, id de miembro); permisos, hogar (X-Home-Id o regla de
// fn_home_for_root_create) y valores los valida la RPC. Errores por rpcPassHome: Not Found → 404,
// Not Allowed → 403, 'Invalid meal profile' / 'Invalid member' → 400.
import { contractBodyOnly, type ContractInput } from "../_shared/contract.ts";
import {
    errHomeMemberIdRequired, errInvalidMealPlan, errInvalidMealProfile, errMealPlanIdRequired, rpcPassHome,
} from "../_shared/errors.ts";
import { rpc } from "../_shared/supabase.ts";
import { clientRequestIdOf } from "../_shared/validate.ts";

const isIntId = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v > 0 && v <= Number.MAX_SAFE_INTEGER;

// GET /meal/profile — perfil, franjas, fichas de quienes comen y horario del hogar
export const handleMealProfileGet = async (_req: Request, token: string): Promise<Response> =>
    rpcPassHome(await rpc("get_meal_profile", {}, token));

// PATCH /meal/profile {week_start_day, shopping_day, cook_minutes_*, equipment, … preferences}
export const handleMealProfileUpdate = async (req: Request, token: string): Promise<Response> => {
    const data = await contractBodyOnly(req);
    return rpcPassHome(await rpc("update_meal_profile", { p_data: data }, token));
};

// PATCH /meal/profile/member {home_member_id (req), …campos de la ficha; eats:false la borra}
export const handleMealProfileMemberUpdate = async (req: Request, token: string): Promise<Response> => {
    const { home_member_id: memberId, ...data }: ContractInput = await contractBodyOnly(req);
    if (!isIntId(memberId)) return errHomeMemberIdRequired();
    return rpcPassHome(await rpc("update_meal_profile_member", { p_member_id: memberId, p_data: data }, token));
};

// PUT /meal/schedule {entries: [{home_member_id, weekday, slot, status}]}
export const handleMealScheduleSet = async (req: Request, token: string): Promise<Response> => {
    const { entries } = await contractBodyOnly(req);
    if (!Array.isArray(entries)) return errInvalidMealProfile();
    return rpcPassHome(await rpc("set_meal_schedule", { p_entries: entries }, token));
};

// PUT /meal/slots {slots: [{slot, enabled?, time?}]}
export const handleMealSlotsSet = async (req: Request, token: string): Promise<Response> => {
    const { slots } = await contractBodyOnly(req);
    if (!Array.isArray(slots)) return errInvalidMealProfile();
    return rpcPassHome(await rpc("set_meal_slot_settings", { p_slots: slots }, token));
};

// ── menú semanal (0044, change menus-semana) ──
// /meal/plan*, /meal/today: get_meal_plan, upsert_meal_plan_items, accept/archive/copy_meal_plan*,
// check_meal_plan y get_meals_today. La Edge valida la forma (fechas YYYY-MM-DD, enteros, arrays);
// revisión, permisos y valores los valida la RPC. Errores por rpcPassHome: 'Stale meal plan
// revision' y 'Meal plan exists' → 409, 'Invalid meal plan' → 400, Not Found → 404.
const isDate = (v: unknown): v is string => {
    if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return false;
    const d = new Date(`${v}T00:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
};

const queryParam = (req: Request, key: string): string | null => new URL(req.url).searchParams.get(key);

// Entero >= 0 que cabe en un `integer` de Postgres (expected_revision): sin tope, 1e12 llegaría a la RPC
// como parámetro tipado y el error de cast saldría como 500.
const isNonNegInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 2147483647;

// GET /meal/plan?week_start=YYYY-MM-DD — plan completo o null si no hay
export const handleMealPlanGet = async (req: Request, token: string): Promise<Response> => {
    const weekStart = queryParam(req, "week_start");
    if (!isDate(weekStart)) return errInvalidMealPlan();
    return rpcPassHome(await rpc("get_meal_plan", { p_week_start: weekStart }, token));
};

// PATCH /meal/plan/items {week_start, expected_revision, items?: [...], delete_ids?: [id], client_request_id?, origin?}
// (0048: client_request_id hace el reintento idempotente; origin 'user' | 'kito', lo valida la RPC; con 'kito' la
// RPC no edita un plan aceptado ni toca casillas locked. El `state` de cada casilla también lo valida la RPC.)
export const handleMealPlanItems = async (req: Request, token: string): Promise<Response> => {
    const b = await contractBodyOnly(req);
    if (!isDate(b.week_start) || !isNonNegInt(b.expected_revision)) return errInvalidMealPlan();
    if (b.items !== undefined && b.items !== null && !Array.isArray(b.items)) return errInvalidMealPlan();
    if (b.delete_ids !== undefined && b.delete_ids !== null && !(Array.isArray(b.delete_ids) && b.delete_ids.every(isIntId))) {
        return errInvalidMealPlan();
    }
    const clientRequestId = clientRequestIdOf(b);
    if (clientRequestId instanceof Response) return clientRequestId;
    if (b.origin !== undefined && b.origin !== null && typeof b.origin !== "string") return errInvalidMealPlan();
    const args: Record<string, unknown> = { p_week_start: b.week_start, p_expected_revision: b.expected_revision };
    if (b.items !== undefined) args.p_items = b.items;
    if (b.delete_ids !== undefined) args.p_delete_ids = b.delete_ids;
    if (clientRequestId !== undefined) args.p_client_request_id = clientRequestId;
    if (typeof b.origin === "string") args.p_origin = b.origin;
    return rpcPassHome(await rpc("upsert_meal_plan_items", args, token));
};

// POST /meal/plan/accept {plan_id, expected_revision}
export const handleMealPlanAccept = async (req: Request, token: string): Promise<Response> => {
    const b = await contractBodyOnly(req);
    if (!isIntId(b.plan_id)) return errMealPlanIdRequired();
    if (!isNonNegInt(b.expected_revision)) return errInvalidMealPlan();
    return rpcPassHome(await rpc("accept_meal_plan", { p_plan_id: b.plan_id, p_expected_revision: b.expected_revision }, token));
};

// POST /meal/plan/archive {plan_id, expected_revision?} — con expected_revision, 409 si el plan cambió
export const handleMealPlanArchive = async (req: Request, token: string): Promise<Response> => {
    const b = await contractBodyOnly(req);
    if (!isIntId(b.plan_id)) return errMealPlanIdRequired();
    const args: Record<string, unknown> = { p_plan_id: b.plan_id };
    if (b.expected_revision !== undefined && b.expected_revision !== null) {
        if (!isNonNegInt(b.expected_revision)) return errInvalidMealPlan();
        args.p_expected_revision = b.expected_revision;
    }
    return rpcPassHome(await rpc("archive_meal_plan", args, token));
};

// POST /meal/plan/copy {from_week, to_week}
export const handleMealPlanCopy = async (req: Request, token: string): Promise<Response> => {
    const b = await contractBodyOnly(req);
    if (!isDate(b.from_week) || !isDate(b.to_week)) return errInvalidMealPlan();
    return rpcPassHome(await rpc("copy_meal_plan_week", { p_from_week: b.from_week, p_to_week: b.to_week }, token), 201);
};

// GET /meal/plan/check?plan_id=
export const handleMealPlanCheck = async (req: Request, token: string): Promise<Response> => {
    const raw = queryParam(req, "plan_id");
    if (raw === null || !/^[0-9]+$/.test(raw) || Number(raw) <= 0) return errMealPlanIdRequired();
    return rpcPassHome(await rpc("check_meal_plan", { p_plan_id: Number(raw) }, token));
};

// GET /meal/today?date=YYYY-MM-DD — sin date, hoy en la zona del hogar
export const handleMealToday = async (req: Request, token: string): Promise<Response> => {
    const date = queryParam(req, "date");
    if (date !== null && !isDate(date)) return errInvalidMealPlan();
    return rpcPassHome(await rpc("get_meals_today", date === null ? {} : { p_date: date }, token));
};
