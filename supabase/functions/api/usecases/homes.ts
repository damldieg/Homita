// /home/* (R1–R6 del plan 1.4 §2; servicios §4.3 sobre las RPC de 0016). Contrato nuevo sin
// oráculo PHP (A8): mensajes en inglés, mismo estilo que las legacy. La validación de entrada va
// antes de la RPC y sigue el orden id → name → timezone (§4.3); la RPC repite la barrera de
// autorización (cabecera ≠ id → Not Found; permisos → Not Allowed). Errores mapeados por
// rpcPassHome: Not Found → 404 (D16), Not Allowed → 403, validación → 400.
import { getInput, inputInt, inputString, inputTimezone, contractEmpty, contractInput, type ContractInput } from "../_shared/contract.ts";
import {
    error, errHomeIdRequired, errHomeMemberIdRequired, errHomeMembershipIdRequired,
    errInvalidPermission, errInvalidRole, errInvalidTimezone, errInvitationCodeRequired,
    errInvitationIdRequired, errNameRequired, errPersonColorInvalid, errPersonNameRequired,
    errRouteHomeNotFound, rpcPassHome,
} from "../_shared/errors.ts";
import { rpc } from "../_shared/supabase.ts";

// 'Invalid member' ya está en RPC_STATUS (errors.ts); aquí se emite en el rechazo de tipos de la
// Edge sin llamar a la RPC (§6.1), con el mismo texto que la validación de kind/status en SQL
const errInvalidMember = (): Response => error("Invalid member", 400);

// Regla de tipos de 1.5 §6.1 (R1-04): clave ausente o JSON null → null (sin cambio en PATCH);
// valor presente no-string → 400 del campo sin llamar a la RPC; string (incluida '') → tal cual
// (la RPC valida: fuente única fn_validate_person_fields).
const optStr = (input: ContractInput, key: string, bad: () => Response): string | null | Response => {
    const raw = getInput(input, key);
    if (raw === null || raw === undefined) return null;
    return typeof raw === "string" ? raw : bad();
};

// R1: GET /home — mis hogares (get_homes filtra archived; la cabecera solo se valida en dispatch)
export const handleHomeIndex = async (_req: Request, token: string): Promise<Response> =>
    rpcPassHome(await rpc("get_homes", {}, token));

// R2: POST /home/create {name (req), timezone (opt, default Europe/Madrid, A5)} → 201
export const handleHomeCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const nameRaw = inputString(input, "name");
    const name = nameRaw === null ? null : nameRaw.trim();  // R1-02: "   " → 400 Name is required
    if (contractEmpty(name)) return errNameRequired();
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
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    if (contractEmpty(id)) return errHomeIdRequired();
    return rpcPassHome(await rpc("get_home_detail", { p_home_id: id }, token));
};

// R4: PATCH /home/update {id (req), name (req), timezone (opt)} — R1-02: timezone omitido o null
// → p_timezone null (la RPC conserva la zona actual con coalesce)
export const handleHomeUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    const nameRaw = inputString(input, "name");
    const name = nameRaw === null ? null : nameRaw.trim();
    if (contractEmpty(id)) return errHomeIdRequired();
    if (contractEmpty(name)) return errNameRequired();
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
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    return rpcPassHome(await rpc("set_default_home", { p_home_id: homeId }, token));
};

// R6: GET /home/membership?id= — cuentas del hogar con permisos efectivos (A4: admin = catálogo)
export const handleHomeMembership = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    if (contractEmpty(id)) return errHomeIdRequired();
    return rpcPassHome(await rpc("get_home_memberships", { p_home_id: id }, token));
};

// M1 (1.5 §6.1): GET /home/member?home_id= — miembros del hogar (kind, status, linked);
// home_id explícito (Q3a: en PATCH /home/member/update `id` es el id de miembro)
export const handleHomeMemberIndex = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    return rpcPassHome(await rpc("get_home_members", { p_home_id: homeId }, token));
};

// M2: POST /home/member/create {home_id, kind, name (req), color (opt, default en la RPC)} → 201
export const handleHomeMemberCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const kind = optStr(input, "kind", errInvalidMember);
    if (kind instanceof Response) return kind;
    if (kind === null) return errInvalidMember();  // POST: kind ausente → Invalid member
    const name = optStr(input, "name", errPersonNameRequired);
    if (name instanceof Response) return name;
    if (name === null) return errPersonNameRequired();  // POST: name ausente → Name is required…
    const color = optStr(input, "color", errPersonColorInvalid);
    if (color instanceof Response) return color;
    return rpcPassHome(await rpc("create_home_member", {
        p_home_id: homeId, p_kind: kind, p_name: name, p_color: color,
    }, token), 201);
};

// M3: PATCH /home/member/update {id (req, id de miembro), kind/name/color/status (opt)} → 200
export const handleHomeMemberUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    if (contractEmpty(id)) return errHomeMemberIdRequired();
    const kind = optStr(input, "kind", errInvalidMember);
    if (kind instanceof Response) return kind;
    const status = optStr(input, "status", errInvalidMember);
    if (status instanceof Response) return status;
    const name = optStr(input, "name", errPersonNameRequired);
    if (name instanceof Response) return name;
    const color = optStr(input, "color", errPersonColorInvalid);
    if (color instanceof Response) return color;
    return rpcPassHome(await rpc("update_home_member", {
        p_id: id, p_kind: kind, p_name: name, p_color: color, p_status: status,
    }, token));
};

// M4 (1.6 §6.1): PATCH /home/membership/role {home_id, membership_id, role (req, admin|member)} →
// 200 MEMBERSHIP_STATE. Validación antes de la RPC: ids → 400 del campo; role ausente, no string o
// fuera de admin/member → 'Invalid role' 400 (la RPC repite la barrera con coalesce null-safe).
export const handleHomeMembershipRole = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const membershipId = inputInt(input, "membership_id");
    if (contractEmpty(membershipId)) return errHomeMembershipIdRequired();
    const roleRaw = getInput(input, "role");
    if (roleRaw !== "admin" && roleRaw !== "member") return errInvalidRole();
    return rpcPassHome(await rpc("set_home_membership_role", {
        p_home_id: homeId, p_membership_id: membershipId, p_role: roleRaw,
    }, token));
};

// M5: POST /home/membership/transfer {home_id, to_membership_id (req)} → 200 (atómico, §3.3 del
// diseño; el caller queda member). A-1: la Edge parsea body en POST/DELETE igual que php://input.
export const handleHomeMembershipTransfer = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const toMembershipId = inputInt(input, "to_membership_id");
    if (contractEmpty(toMembershipId)) return errHomeMembershipIdRequired();
    return rpcPassHome(await rpc("transfer_home_admin", {
        p_home_id: homeId, p_to_membership_id: toMembershipId,
    }, token));
};

// M6: DELETE /home/membership {home_id, membership_id (req)} → 200 SUCCESS (salir o expulsar;
// A-1: contractInput parsea body en DELETE, como DELETE /calendar/user)
export const handleHomeMembershipRemove = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const membershipId = inputInt(input, "membership_id");
    if (contractEmpty(membershipId)) return errHomeMembershipIdRequired();
    return rpcPassHome(await rpc("remove_home_membership", {
        p_home_id: homeId, p_membership_id: membershipId,
    }, token));
};

// P1 (1.9 §4.2): GET /home/permission?home_id= — catálogo + defaults por kind (BD) + permisos
// efectivos por membresía con flag editable. La RPC repite la barrera (cabecera ≠ home_id o no
// miembro → Not Found; sin home.view → Not Allowed).
export const handleHomePermissionIndex = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    return rpcPassHome(await rpc("get_home_permissions", { p_home_id: homeId }, token));
};

// P2: PATCH /home/permission {home_id, membership_id, permissions:[codes]} — set completo
// idempotente (Q2); el servidor calcula el delta. permissions ausente, no array o con elemento
// no string → 'Invalid permission' sin llamar a la RPC (la RPC repite la barrera: códigos fuera
// del catálogo, shape, target admin → Not Allowed, membresía ajena → Not Found).
export const handleHomePermissionUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const membershipId = inputInt(input, "membership_id");
    if (contractEmpty(membershipId)) return errHomeMembershipIdRequired();
    const permissions = getInput(input, "permissions");
    if (!Array.isArray(permissions) || permissions.some((c) => typeof c !== "string")) {
        return errInvalidPermission();
    }
    return rpcPassHome(await rpc("set_home_permissions", {
        p_home_id: homeId, p_membership_id: membershipId, p_permissions: permissions,
    }, token));
};

// A1: GET /home/audit?home_id=&limit=&before_id= — auditoría admin-only del hogar (solo acciones
// home.*, R1-01). limit/before_id opcionales: ausentes o no numéricos → null (la RPC aplica
// default 50, clamp 1..200 y paginación por id desc con before_id).
export const handleHomeAudit = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const limit = inputInt(input, "limit");
    const beforeId = inputInt(input, "before_id");
    return rpcPassHome(await rpc("get_home_audit", {
        p_home_id: homeId, p_limit: limit, p_before_id: beforeId,
    }, token));
};

// I1 (1.15, diseño §5.2): GET /home/invitation?home_id= — invitaciones pendientes no caducadas
// (home.invite; cabecera ≠ home_id o no miembro → 404). Nunca devuelve el código ni su hash.
export const handleHomeInvitationIndex = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    return rpcPassHome(await rpc("get_home_invitations", { p_home_id: homeId }, token));
};

// I2: POST /home/invitation/create {home_id, kind?, member_id?} → 201 INVITATION_CREATED (el
// código en claro sale solo aquí, una vez). kind/member_id ausentes o null → null; kind no
// string o member_id no entero → 'Invalid member' sin llamar a la RPC (la RPC valida el resto:
// pet, ambos nulos, miembro ajeno/vinculado/inactivo; D-017: adult solo admin → 403).
export const handleHomeInvitationCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const kind = optStr(input, "kind", errInvalidMember);
    if (kind instanceof Response) return kind;
    const memberRaw = getInput(input, "member_id");
    let memberId: number | null = null;
    if (memberRaw !== null && memberRaw !== undefined) {
        memberId = inputInt(input, "member_id");
        if (memberId === null) return errInvalidMember();
    }
    return rpcPassHome(await rpc("create_home_invitation", {
        p_home_id: homeId, p_kind: kind, p_member_id: memberId,
    }, token), 201);
};

// I3: POST /home/invitation/accept {code} → 200 INVITATION_ACCEPTED. Ruta sin contexto de hogar
// (D-015, `homeContext: false` en index.ts): el usuario aún no es miembro y el hogar lo indica el
// código. code ausente, no string o vacío → 400; presente pero mal formado → el mismo 404 que la
// RPC (sin oráculo y sin llamarla). El código nunca se registra en logs.
// R1-01 (review 1.15): `code` SOLO del body JSON. No se usa contractInput (mezcla el query string): un
// `?code=` acabaría en logs de URL (proxy, plataforma). Con el código solo en la query → 400.
export const handleHomeInvitationAccept = async (req: Request, token: string): Promise<Response> => {
    const rawBody = await req.text().catch(() => "");
    let body: unknown = null;
    try {
        body = rawBody ? JSON.parse(rawBody) : null;
    } catch {
        body = null;
    }
    const raw = body !== null && typeof body === "object" && !Array.isArray(body)
        ? (body as Record<string, unknown>).code
        : undefined;
    if (typeof raw !== "string" || raw.trim() === "") return errInvitationCodeRequired();
    const code = raw.trim().toLowerCase();
    if (!/^[0-9a-f]{32}$/.test(code)) return errRouteHomeNotFound();
    return rpcPassHome(await rpc("accept_home_invitation", { p_code: code }, token));
};

// I4: POST /home/invitation/revoke {home_id, id} → 200 INVITATION_ITEM (status revoked); otro
// hogar, ya no pendiente o caducada → 404; sin home.invite → 403.
export const handleHomeInvitationRevoke = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const homeId = inputInt(input, "home_id");
    if (contractEmpty(homeId)) return errHomeIdRequired();
    const id = inputInt(input, "id");
    if (contractEmpty(id)) return errInvitationIdRequired();
    return rpcPassHome(await rpc("revoke_home_invitation", { p_home_id: homeId, p_id: id }, token));
};
