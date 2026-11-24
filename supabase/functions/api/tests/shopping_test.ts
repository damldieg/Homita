// Tests de la Edge para /shopping* (0045, menus-compra). Sin BD ni red: fetch se sustituye por un stub
// durante cada test; se comprueban la validación de forma (400 sin RPC), los argumentos de cada RPC, el
// mapeo de errores, client_request_id y X-Home-Id.
import { assert, assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const {
    handleShoppingClearChecked, handleShoppingItemCheck, handleShoppingItemCreate, handleShoppingItemDelete,
    handleShoppingItemQty, handleShoppingList, handleShoppingPreview, handleShoppingSync,
} = await import("../usecases/shopping.ts");
const { runWithHome } = await import("../_shared/home.ts");

type Call = { url: string; body: unknown; headers: Headers };

const RPC = "http://stub.local/rest/v1/rpc/";
const UUID = "0b9f6a52-5d1e-4c53-9a4b-2f7f3a1c8e10";

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

const req = (method: string, body?: unknown, path = "/shopping"): Request =>
    new Request(`http://x${path}`, {
        method,
        headers: { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
    });

const ok = () => jsonRes(200, { success: true });

Deno.test("GET /shopping llama a list_shopping y pasa el JSON tal cual", async () => {
    await withFetch(() => jsonRes(200, { revision: 2, items: [] }), async (calls) => {
        const res = await handleShoppingList(req("GET"), "tok");
        assertEquals(res.status, 200);
        assertEquals(await res.json(), { revision: 2, items: [] });
        assertEquals(calls[0].url, `${RPC}list_shopping`);
        assertEquals(calls[0].headers.get("Authorization"), "Bearer tok");
    });
});

Deno.test("X-Home-Id del contexto se propaga a la RPC", async () => {
    await withFetch(() => jsonRes(200, {}), async (calls) => {
        await runWithHome("42", () => handleShoppingList(req("GET"), "tok"));
        assertEquals(calls[0].headers.get("X-Home-Id"), "42");
    });
});

Deno.test("GET /shopping/preview exige plan_id entero positivo y lo manda como p_plan_id", async () => {
    for (const q of ["", "?plan_id=abc", "?plan_id=0", "?plan_id=-3", "?plan_id=1.5"]) {
        await withFetch(ok, async (calls) => {
            const res = await handleShoppingPreview(req("GET", undefined, `/shopping/preview${q}`), "tok");
            assertEquals(res.status, 400);
            assertEquals(calls.length, 0);
        });
    }
    await withFetch(ok, async (calls) => {
        const res = await handleShoppingPreview(req("GET", undefined, "/shopping/preview?plan_id=9"), "tok");
        assertEquals(res.status, 200);
        assertEquals(calls[0].url, `${RPC}preview_meal_shopping`);
        assertEquals(calls[0].body, { p_plan_id: 9 });
    });
});

Deno.test("POST /shopping/sync valida plan_id y client_request_id sin llamar a la RPC", async () => {
    for (const body of [{}, { plan_id: "1" }, { plan_id: 0 }, { plan_id: 1.5 }, { plan_id: 1, client_request_id: "nope" }]) {
        await withFetch(ok, async (calls) => {
            const res = await handleShoppingSync(req("POST", body), "tok");
            assertEquals(res.status, 400);
            assertEquals(calls.length, 0);
        });
    }
});

Deno.test("POST /shopping/sync propaga client_request_id (en minúsculas) y devuelve {added,updated,removed}", async () => {
    await withFetch(() => jsonRes(200, { added: 2, updated: 0, removed: 1 }), async (calls) => {
        const res = await handleShoppingSync(req("POST", { plan_id: 5, client_request_id: UUID.toUpperCase() }), "tok");
        assertEquals(res.status, 200);
        assertEquals(await res.json(), { added: 2, updated: 0, removed: 1 });
        assertEquals(calls[0].url, `${RPC}sync_meal_shopping`);
        assertEquals(calls[0].body, { p_plan_id: 5, p_client_request_id: UUID });
    });
    await withFetch(ok, async (calls) => {
        await handleShoppingSync(req("POST", { plan_id: 5 }), "tok");
        assertEquals(calls[0].body, { p_plan_id: 5 });
    });
});

Deno.test("POST /shopping/sync: archivado 400, plan ajeno 404, sin permiso 403", async () => {
    const cases: [number, string, number][] = [
        [400, "Invalid meal plan", 400], [404, "Not Found", 404], [403, "Not Allowed", 403], [400, "Invalid client_request_id", 400],
    ];
    for (const [rpcStatus, message, expected] of cases) {
        await withFetch(() => jsonRes(rpcStatus, { message }), async () => {
            const res = await handleShoppingSync(req("POST", { plan_id: 5 }), "tok");
            assertEquals(res.status, expected);
            assertEquals(await res.json(), { error: message });
        });
    }
});

Deno.test("POST /shopping/item/create: forma inválida da 400 sin RPC", async () => {
    const bodies = [
        {}, { label: 5 }, { label: "x", quantity: "2" }, { label: "x", unit: 3 }, { label: "x", section: [] },
        { label: "x", food_id: "7" }, { label: "x", food_id: 0 }, { label: "x", client_request_id: "nope" },
    ];
    for (const body of bodies) {
        await withFetch(ok, async (calls) => {
            const res = await handleShoppingItemCreate(req("POST", body), "tok");
            assertEquals(res.status, 400);
            assertEquals(calls.length, 0);
        });
    }
});

Deno.test("POST /shopping/item/create responde 201 y manda solo los campos presentes", async () => {
    await withFetch(() => jsonRes(200, { id: 3, label: "Leche" }), async (calls) => {
        const res = await handleShoppingItemCreate(
            req("POST", { label: "Leche", quantity: 2, unit: "l", section: "lacteos", food_id: 11, client_request_id: UUID }),
            "tok",
        );
        assertEquals(res.status, 201);
        assertEquals(calls[0].url, `${RPC}create_shopping_item`);
        assertEquals(calls[0].body, {
            p_label: "Leche", p_quantity: 2, p_unit: "l", p_section: "lacteos", p_food_id: 11, p_client_request_id: UUID,
        });
    });
    await withFetch(ok, async (calls) => {
        await handleShoppingItemCreate(req("POST", { food_id: 11 }), "tok");
        assertEquals(calls[0].body, { p_label: null, p_food_id: 11 });
        await handleShoppingItemCreate(req("POST", { label: "Pan" }), "tok");
        assertEquals(calls[1].body, { p_label: "Pan" });
    });
});

Deno.test("POST /shopping/item/create: errores de la RPC mapeados (400, 403, 400 por clave reutilizada)", async () => {
    const cases: [number, string, number][] = [
        [400, "Invalid shopping item", 400], [403, "Not Allowed", 403], [400, "Invalid client_request_id", 400], [404, "Not Found", 404],
    ];
    for (const [rpcStatus, message, expected] of cases) {
        await withFetch(() => jsonRes(rpcStatus, { message }), async () => {
            const res = await handleShoppingItemCreate(req("POST", { label: "x" }), "tok");
            assertEquals(res.status, expected);
            assertEquals(await res.json(), { error: message });
        });
    }
});

Deno.test("PATCH /shopping/item/check valida id y state sin RPC y manda p_item_id/p_state", async () => {
    for (const body of [{}, { id: "1", state: "checked" }, { id: 0, state: "checked" }, { id: 1 }, { id: 1, state: 3 }]) {
        await withFetch(ok, async (calls) => {
            const res = await handleShoppingItemCheck(req("PATCH", body), "tok");
            assertEquals(res.status, 400);
            assertEquals(calls.length, 0);
        });
    }
    for (const state of ["checked", "pending", "skipped"]) {
        await withFetch(ok, async (calls) => {
            const res = await handleShoppingItemCheck(req("PATCH", { id: 4, state }), "tok");
            assertEquals(res.status, 200);
            assertEquals(calls[0].url, `${RPC}set_shopping_item_state`);
            assertEquals(calls[0].body, { p_item_id: 4, p_state: state });
        });
    }
});

Deno.test("PATCH /shopping/item/check: estado inválido de la RPC es 400, inexistente 404, invitado 403", async () => {
    const cases: [number, string, number][] = [[400, "Invalid shopping item", 400], [404, "Not Found", 404], [403, "Not Allowed", 403]];
    for (const [rpcStatus, message, expected] of cases) {
        await withFetch(() => jsonRes(rpcStatus, { message }), async () => {
            const res = await handleShoppingItemCheck(req("PATCH", { id: 4, state: "hecho" }), "tok");
            assertEquals(res.status, expected);
            assertEquals(await res.json(), { error: message });
        });
    }
});

Deno.test("PATCH /shopping/item/update valida id y quantity y manda unit solo si viene", async () => {
    for (const body of [{}, { id: 1 }, { id: 1, quantity: "2" }, { id: 1, quantity: null }, { id: 1, quantity: 2, unit: 5 }, { quantity: 2 }]) {
        await withFetch(ok, async (calls) => {
            const res = await handleShoppingItemQty(req("PATCH", body), "tok");
            assertEquals(res.status, 400);
            assertEquals(calls.length, 0);
        });
    }
    await withFetch(ok, async (calls) => {
        await handleShoppingItemQty(req("PATCH", { id: 2, quantity: 1.5 }), "tok");
        await handleShoppingItemQty(req("PATCH", { id: 2, quantity: 300, unit: "g" }), "tok");
        assertEquals(calls[0].url, `${RPC}update_shopping_item_qty`);
        assertEquals(calls[0].body, { p_item_id: 2, p_quantity: 1.5 });
        assertEquals(calls[1].body, { p_item_id: 2, p_quantity: 300, p_unit: "g" });
    });
});

Deno.test("DELETE /shopping/item/delete acepta id por query o body y valida la forma", async () => {
    await withFetch(ok, async (calls) => {
        const res = await handleShoppingItemDelete(req("DELETE", undefined, "/shopping/item/delete"), "tok");
        assertEquals(res.status, 400);
        assertEquals(calls.length, 0);
        const bad = await handleShoppingItemDelete(req("DELETE", undefined, "/shopping/item/delete?id=x"), "tok");
        assertEquals(bad.status, 400);
        assertEquals(calls.length, 0);
    });
    await withFetch(() => jsonRes(200, { id: 8, deleted: true }), async (calls) => {
        const a = await handleShoppingItemDelete(req("DELETE", undefined, "/shopping/item/delete?id=8"), "tok");
        assertEquals(await a.json(), { id: 8, deleted: true });
        await handleShoppingItemDelete(req("DELETE", { id: 9 }, "/shopping/item/delete"), "tok");
        assertEquals(calls[0].url, `${RPC}delete_shopping_item`);
        assertEquals(calls[0].body, { p_item_id: 8 });
        assertEquals(calls[1].body, { p_item_id: 9 });
    });
});

Deno.test("DELETE /shopping/item/delete: artículo de otro hogar es 404", async () => {
    await withFetch(() => jsonRes(404, { message: "Not Found" }), async () => {
        const res = await handleShoppingItemDelete(req("DELETE", undefined, "/shopping/item/delete?id=8"), "tok");
        assertEquals(res.status, 404);
    });
});

Deno.test("DELETE /shopping/checked llama a clear_checked_shopping sin argumentos y 403 para invitado", async () => {
    await withFetch(() => jsonRes(200, { cleared: 3 }), async (calls) => {
        const res = await handleShoppingClearChecked(req("DELETE", undefined, "/shopping/checked"), "tok");
        assertEquals(await res.json(), { cleared: 3 });
        assertEquals(calls[0].url, `${RPC}clear_checked_shopping`);
        assertEquals(calls[0].body, {});
    });
    await withFetch(() => jsonRes(403, { message: "Not Allowed" }), async () => {
        const res = await handleShoppingClearChecked(req("DELETE", undefined, "/shopping/checked"), "tok");
        assertEquals(res.status, 403);
    });
});

Deno.test("las rutas /shopping* están registradas en index.ts con auth y home", async () => {
    const src = await Deno.readTextFile(new URL("../index.ts", import.meta.url));
    const routes = [
        "GET /shopping", "GET /shopping/preview", "POST /shopping/sync", "POST /shopping/item/create",
        "PATCH /shopping/item/check", "PATCH /shopping/item/update", "DELETE /shopping/item/delete", "DELETE /shopping/checked",
    ];
    for (const r of routes) {
        assert(src.includes(`"${r}": { auth: true, home: true,`), `falta la ruta ${r}`);
    }
});
