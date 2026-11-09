// /home/* (R1–R6 del plan 1.4 §2; servicios §4.3 sobre las RPC de 0016). Contrato nuevo sin
// oráculo PHP (A8): mensajes en inglés, mismo estilo que las legacy. La validación de entrada va
// antes de la RPC y sigue el orden id → name → timezone (§4.3); la RPC repite la barrera de
// autorización (cabecera ≠ id → Not Found; permisos → Not Allowed). Errores mapeados por
// rpcPassHome: Not Found → 404 (D16), Not Allowed → 403, validación → 400.
import { getInput, inputInt, inputString, inputTimezone, phpEmpty, phpInput } from "../_shared/contract.ts";
import {
    errHomeIdRequired, errInvalidTimezone, errNameRequired, rpcPassHome,
} from "../_shared/errors.ts";
import { rpc } from "../_shared/supabase.ts";

// R1: GET /home — mis hogares (get_homes filtra archived; la cabecera solo se valida en dispatch)
export const handleHomeIndex = async (_req: Request, token: string): Promise<Response> =>
    rpcPassHome(await rpc("get_homes", {}, token));

// R2: POST /home/create {name (req), timezone (opt, default Europe/Madrid, A5)} → 201
export const handleHomeCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const nameRaw = inputString(input, "name");
    const name = nameRaw === null ? null : nameRaw.trim();  // R1-02: "   " → 400 Name is required
    if (phpEmpty(name)) return errNameRequired();
    let timezone = "Europe/Madrid";  // R1-02: default A5 aunque inputTimezone lo daría 'UTC'
    const tzRaw = getInput(input, "timezone");
    if (tzRaw !== null && tzRaw !== undefined) {
        const v = inputTimezone({ timezone: tzRaw });
        if (v === "INVALID") return errInvalidTimezone();
        timezone = v;
    }
    return rpcPassHome(await rpc("create_home", { p_name: name, p_timezone: timezone }, token), 201);
};

// R3: GET /home/detail?id= — cabecera ≠ id y no miembro → 404; sin home.view → 403
export const handleHomeDetail = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errHomeIdRequired();
    return rpcPassHome(await rpc("get_home_detail", { p_home_id: id }, token));
};

// R4: PATCH /home/update {id (req), name (req), timezone (opt)} — R1-02: timezone omitido o null
// → p_timezone null (la RPC conserva la zona actual con coalesce)
export const handleHomeUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    const nameRaw = inputString(input, "name");
    const name = nameRaw === null ? null : nameRaw.trim();
    if (phpEmpty(id)) return errHomeIdRequired();
    if (phpEmpty(name)) return errNameRequired();
    let timezone: string | null = null;
    const tzRaw = getInput(input, "timezone");
    if (tzRaw !== null && tzRaw !== undefined) {
        const v = inputTimezone({ timezone: tzRaw });
        if (v === "INVALID") return errInvalidTimezone();
        timezone = v;
    }
    return rpcPassHome(await rpc("update_home", { p_home_id: id, p_name: name, p_timezone: timezone }, token));
};

// R5: PATCH /home/default {home_id (req)} → {"default_home_id": <id>} (A3)
export const handleHomeDefault = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const homeId = inputInt(input, "home_id");
    if (phpEmpty(homeId)) return errHomeIdRequired();
    return rpcPassHome(await rpc("set_default_home", { p_home_id: homeId }, token));
};

// R6: GET /home/membership?id= — cuentas del hogar con permisos efectivos (A4: admin = catálogo)
export const handleHomeMembership = async (req: Request, token: string): Promise<Response> => {
    const input = await phpInput(req);
    const id = inputInt(input, "id");
    if (phpEmpty(id)) return errHomeIdRequired();
    return rpcPassHome(await rpc("get_home_memberships", { p_home_id: id }, token));
};
