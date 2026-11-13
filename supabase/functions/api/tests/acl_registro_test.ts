// Tests de la Edge del change permisos-edicion-registro-sesion: PATCH /calendar/user y
// PATCH /task-list/user (0029) y registro con sesión (password grant tras el signup).
// Sin BD ni red: fetch se sustituye por un stub durante cada test.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");
Deno.env.set("ALLOW_REGISTRATION", "true");

const { handleUserCreate } = await import("../usecases/auth.ts");
const { handleCalendarUserAccess } = await import("../usecases/calendars.ts");
const { handleTaskListUserAccess } = await import("../usecases/task-lists.ts");

type Call = { url: string; body: unknown };

const jsonRes = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const withFetch = async (
    handler: (url: string, body: unknown) => Response,
    fn: (calls: Call[]) => Promise<void>,
): Promise<void> => {
    const original = globalThis.fetch;
    const calls: Call[] = [];
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
        const url = String(input instanceof Request ? input.url : input);
        const body = init?.body ? JSON.parse(String(init.body)) : null;
        calls.push({ url, body });
        return Promise.resolve(handler(url, body));
    }) as typeof fetch;
    try {
        await fn(calls);
    } finally {
        globalThis.fetch = original;
    }
};

const patch = (path: string, body: unknown): Request =>
    new Request(`http://x/${path}`, {
        method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const post = (body: unknown): Request =>
    new Request("http://x/user/create", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

// ─────────────── PATCH /calendar/user y /task-list/user ───────────────

Deno.test("PATCH calendar/user llama a set_calendar_user_access con can_edit booleano", async () => {
    await withFetch(() => jsonRes(200, { user_id: 7, can_edit: true }), async (calls) => {
        const res = await handleCalendarUserAccess(
            patch("calendar/user", { calendar_id: 3, user_id: 7, can_edit: true }), "jwt");
        assertEquals(res.status, 200);
        const rpcCall = calls.find((c) => c.url.includes("/rpc/set_calendar_user_access"))!;
        assertEquals(rpcCall.body, { p_calendar_id: 3, p_user_id: 7, p_can_edit: true });
    });
});

Deno.test("PATCH task-list/user acepta can_edit=false y llama a set_task_list_user_access", async () => {
    await withFetch(() => jsonRes(200, { user_id: 7, can_edit: false }), async (calls) => {
        const res = await handleTaskListUserAccess(
            patch("task-list/user", { task_list_id: 4, user_id: 7, can_edit: false }), "jwt");
        assertEquals(res.status, 200);
        const rpcCall = calls.find((c) => c.url.includes("/rpc/set_task_list_user_access"))!;
        assertEquals(rpcCall.body, { p_task_list_id: 4, p_user_id: 7, p_can_edit: false });
    });
});

for (const [label, body] of [
    ["sin can_edit", { calendar_id: 3, user_id: 7 }],
    ["sin user_id", { calendar_id: 3, can_edit: true }],
    ["can_edit no booleano", { calendar_id: 3, user_id: 7, can_edit: "quizá" }],
] as const) {
    Deno.test(`PATCH calendar/user ${label} -> 400 sin RPC`, async () => {
        await withFetch(() => jsonRes(200, {}), async (calls) => {
            const res = await handleCalendarUserAccess(patch("calendar/user", body), "jwt");
            assertEquals(res.status, 400);
            assertEquals((await res.json()).error, "calendar_id, user_id and can_edit are required");
            assertEquals(calls.length, 0);
        });
    });
}

Deno.test("PATCH calendar/user: RPC 42501 Not Allowed -> 403 Not Allowed (mismo contrato que viewer)", async () => {
    await withFetch(() => jsonRes(403, { code: "42501", message: "Not Allowed" }), async () => {
        const res = await handleCalendarUserAccess(
            patch("calendar/user", { calendar_id: 3, user_id: 7, can_edit: true }), "jwt");
        assertEquals(res.status, 403);
        assertEquals((await res.json()).error, "Not Allowed");
    });
});

// ─────────────── POST /user/create con sesión ───────────────

const userBody = { name: "Ana Pérez", email: "ana@example.com", password: "12345678" };
const session = {
    access_token: "jwt-ana", refresh_token: "rt-ana", user: { id: "00000000-0000-4000-8000-000000000001" },
};
const appUser = [{ id: 9, name: "Ana Pérez", email: "ana@example.com",
                   created_at: "2026-11-13T10:00:00", updated_at: "2026-11-13T10:00:00" }];

Deno.test("user/create con sesión en el signup -> 201 con token y refresh_token, sin password grant", async () => {
    await withFetch((url) => {
        if (url.includes("/auth/v1/signup")) return jsonRes(200, session);
        if (url.includes("/rest/v1/app_user")) return jsonRes(200, appUser);
        return jsonRes(500, {});
    }, async (calls) => {
        const res = await handleUserCreate(post(userBody));
        assertEquals(res.status, 201);
        const body = await res.json();
        assertEquals([body.token, body.refresh_token], ["jwt-ana", "rt-ana"]);
        assertEquals(calls.filter((c) => c.url.includes("grant_type=password")).length, 0);
    });
});

Deno.test("user/create sin sesión en el signup -> password grant -> 201 con sesión", async () => {
    await withFetch((url) => {
        if (url.includes("/auth/v1/signup")) return jsonRes(200, { id: "x", email: "ana@example.com" });
        if (url.includes("grant_type=password")) return jsonRes(200, session);
        if (url.includes("/rest/v1/app_user")) return jsonRes(200, appUser);
        return jsonRes(500, {});
    }, async (calls) => {
        const res = await handleUserCreate(post(userBody));
        assertEquals(res.status, 201);
        assertEquals((await res.json()).token, "jwt-ana");
        const grant = calls.find((c) => c.url.includes("grant_type=password"))!;
        assertEquals(grant.body, { email: "ana@example.com", password: "12345678" });
    });
});

Deno.test("user/create con confirmación de email activa -> 400 Email confirmation is pending", async () => {
    await withFetch((url) => {
        if (url.includes("/auth/v1/signup")) return jsonRes(200, { id: "x", email: "ana@example.com" });
        if (url.includes("grant_type=password")) return jsonRes(400, { error_code: "email_not_confirmed" });
        return jsonRes(500, {});
    }, async () => {
        const res = await handleUserCreate(post(userBody));
        assertEquals(res.status, 400);
        assertEquals((await res.json()).error, "Email confirmation is pending");
    });
});
