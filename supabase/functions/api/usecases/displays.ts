// /home/display/* y /display/config (0049, dashboard-pantalla-hogar). Rutas nuevas (D-008): la pantalla del
// hogar es una cuenta técnica (app_user propio, sin contraseña conocida) con permisos de solo lectura.
// Vinculación sin sesión: link-start (código de 6 dígitos + secreto de sondeo), link-confirm desde el móvil
// (admin o quien gestiona calendarios, con X-Home-Id), link-poll desde la pantalla hasta recibir su sesión.
// La selección de calendarios y listas se refleja en calendar_user / task_list_user, así que los GET de
// eventos y tareas con dashboard=true no cambian para la pantalla.
import { contractInput, contractEmpty, inputString, inputInt, getInput, json, type ContractInput } from "../_shared/contract.ts";
import { error, errHomeIdRequired, errNameRequired, rpcError, rpcPassHome } from "../_shared/errors.ts";
import { currentHome } from "../_shared/home.ts";
import { adminCreateUser, adminDeleteUser, passwordGrant, rpc, serviceRpc } from "../_shared/supabase.ts";

// Contraseña y correo de la cuenta técnica: aleatorios, la contraseña no se guarda en ningún sitio.
const randomHex = (bytes: number): string =>
    Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (b) => b.toString(16).padStart(2, "0")).join("");

const RPC_ERRORS = (body: unknown): Response => rpcError(body);

// Limpieza de una vinculación a medias: borra la cuenta de GoTrue y la vinculación (best effort).
const abortLink = async (linkId: number, uid: string | null): Promise<void> => {
    if (uid !== null) await adminDeleteUser(uid).catch(() => undefined);
    await serviceRpc("fn_display_link_abort", { p_link_id: linkId }).catch(() => undefined);
};

// POST /home/display/link-start (público): código y secreto de sondeo. Ambos se muestran una vez.
export const handleDisplayLinkStart = async (): Promise<Response> => {
    const res = await serviceRpc("fn_display_link_start", {});
    const body = await res.json().catch(() => null);
    if (!res.ok) return RPC_ERRORS(body);
    return json(body, 201);
};

// POST /home/display/link-poll (público, con el secreto de sondeo): pending, expired o ready con la sesión.
export const handleDisplayLinkPoll = async (req: Request): Promise<Response> => {
    const input = await contractInput(req);
    const secret = inputString(input, "poll_secret");
    if (contractEmpty(secret)) return error("Poll secret is required", 400);
    const res = await serviceRpc("fn_display_link_poll", { p_poll_secret: secret });
    const body = await res.json().catch(() => null) as { status?: string; session?: Record<string, unknown>; display?: unknown } | null;
    if (!res.ok) {
        const message = (body as { message?: string } | null)?.message ?? "Internal error";
        return error(message, message === "Not Found" ? 404 : 500);
    }
    if (body?.status === "ready" && body.session) {
        return json({
            status: "ready",
            token: body.session.access_token,
            refresh_token: body.session.refresh_token,
            display: body.display,
        });
    }
    return json({ status: body?.status ?? "pending" });
};

// POST /home/display/link-confirm {code, name} (con X-Home-Id): vincula la pantalla al hogar de la cabecera.
export const handleDisplayLinkConfirm = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const code = inputString(input, "code");
    const nameRaw = inputString(input, "name");
    if (contractEmpty(nameRaw)) return errNameRequired();
    const name = nameRaw as string;
    if (code === null || !/^\d{6}$/.test(code)) return error("Invalid link code", 400);
    const homeId = currentHome();
    if (homeId === null) return errHomeIdRequired();

    // 1. Claim: comprueba permisos, límites, intentos y el código; marca la vinculación como usada.
    const claim = await rpc("fn_display_link_claim", { p_home_id: Number(homeId), p_code: code, p_name: name }, token);
    const claimBody = await claim.json().catch(() => null) as { link_id?: number; error?: string } | null;
    if (!claim.ok) return RPC_ERRORS(claimBody);
    if (claimBody?.error) return RPC_ERRORS({ message: claimBody.error });
    const linkId = Number(claimBody?.link_id);

    // 2. Cuenta técnica en GoTrue y su sesión (la contraseña es aleatoria y se descarta).
    const email = `display-${linkId}-${randomHex(6)}@displays.homita.invalid`;
    const password = randomHex(32);
    const created = await adminCreateUser(email, password, name);
    if (!created.ok) {
        await abortLink(linkId, null);
        return error("Internal error", 500);
    }
    const uid = (await created.json() as { id: string }).id;
    const grant = await passwordGrant(email, password);
    if (!grant.ok) {
        await abortLink(linkId, uid);
        return error("Internal error", 500);
    }
    const session = await grant.json();

    // 3. Membresía, home_member de kind display y sesión pendiente de entregar al sondeo.
    const done = await serviceRpc("fn_display_link_complete", { p_link_id: linkId, p_auth_uid: uid, p_session: session });
    if (!done.ok) {
        const doneBody = await done.json().catch(() => null);
        await abortLink(linkId, uid);
        return RPC_ERRORS(doneBody);
    }
    const out = await done.json() as { display_id: number };
    return json({ id: out.display_id, name, home_id: Number(homeId) }, 201);
};

// GET /home/display (con X-Home-Id): pantallas activas del hogar y su selección.
export const handleDisplayList = async (_req: Request, token: string): Promise<Response> => {
    const homeId = currentHome();
    if (homeId === null) return errHomeIdRequired();
    return rpcPassHome(await rpc("fn_display_list", { p_home_id: Number(homeId) }, token));
};

// Lee la pantalla actual para completar un PATCH parcial (lo que no llega se conserva).
const currentDisplay = async (token: string, homeId: number, displayId: number): Promise<Record<string, unknown> | null> => {
    const res = await rpc("fn_display_list", { p_home_id: homeId }, token);
    if (!res.ok) return null;
    const list = await res.json() as Record<string, unknown>[];
    return list.find((d) => d.id === displayId) ?? null;
};

// Lista de ids válida: array de enteros positivos; ausente o null → no tocar.
const idsOf = (input: ContractInput, key: string): number[] | null | "INVALID" => {
    const raw = getInput(input, key);
    if (raw === null || raw === undefined) return null;
    if (!Array.isArray(raw) || !raw.every((v) => Number.isInteger(v) && (v as number) > 0)) return "INVALID";
    return raw as number[];
};

// PATCH /home/display/update {id, name?, settings?, calendar_ids?, task_list_ids?} (con X-Home-Id)
export const handleDisplayUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const displayId = inputInt(input, "id");
    if (displayId === null || displayId <= 0) return error("Display ID is required", 400);
    const homeId = currentHome();
    if (homeId === null) return errHomeIdRequired();

    const nameRaw = getInput(input, "name");
    if (nameRaw !== null && nameRaw !== undefined && typeof nameRaw !== "string") return errNameRequired();
    const settingsRaw = getInput(input, "settings");
    if (settingsRaw !== null && settingsRaw !== undefined && (typeof settingsRaw !== "object" || Array.isArray(settingsRaw))) {
        return error("Invalid display settings", 400);
    }
    const calendars = idsOf(input, "calendar_ids");
    const lists = idsOf(input, "task_list_ids");
    if (calendars === "INVALID" || lists === "INVALID") return error("Invalid display selection", 400);

    const current = await currentDisplay(token, Number(homeId), displayId);
    if (current === null) return rpcPassHome(new Response(JSON.stringify({ message: "Not Found" }), { status: 404 }));

    const res = await rpc("fn_display_update", {
        p_home_id: Number(homeId),
        p_display_id: displayId,
        p_name: typeof nameRaw === "string" ? nameRaw : current.name,
        p_settings: settingsRaw ?? null,
        p_calendar_ids: calendars ?? current.calendar_ids,
        p_task_list_ids: lists ?? current.task_list_ids,
    }, token);
    return rpcPassHome(res);
};

// POST /home/display/revoke {id} (con X-Home-Id): quita la membresía y la selección y borra la cuenta de GoTrue,
// que cierra sus sesiones. Aunque el borrado en GoTrue falle, la pantalla ya no lee nada del hogar.
export const handleDisplayRevoke = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const displayId = inputInt(input, "id");
    if (displayId === null || displayId <= 0) return error("Display ID is required", 400);
    const homeId = currentHome();
    if (homeId === null) return errHomeIdRequired();
    const res = await rpc("fn_display_revoke", { p_home_id: Number(homeId), p_display_id: displayId }, token);
    const body = await res.json().catch(() => null) as { id?: number; auth_uid?: string | null } | null;
    if (!res.ok) return RPC_ERRORS(body);
    if (body?.auth_uid) await adminDeleteUser(body.auth_uid).catch(() => undefined);
    return json({ id: displayId, revoked: true });
};

// GET /display/config (sesión de la pantalla, sin cabecera de hogar): su configuración y selección.
export const handleDisplayConfig = async (_req: Request, token: string): Promise<Response> =>
    rpcPassHome(await rpc("fn_display_config", {}, token));
