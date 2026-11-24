// Tests de la Edge para /recipe* y /food* (0044, menus-semana). Sin BD ni red: fetch se sustituye
// por un stub; se comprueban argumentos de cada RPC, validación de forma, mapeo de errores y X-Home-Id.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const {
    handleFoodCreate, handleFoodDelete, handleFoodSearch, handleFoodUpdate, handleRecipeCreate,
    handleRecipeDelete, handleRecipeDetail, handleRecipeIndex, handleRecipeUpdate,
} = await import("../usecases/recipes.ts");
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

const req = (method: string, body?: unknown, path = "/x"): Request =>
    new Request(`http://x${path}`, {
        method,
        headers: { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
    });

const RPC = "http://stub.local/rest/v1/rpc/";

const ok = () => jsonRes(200, { ok: true });

Deno.test("GET /recipe pasa q, slot y max_minutes a list_recipes", async () => {
    await withFetch(() => jsonRes(200, []), async (calls) => {
        const res = await handleRecipeIndex(req("GET", undefined, "/recipe?q=lent&slot=lunch&max_minutes=30"), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, RPC + "list_recipes");
        assertEquals(calls[0].body, { p_q: "lent", p_slot: "lunch", p_max_minutes: 30 });
    });
});

Deno.test("GET /recipe con max_minutes no numérico → 400 sin RPC", async () => {
    await withFetch(ok, async (calls) => {
        const res = await handleRecipeIndex(req("GET", undefined, "/recipe?max_minutes=abc"), "tok");
        assertEquals(res.status, 400);
        assertEquals(await res.json(), { error: "Invalid recipe" });
        assertEquals(calls.length, 0);
    });
});

Deno.test("GET /recipe/detail exige id entero y llama a get_recipe", async () => {
    await withFetch(ok, async (calls) => {
        for (const p of ["/recipe/detail", "/recipe/detail?id=abc", "/recipe/detail?id=0"]) {
            const res = await handleRecipeDetail(req("GET", undefined, p), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Recipe ID is required" });
        }
        assertEquals(calls.length, 0);
        const res = await handleRecipeDetail(req("GET", undefined, "/recipe/detail?id=12"), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, RPC + "get_recipe");
        assertEquals(calls[0].body, { p_id: 12 });
    });
});

Deno.test("GET /recipe/detail: Not Found de la RPC → 404", async () => {
    await withFetch(() => jsonRes(404, { message: "Not Found" }), async () => {
        const res = await handleRecipeDetail(req("GET", undefined, "/recipe/detail?id=9"), "tok");
        assertEquals(res.status, 404);
    });
});

Deno.test("POST /recipe/create mapea el body a p_* y responde 201", async () => {
    await withFetch(ok, async (calls) => {
        const body = {
            name: "Lentejas", servings: 4, minutes: 45, slots: ["lunch"], steps: ["Cocer"],
            ingredients: [{ food_id: 1, label: "Lentejas", quantity: 300, unit: "g" }],
        };
        const res = await handleRecipeCreate(req("POST", body), "tok");
        assertEquals(res.status, 201);
        assertEquals(calls[0].url, RPC + "create_recipe");
        assertEquals(calls[0].body, {
            p_name: "Lentejas", p_servings: 4, p_minutes: 45, p_slots: ["lunch"], p_steps: ["Cocer"],
            p_ingredients: body.ingredients,
        });
    });
});

Deno.test("POST /recipe/create solo con name no envía el resto (la RPC aplica sus defaults)", async () => {
    await withFetch(ok, async (calls) => {
        await handleRecipeCreate(req("POST", { name: "Tortilla" }), "tok");
        assertEquals(calls[0].body, { p_name: "Tortilla" });
    });
});

Deno.test("POST /recipe/create con forma inválida → 400 sin RPC", async () => {
    await withFetch(ok, async (calls) => {
        for (const b of [{}, { name: 5 }, { name: "a", slots: "lunch" }, { name: "a", steps: [1] }, { name: "a", ingredients: {} }]) {
            const res = await handleRecipeCreate(req("POST", b), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid recipe" });
        }
        assertEquals(calls.length, 0);
    });
});

Deno.test("POST /recipe/create: 'Invalid recipe' de la RPC → 400", async () => {
    await withFetch(() => jsonRes(400, { message: "Invalid recipe" }), async () => {
        const res = await handleRecipeCreate(req("POST", { name: "x", servings: 0 }), "tok");
        assertEquals(res.status, 400);
    });
});

Deno.test("PATCH /recipe/update separa id y envía el resto como p_data", async () => {
    await withFetch(ok, async (calls) => {
        const res = await handleRecipeUpdate(req("PATCH", { id: 3, name: "Nueva", ingredients: [] }), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, RPC + "update_recipe");
        assertEquals(calls[0].body, { p_id: 3, p_data: { name: "Nueva", ingredients: [] } });
    });
});

Deno.test("PATCH /recipe/update sin id válido o ingredients no array → 400", async () => {
    await withFetch(ok, async (calls) => {
        const r1 = await handleRecipeUpdate(req("PATCH", { name: "x" }), "tok");
        assertEquals(await r1.json(), { error: "Recipe ID is required" });
        const r2 = await handleRecipeUpdate(req("PATCH", { id: "3" }), "tok");
        assertEquals(r2.status, 400);
        const r3 = await handleRecipeUpdate(req("PATCH", { id: 3, ingredients: "x" }), "tok");
        assertEquals(await r3.json(), { error: "Invalid recipe" });
        assertEquals(calls.length, 0);
    });
});

Deno.test("DELETE /recipe/delete acepta id por query o body", async () => {
    await withFetch(ok, async (calls) => {
        await handleRecipeDelete(req("DELETE", undefined, "/recipe/delete?id=5"), "tok");
        await handleRecipeDelete(req("DELETE", { id: 6 }), "tok");
        assertEquals(calls.map((c) => c.body), [{ p_id: 5 }, { p_id: 6 }]);
        assertEquals(calls[0].url, RPC + "delete_recipe");
        const bad = await handleRecipeDelete(req("DELETE", {}), "tok");
        assertEquals(bad.status, 400);
        assertEquals(calls.length, 2);
    });
});

Deno.test("GET /food pasa q y limit a search_food", async () => {
    await withFetch(() => jsonRes(200, []), async (calls) => {
        await handleFoodSearch(req("GET", undefined, "/food?q=pol&limit=5"), "tok");
        assertEquals(calls[0].url, RPC + "search_food");
        assertEquals(calls[0].body, { p_q: "pol", p_limit: 5 });
        await handleFoodSearch(req("GET", undefined, "/food"), "tok");
        assertEquals(calls[1].body, {});
    });
});

Deno.test("POST /food/create mapea campos y responde 201; forma inválida → 400", async () => {
    await withFetch(ok, async (calls) => {
        const res = await handleFoodCreate(
            req("POST", { name: "Pollo", section: "carne", allergens: [], default_unit: "g", grams_per_unit: 1 }), "tok");
        assertEquals(res.status, 201);
        assertEquals(calls[0].url, RPC + "create_food");
        assertEquals(calls[0].body, {
            p_name: "Pollo", p_section: "carne", p_allergens: [], p_default_unit: "g", p_grams_per_unit: 1,
        });
        for (const b of [{}, { name: 1 }, { name: "a", allergens: "gluten" }]) {
            const bad = await handleFoodCreate(req("POST", b), "tok");
            assertEquals(bad.status, 400);
            assertEquals(await bad.json(), { error: "Invalid food" });
        }
        assertEquals(calls.length, 1);
    });
});

Deno.test("PATCH /food/update y DELETE /food/delete: id obligatorio; común → Not Found 404", async () => {
    await withFetch(() => jsonRes(404, { message: "Not Found" }), async (calls) => {
        const bad = await handleFoodUpdate(req("PATCH", { name: "x" }), "tok");
        assertEquals(await bad.json(), { error: "Food ID is required" });
        const upd = await handleFoodUpdate(req("PATCH", { id: 4, name: "x" }), "tok");
        assertEquals(upd.status, 404);
        assertEquals(calls[0].body, { p_id: 4, p_data: { name: "x" } });
        const del = await handleFoodDelete(req("DELETE", undefined, "/food/delete?id=4"), "tok");
        assertEquals(del.status, 404);
        assertEquals(calls[1].url, RPC + "delete_food");
    });
});

Deno.test("'Not Allowed' (42501) de la RPC → 403 en recetas", async () => {
    await withFetch(() => jsonRes(403, { message: "Not Allowed" }), async () => {
        const res = await handleRecipeCreate(req("POST", { name: "x" }), "tok");
        assertEquals(res.status, 403);
    });
});

Deno.test("X-Home-Id del contexto se propaga a recetas y alimentos", async () => {
    await withFetch(() => jsonRes(200, []), async (calls) => {
        await runWithHome("42", () => handleRecipeIndex(req("GET", undefined, "/recipe"), "tok"));
        await runWithHome("42", () => handleFoodSearch(req("GET", undefined, "/food"), "tok"));
        assertEquals(calls[0].headers.get("X-Home-Id"), "42");
        assertEquals(calls[1].headers.get("X-Home-Id"), "42");
    });
});

Deno.test("R1-03: tipos o rangos inválidos en recetas y alimentos → 400 sin RPC (no 500)", async () => {
    await withFetch(ok, async (calls) => {
        const recipeBodies = [
            { name: "a", servings: "abc" }, { name: "a", servings: 1.5 }, { name: "a", servings: 1e12 },
            { name: "a", minutes: "10" }, { name: "a", minutes: -1 }, { name: "a", minutes: true },
        ];
        for (const b of recipeBodies) {
            const res = await handleRecipeCreate(req("POST", b), "tok");
            assertEquals(res.status, 400, JSON.stringify(b));
            assertEquals(await res.json(), { error: "Invalid recipe" });
        }
        for (const data of [{ servings: "abc" }, { minutes: 1e12 }, { name: 5 }, { steps: [1] }, { slots: "x" }]) {
            const res = await handleRecipeUpdate(req("PATCH", { id: 3, ...data }), "tok");
            assertEquals(res.status, 400, JSON.stringify(data));
            assertEquals(await res.json(), { error: "Invalid recipe" });
        }
        const idx = await handleRecipeIndex(req("GET", undefined, "/recipe?max_minutes=99999999999"), "tok");
        assertEquals(idx.status, 400);
        for (const b of [{ name: "a", grams_per_unit: "x" }, { name: "a", section: {} }, { name: "a", default_unit: 3 }]) {
            const res = await handleFoodCreate(req("POST", b), "tok");
            assertEquals(res.status, 400, JSON.stringify(b));
            assertEquals(await res.json(), { error: "Invalid food" });
        }
        for (const data of [{ grams_per_unit: "x" }, { name: 1 }, { allergens: [1] }]) {
            const res = await handleFoodUpdate(req("PATCH", { id: 3, ...data }), "tok");
            assertEquals(res.status, 400, JSON.stringify(data));
        }
        const lim = await handleFoodSearch(req("GET", undefined, "/food?limit=99999999999"), "tok");
        assertEquals(lim.status, 400);
        assertEquals(calls.length, 0);
    });
});

Deno.test("R1-03: valores válidos límite (int32, null, decimales en grams_per_unit) sí llegan a la RPC", async () => {
    await withFetch(ok, async (calls) => {
        await handleRecipeCreate(req("POST", { name: "a", servings: 2147483647, minutes: null }), "tok");
        await handleFoodCreate(req("POST", { name: "a", grams_per_unit: 12.5 }), "tok");
        assertEquals(calls.length, 2);
    });
});

Deno.test("R1-04: steps con más de 50 pasos o pasos de más de 500 caracteres → 400 sin RPC", async () => {
    await withFetch(ok, async (calls) => {
        const many = Array.from({ length: 51 }, (_, i) => `p${i}`);
        const long = ["x".repeat(501)];
        for (const steps of [many, long, ["a", null]]) {
            const res = await handleRecipeCreate(req("POST", { name: "a", steps }), "tok");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid recipe" });
            const up = await handleRecipeUpdate(req("PATCH", { id: 3, steps }), "tok");
            assertEquals(up.status, 400);
        }
        assertEquals(calls.length, 0);
        const okSteps = Array.from({ length: 50 }, () => "x".repeat(500));
        const res = await handleRecipeCreate(req("POST", { name: "a", steps: okSteps }), "tok");
        assertEquals(res.status, 201);
        assertEquals(calls.length, 1);
    });
});
