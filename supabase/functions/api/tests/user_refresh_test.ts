// Tests de POST /user/refresh (dashboard-sesion): refresh_token grant contra GoTrue, sin BD ni red.
// fetch se sustituye por un stub durante cada test.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { handleUserRefresh } = await import("../usecases/auth.ts");

type Call = { url: string; body: unknown; apikey: string | null };

const jsonRes = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const withFetch = async (
    handler: (url: string) => Response,
    fn: (calls: Call[]) => Promise<void>,
): Promise<void> => {
    const original = globalThis.fetch;
    const calls: Call[] = [];
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
        const url = String(input instanceof Request ? input.url : input);
        const body = init?.body ? JSON.parse(String(init.body)) : null;
        const apikey = new Headers(init?.headers).get("apikey");
        calls.push({ url, body, apikey });
        return Promise.resolve(handler(url));
    }) as typeof fetch;
    try {
        await fn(calls);
    } finally {
        globalThis.fetch = original;
    }
};

const post = (body: unknown): Request =>
    new Request("http://x/user/refresh", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const session = { access_token: "jwt-nuevo", refresh_token: "rt-nuevo", user: { id: "u" } };

Deno.test("refresh ok: llama al grant refresh_token de GoTrue con la anon key y devuelve token y refresh_token", async () => {
    await withFetch(() => jsonRes(200, session), async (calls) => {
        const res = await handleUserRefresh(post({ refresh_token: "rt-viejo" }));
        assertEquals(res.status, 200);
        assertEquals(await res.json(), { token: "jwt-nuevo", refresh_token: "rt-nuevo" });
        assertEquals(calls.length, 1);
        assertEquals(calls[0].url, "http://stub.local/auth/v1/token?grant_type=refresh_token");
        assertEquals(calls[0].body, { refresh_token: "rt-viejo" });
        assertEquals(calls[0].apikey, "anon");
    });
});

Deno.test("token inválido o revocado (GoTrue 400/401) → 401 Invalid refresh token", async () => {
    for (const status of [400, 401]) {
        await withFetch(() => jsonRes(status, { error: "invalid_grant" }), async () => {
            const res = await handleUserRefresh(post({ refresh_token: "malo" }));
            assertEquals(res.status, 401);
            assertEquals(await res.json(), { error: "Invalid refresh token" });
        });
    }
});

Deno.test("sin cuerpo o sin refresh_token → 400 sin llamar a GoTrue", async () => {
    await withFetch(() => jsonRes(200, session), async (calls) => {
        const sinCuerpo = await handleUserRefresh(new Request("http://x/user/refresh", { method: "POST" }));
        assertEquals(sinCuerpo.status, 400);
        const vacio = await handleUserRefresh(post({ refresh_token: "" }));
        assertEquals(vacio.status, 400);
        assertEquals(await vacio.json(), { error: "Refresh token is required" });
        assertEquals(calls.length, 0);
    });
});

Deno.test("error de GoTrue 5xx → 500, no 401 (el cliente no debe cerrar sesión)", async () => {
    await withFetch(() => jsonRes(503, { msg: "down" }), async () => {
        const res = await handleUserRefresh(post({ refresh_token: "rt" }));
        assertEquals(res.status, 500);
    });
});
