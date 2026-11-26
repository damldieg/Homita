// Tests de la Edge para /meal/* (0043, menus-perfil-hogar). Sin BD ni red: fetch se sustituye por
// un stub durante cada test; se comprueban los argumentos de cada RPC, el mapeo de errores y la
// propagación de X-Home-Id.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const {
    handleMealProfileGet, handleMealProfileMemberUpdate, handleMealProfileUpdate, handleMealScheduleSet,
    handleMealSlotsSet, handleMealPlanAccept, handleMealPlanArchive, handleMealPlanCheck, handleMealPlanCopy,
    handleMealPlanGet, handleMealPlanItems, handleMealToday,
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

Deno.test("GET /meal/profile conserva candidates (A1) tal cual, sin llamar a home/member", async () => {
    const body = {
        home_id: 7, members: [],
        candidates: [{ id: 3, home_id: 7, kind: "adult", name: "Ana", color: null, status: "active", linked: true }],
    };
    await withFetch(() => jsonRes(200, body), async (calls) => {
        const res = await handleMealProfileGet(req("GET"), "tok");
        assertEquals(await res.json(), body);
        assertEquals(calls.length, 1);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/rpc/get_meal_profile");
    });
});

Deno.test("PATCH /meal/profile reenvía valores raros a la RPC y su 'Invalid meal profile' sale como 400 (R1-02/R1-03)", async () => {
    const bodies = [{ task_list_id: "abc" }, { preferences: { k: "x".repeat(9000) } }];
    for (const data of bodies) {
        await withFetch(() => jsonRes(400, { message: "Invalid meal profile" }), async (calls) => {
            const res = await handleMealProfileUpdate(req("PATCH", data), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid meal profile" });
            assertEquals(calls[0].body, { p_data: data });
        });
    }
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

Deno.test("PATCH /meal/profile reenvía countries como p_data y el GET lo devuelve tal cual (0046)", async () => {
    await withFetch(ok, async (calls) => {
        for (const countries of [["AR", "ES"], []]) {
            const res = await handleMealProfileUpdate(req("PATCH", { countries }), "tok");
            assertEquals(res.status, 200);
            assertEquals(calls[calls.length - 1].body, { p_data: { countries } });
        }
    });
    const profile = { home_id: 1, profile: { countries: ["AR", "ES"], shopping_day: 6 } };
    await withFetch(() => jsonRes(200, profile), async () => {
        const res = await handleMealProfileGet(req("GET"), "tok");
        assertEquals(await res.json(), profile);
    });
});

Deno.test("PATCH /meal/profile con countries mal formado → 400 sin llamar a la RPC (0046)", async () => {
    const bodies = [{ countries: "ES" }, { countries: null }, { countries: [1] }, { countries: ["ES", null] },
        { countries: [["ES"]] }, { countries: { a: "ES" } }];
    for (const data of bodies) {
        await withFetch(ok, async (calls) => {
            const res = await handleMealProfileUpdate(req("PATCH", data), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid meal profile" });
            assertEquals(calls.length, 0);
        });
    }
});

Deno.test("PATCH /meal/profile: un código fuera de lista lo rechaza la RPC → 400 (0046)", async () => {
    await withFetch(() => jsonRes(400, { message: "Invalid meal profile" }), async (calls) => {
        const res = await handleMealProfileUpdate(req("PATCH", { countries: ["XX"] }), "tok");
        assertEquals(res.status, 400);
        assertEquals(calls[0].body, { p_data: { countries: ["XX"] } });
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

// ── menú semanal (0044) ──
const RPC = "http://stub.local/rest/v1/rpc/";
const getReq = (path: string): Request => new Request(`http://x${path}`, { method: "GET" });

Deno.test("GET /meal/plan valida week_start y llama a get_meal_plan (null pasa tal cual)", async () => {
    await withFetch(() => jsonRes(200, null), async (calls) => {
        for (const p of ["/meal/plan", "/meal/plan?week_start=2026-13-01", "/meal/plan?week_start=26-11-23"]) {
            const bad = await handleMealPlanGet(getReq(p), "tok");
            assertEquals(bad.status, 400);
            assertEquals(await bad.json(), { error: "Invalid meal plan" });
        }
        assertEquals(calls.length, 0);
        const res = await handleMealPlanGet(getReq("/meal/plan?week_start=2026-11-23"), "tok");
        assertEquals(res.status, 200);
        assertEquals(await res.json(), null);
        assertEquals(calls[0].url, RPC + "get_meal_plan");
        assertEquals(calls[0].body, { p_week_start: "2026-11-23" });
    });
});

Deno.test("PATCH /meal/plan/items mapea a upsert_meal_plan_items", async () => {
    await withFetch(ok, async (calls) => {
        const items = [{ day: "2026-11-23", slot: "lunch", kind: "free_text", title: "Arroz" }];
        const res = await handleMealPlanItems(
            req("PATCH", { week_start: "2026-11-23", expected_revision: 0, items, delete_ids: [4, 5] }), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, RPC + "upsert_meal_plan_items");
        assertEquals(calls[0].body, {
            p_week_start: "2026-11-23", p_expected_revision: 0, p_items: items, p_delete_ids: [4, 5],
        });
    });
});

Deno.test("PATCH /meal/plan/items con forma inválida → 400 sin RPC", async () => {
    await withFetch(ok, async (calls) => {
        const base = { week_start: "2026-11-23", expected_revision: 1 };
        for (const b of [
            {}, { ...base, week_start: "hoy" }, { ...base, expected_revision: "1" }, { ...base, expected_revision: 1.5 },
            { ...base, expected_revision: -1 }, { ...base, items: {} }, { ...base, delete_ids: ["a"] },
            { ...base, delete_ids: [0] },
        ]) {
            const res = await handleMealPlanItems(req("PATCH", b), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid meal plan" });
        }
        assertEquals(calls.length, 0);
    });
});

Deno.test("PATCH /meal/plan/items: 'Stale meal plan revision' → 409", async () => {
    await withFetch(() => jsonRes(400, { message: "Stale meal plan revision" }), async () => {
        const res = await handleMealPlanItems(req("PATCH", { week_start: "2026-11-23", expected_revision: 1 }), "tok");
        assertEquals(res.status, 409);
        assertEquals(await res.json(), { error: "Stale meal plan revision" });
    });
});

Deno.test("POST /meal/plan/accept: args, 409 de revisión y 400 de plan no draft", async () => {
    await withFetch(() => jsonRes(200, { id: 3, revision: 2 }), async (calls) => {
        const res = await handleMealPlanAccept(req("POST", { plan_id: 3, expected_revision: 1 }), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, RPC + "accept_meal_plan");
        assertEquals(calls[0].body, { p_plan_id: 3, p_expected_revision: 1 });
        const bad = await handleMealPlanAccept(req("POST", { expected_revision: 1 }), "tok");
        assertEquals(await bad.json(), { error: "Meal plan ID is required" });
        const bad2 = await handleMealPlanAccept(req("POST", { plan_id: 3 }), "tok");
        assertEquals(await bad2.json(), { error: "Invalid meal plan" });
        assertEquals(calls.length, 1);
    });
    await withFetch(() => jsonRes(400, { message: "Invalid meal plan" }), async () => {
        const res = await handleMealPlanAccept(req("POST", { plan_id: 3, expected_revision: 1 }), "tok");
        assertEquals(res.status, 400);
    });
    await withFetch(() => jsonRes(400, { message: "Stale meal plan revision" }), async () => {
        const res = await handleMealPlanAccept(req("POST", { plan_id: 3, expected_revision: 0 }), "tok");
        assertEquals(res.status, 409);
    });
});

Deno.test("POST /meal/plan/archive exige plan_id; Not Found → 404", async () => {
    await withFetch(() => jsonRes(404, { message: "Not Found" }), async (calls) => {
        const bad = await handleMealPlanArchive(req("POST", {}), "tok");
        assertEquals(bad.status, 400);
        assertEquals(calls.length, 0);
        const res = await handleMealPlanArchive(req("POST", { plan_id: 8 }), "tok");
        assertEquals(res.status, 404);
        assertEquals(calls[0].url, RPC + "archive_meal_plan");
        assertEquals(calls[0].body, { p_plan_id: 8 });
    });
    await withFetch(() => jsonRes(400, { message: "Stale meal plan revision" }), async (calls) => {
        const res = await handleMealPlanArchive(req("POST", { plan_id: 8, expected_revision: 3 }), "tok");
        assertEquals(res.status, 409);
        assertEquals(calls[0].body, { p_plan_id: 8, p_expected_revision: 3 });
        const bad = await handleMealPlanArchive(req("POST", { plan_id: 8, expected_revision: "x" }), "tok");
        assertEquals(bad.status, 400);
        assertEquals(calls.length, 1);
    });
});

Deno.test("POST /meal/plan/copy: args, 400 de fechas y 409 'Meal plan exists'", async () => {
    await withFetch(() => jsonRes(400, { message: "Meal plan exists" }), async (calls) => {
        const bad = await handleMealPlanCopy(req("POST", { from_week: "2026-11-16" }), "tok");
        assertEquals(bad.status, 400);
        assertEquals(calls.length, 0);
        const res = await handleMealPlanCopy(req("POST", { from_week: "2026-11-16", to_week: "2026-11-23" }), "tok");
        assertEquals(res.status, 409);
        assertEquals(await res.json(), { error: "Meal plan exists" });
        assertEquals(calls[0].url, RPC + "copy_meal_plan_week");
        assertEquals(calls[0].body, { p_from_week: "2026-11-16", p_to_week: "2026-11-23" });
    });
    await withFetch(() => jsonRes(200, { id: 9 }), async () => {
        const res = await handleMealPlanCopy(req("POST", { from_week: "2026-11-16", to_week: "2026-11-23" }), "tok");
        assertEquals(res.status, 201);
    });
});

Deno.test("GET /meal/plan/check exige plan_id entero", async () => {
    await withFetch(() => jsonRes(200, []), async (calls) => {
        for (const p of ["/meal/plan/check", "/meal/plan/check?plan_id=x"]) {
            const bad = await handleMealPlanCheck(getReq(p), "tok");
            assertEquals(bad.status, 400);
        }
        assertEquals(calls.length, 0);
        const res = await handleMealPlanCheck(getReq("/meal/plan/check?plan_id=7"), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, RPC + "check_meal_plan");
        assertEquals(calls[0].body, { p_plan_id: 7 });
    });
});

Deno.test("GET /meal/today: sin date no manda p_date; con date lo valida; Invalid timezone → 400", async () => {
    await withFetch(() => jsonRes(200, { has_plan: false }), async (calls) => {
        await handleMealToday(getReq("/meal/today"), "tok");
        assertEquals(calls[0].url, RPC + "get_meals_today");
        assertEquals(calls[0].body, {});
        await handleMealToday(getReq("/meal/today?date=2026-11-24"), "tok");
        assertEquals(calls[1].body, { p_date: "2026-11-24" });
        const bad = await handleMealToday(getReq("/meal/today?date=mañana"), "tok");
        assertEquals(bad.status, 400);
        assertEquals(calls.length, 2);
    });
    await withFetch(() => jsonRes(400, { message: "Invalid timezone" }), async () => {
        const res = await handleMealToday(getReq("/meal/today"), "tok");
        assertEquals(res.status, 400);
    });
});

Deno.test("X-Home-Id se propaga en las rutas del plan", async () => {
    await withFetch(() => jsonRes(200, {}), async (calls) => {
        await runWithHome("42", () => handleMealToday(getReq("/meal/today"), "tok"));
        await runWithHome("42", () => handleMealPlanGet(getReq("/meal/plan?week_start=2026-11-23"), "tok"));
        assertEquals(calls[0].headers.get("X-Home-Id"), "42");
        assertEquals(calls[1].headers.get("X-Home-Id"), "42");
    });
});

Deno.test("R1-03: expected_revision fuera de int32 o plan_id gigante → 400 sin RPC (no 500)", async () => {
    await withFetch(() => jsonRes(200, {}), async (calls) => {
        for (const rev of [1e12, 2147483648, -1, 1.5, "1", true]) {
            const a = await handleMealPlanItems(req("PATCH", { week_start: "2026-11-23", expected_revision: rev }), "tok");
            assertEquals(a.status, 400, String(rev));
            assertEquals(await a.json(), { error: "Invalid meal plan" });
            const b = await handleMealPlanAccept(req("POST", { plan_id: 1, expected_revision: rev }), "tok");
            assertEquals(b.status, 400, String(rev));
            const c = await handleMealPlanArchive(req("POST", { plan_id: 1, expected_revision: rev }), "tok");
            assertEquals(c.status, 400, String(rev));
        }
        const d = await handleMealPlanArchive(req("POST", { plan_id: 1e20 }), "tok");
        assertEquals(d.status, 400);
        assertEquals(calls.length, 0);
    });
});
