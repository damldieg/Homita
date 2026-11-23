// Tests de la Edge para /meal/* (0043, menus-perfil-hogar). Sin BD ni red: fetch se sustituye por
// un stub durante cada test; se comprueban los argumentos de cada RPC, el mapeo de errores y la
// propagación de X-Home-Id.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const {
    handleMealProfileGet, handleMealProfileMemberUpdate, handleMealProfileUpdate, handleMealScheduleSet,
    handleMealSlotsSet,
} = await import("../usecases/meals.ts");
const { runWithHome } = await import("../_shared/home.ts");

type Call = { url: string; body: unknown; headers: Headers };

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
        calls.push({ url, body, headers: new Headers(init?.headers) });
        return Promise.resolve(handler(url, body));
    }) as typeof fetch;
    try {
        await fn(calls);
    } finally {
        globalThis.fetch = original;
    }
};

const req = (method: string, body?: unknown): Request =>
    new Request("http://x/meal", {
        method,
        headers: { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
    });

const ok = () => jsonRes(200, { success: true });

Deno.test("GET /meal/profile llama a get_meal_profile y pasa el JSON tal cual", async () => {
    await withFetch(() => jsonRes(200, { home_id: 7, slots: [] }), async (calls) => {
        const res = await handleMealProfileGet(req("GET"), "tok");
        assertEquals(res.status, 200);
        assertEquals(await res.json(), { home_id: 7, slots: [] });
        assertEquals(calls.length, 1);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/rpc/get_meal_profile");
        assertEquals(calls[0].headers.get("Authorization"), "Bearer tok");
    });
});

Deno.test("X-Home-Id del contexto se propaga a la RPC", async () => {
    await withFetch(() => jsonRes(200, {}), async (calls) => {
        await runWithHome("42", () => handleMealProfileGet(req("GET"), "tok"));
        assertEquals(calls[0].headers.get("X-Home-Id"), "42");
    });
});

Deno.test("PATCH /meal/profile envía el body como p_data", async () => {
    await withFetch(ok, async (calls) => {
        const res = await handleMealProfileUpdate(req("PATCH", { shopping_day: 5, preferences: { a: 1 } }), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/rpc/update_meal_profile");
        assertEquals(calls[0].body, { p_data: { shopping_day: 5, preferences: { a: 1 } } });
    });
});

Deno.test("PATCH /meal/profile ignora el query string (solo body)", async () => {
    await withFetch(ok, async (calls) => {
        const r = new Request("http://x/meal/profile?shopping_day=1", {
            method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ shopping_day: 3 }),
        });
        await handleMealProfileUpdate(r, "tok");
        assertEquals(calls[0].body, { p_data: { shopping_day: 3 } });
    });
});

Deno.test("PATCH /meal/profile/member separa home_member_id del resto", async () => {
    await withFetch(ok, async (calls) => {
        const res = await handleMealProfileMemberUpdate(req("PATCH", { home_member_id: 9, diet: "vegan", spice: 1 }), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/rpc/update_meal_profile_member");
        assertEquals(calls[0].body, { p_member_id: 9, p_data: { diet: "vegan", spice: 1 } });
    });
});

Deno.test("PATCH /meal/profile/member sin home_member_id válido → 400 sin llamar a la RPC", async () => {
    await withFetch(ok, async (calls) => {
        for (const body of [{}, { home_member_id: "9" }, { home_member_id: 0 }, { home_member_id: 1.5 }, { home_member_id: null }]) {
            const res = await handleMealProfileMemberUpdate(req("PATCH", body), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Member ID is required" });
        }
        assertEquals(calls.length, 0);
    });
});

Deno.test("PUT /meal/schedule envía entries a set_meal_schedule", async () => {
    await withFetch(ok, async (calls) => {
        const entries = [{ home_member_id: 3, weekday: 1, slot: "lunch", status: "out" }];
        const res = await handleMealScheduleSet(req("PUT", { entries }), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/rpc/set_meal_schedule");
        assertEquals(calls[0].body, { p_entries: entries });
    });
});

Deno.test("PUT /meal/schedule y /meal/slots sin array → 400 sin llamar a la RPC", async () => {
    await withFetch(ok, async (calls) => {
        for (const body of [{}, { entries: "x" }, { entries: {} }]) {
            const res = await handleMealScheduleSet(req("PUT", body), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid meal profile" });
        }
        for (const body of [{}, { slots: 1 }]) {
            const res = await handleMealSlotsSet(req("PUT", body), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid meal profile" });
        }
        assertEquals(calls.length, 0);
    });
});

Deno.test("PUT /meal/slots envía slots a set_meal_slot_settings", async () => {
    await withFetch(ok, async (calls) => {
        const slots = [{ slot: "lunch", enabled: true, time: "14:30" }];
        const res = await handleMealSlotsSet(req("PUT", { slots }), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/rpc/set_meal_slot_settings");
        assertEquals(calls[0].body, { p_slots: slots });
    });
});

Deno.test("errores de la RPC: Not Allowed 403, Not Found 404, Invalid meal profile / Invalid member 400", async () => {
    const cases: [string, number][] = [
        ["Not Allowed", 403], ["Not Found", 404], ["Invalid meal profile", 400], ["Invalid member", 400],
        ["Home header required", 400],
    ];
    for (const [message, status] of cases) {
        await withFetch(() => jsonRes(400, { message }), async () => {
            const res = await handleMealProfileUpdate(req("PATCH", { shopping_day: 1 }), "tok");
            assertEquals(res.status, status, message);
            assertEquals(await res.json(), { error: message });
        });
    }
});
