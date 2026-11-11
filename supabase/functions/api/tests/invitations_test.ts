// Tests de la Edge para invitaciones (0026): registro con código y alta de invitación con email.
// Sin BD ni red: fetch se sustituye por un stub durante cada test.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");
Deno.env.set("ALLOW_REGISTRATION", "true");

const { handleUserCreate } = await import("../usecases/auth.ts");
const { handleHomeInvitationCreate } = await import("../usecases/homes.ts");

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

const req = (body: unknown): Request =>
    new Request("http://x/user/create", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const userBody = (extra: Record<string, unknown> = {}) => ({
    name: "Ana Pérez", email: "Ana@Example.com", password: "12345678", ...extra,
});
const isCheck = (c: Call) => c.url.includes("/rpc/check_home_invitation_for_signup");
const isSignup = (c: Call) => c.url.includes("/auth/v1/signup");

Deno.test("user/create con código válido y email correcto llama a signup", async () => {
    await withFetch((url) => {
        if (url.includes("/rpc/check_home_invitation_for_signup")) return jsonRes(200, null);
        // signup sin sesión: la respuesta no importa, solo que se llame
        return jsonRes(400, { msg: "stop" });
    }, async (calls) => {
        await handleUserCreate(req(userBody({ invitation_code: "  ABC123  " })));
        const check = calls.find(isCheck)!;
        assertEquals(check.body, { p_code: "abc123", p_email: "ana@example.com" });
        assertEquals(calls.filter(isSignup).length, 1);
    });
});

Deno.test("user/create: RPC 404 Not Found -> 404 y no llama a signup", async () => {
    await withFetch(() => jsonRes(404, { message: "Not Found" }), async (calls) => {
        const res = await handleUserCreate(req(userBody({ invitation_code: "abc" })));
        assertEquals(res.status, 404);
        assertEquals((await res.json()).error, "Invitation code is not valid");
        assertEquals(calls.filter(isSignup).length, 0);
    });
});

Deno.test("user/create: RPC 403 Not Allowed -> 403 y no llama a signup", async () => {
    await withFetch(() => jsonRes(403, { message: "Not Allowed" }), async (calls) => {
        const res = await handleUserCreate(req(userBody({ invitation_code: "abc" })));
        assertEquals(res.status, 403);
        assertEquals(calls.filter(isSignup).length, 0);
    });
});

Deno.test("user/create sin invitation_code no llama a la RPC", async () => {
    await withFetch(() => jsonRes(400, { msg: "stop" }), async (calls) => {
        await handleUserCreate(req(userBody()));
        assertEquals(calls.filter(isCheck).length, 0);
        assertEquals(calls.filter(isSignup).length, 1);
    });
});

const invReq = (body: unknown): Request =>
    new Request("http://x/home/invitation/create", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

for (const [label, email] of [["ausente", undefined], ["mal formado", "no-es-email"], ["sin dominio", "a@b"]] as const) {
    Deno.test(`home/invitation/create con email ${label} -> 400 sin RPC`, async () => {
        await withFetch(() => jsonRes(200, {}), async (calls) => {
            const res = await handleHomeInvitationCreate(invReq({ home_id: 1, kind: "member", email }), "tok");
            assertEquals(res.status, 400);
            assertEquals((await res.json()).error, "Invalid email");
            assertEquals(calls.length, 0);
        });
    });
}

Deno.test("home/invitation/create con email válido llama a la RPC con p_email en minúsculas", async () => {
    await withFetch(() => jsonRes(200, {}), async (calls) => {
        await handleHomeInvitationCreate(invReq({ home_id: 1, kind: "member", email: " Bob@Example.COM " }), "tok");
        const c = calls.find((x) => x.url.includes("/rpc/create_home_invitation"))!;
        assertEquals((c.body as Record<string, unknown>).p_email, "bob@example.com");
    });
});

Deno.test("signup envía el marcador invitation_pending (no el código) solo cuando hay código (0027)", async () => {
    const stop = () => jsonRes(400, { msg: "stop" });
    await withFetch((url) => url.includes("/rpc/") ? jsonRes(200, null) : stop(), async (calls) => {
        await handleUserCreate(req(userBody({ invitation_code: "  ABC123  " })));
        const s = calls.find(isSignup)!;
        assertEquals((s.body as { data: unknown }).data, { name: "Ana Pérez", invitation_pending: true });
    });
    await withFetch(stop, async (calls) => {
        await handleUserCreate(req(userBody()));
        const s = calls.find(isSignup)!;
        assertEquals((s.body as { data: unknown }).data, { name: "Ana Pérez" });
    });
});

Deno.test("user/create ignora invitation_code en el query string (R1-06)", async () => {
    const stop = () => jsonRes(400, { msg: "stop" });
    await withFetch(stop, async (calls) => {
        const r = new Request("http://x/user/create?invitation_code=abc123", {
            method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(userBody()),
        });
        await handleUserCreate(r);
        assertEquals(calls.some(isCheck), false);
        assertEquals((calls.find(isSignup)!.body as { data: unknown }).data, { name: "Ana Pérez" });
    });
});
