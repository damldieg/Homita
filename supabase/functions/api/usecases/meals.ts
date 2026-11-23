// /meal/* (0043, change menus-perfil-hogar; D-008 rutas aditivas): perfil de hogar del planificador
// de comidas. Casos de uso finos sobre las RPC get_meal_profile, update_meal_profile,
// update_meal_profile_member, set_meal_schedule y set_meal_slot_settings: la Edge solo comprueba la
// forma de la petición (objeto/array, id de miembro); permisos, hogar (X-Home-Id o regla de
// fn_home_for_root_create) y valores los valida la RPC. Errores por rpcPassHome: Not Found → 404,
// Not Allowed → 403, 'Invalid meal profile' / 'Invalid member' → 400.
import { contractBodyOnly, type ContractInput } from "../_shared/contract.ts";
import { errHomeMemberIdRequired, errInvalidMealProfile, rpcPassHome } from "../_shared/errors.ts";
import { rpc } from "../_shared/supabase.ts";

const isIntId = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v > 0;

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
