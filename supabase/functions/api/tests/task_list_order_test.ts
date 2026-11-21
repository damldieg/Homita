// Tests de la Edge del change lista-prioritaria-inicio: PATCH /task-list/order. Sin BD ni red: fetch se
// sustituye por un stub. La atomicidad y los permisos reales los comprueban en BD
// scripts/supabase/tests/task_list_position_check.sql (TP3-TP7); aquí se fija la validación local (400),
// el reenvío de `ids` como p_ids a la RPC y el paso de errores de la RPC (403/500).
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { handleTaskListOrder } = await import("../usecases/task-lists.ts");

type Call = { url: string; body: Record<string, unknown> | null };

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

const patch = (body: unknown): Request =>
    new Request("http://x/task-list/order", {
        method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const invalid: [string, unknown][] = [
    ["ids ausente", {}],
    ["ids vacío", { ids: [] }],
    ["ids no es array", { ids: 3 }],
    ["ids duplicados", { ids: [1, 2, 1] }],
    ["id no entero", { ids: [1, 2.5] }],
    ["id string", { ids: [1, "2"] }],
    ["id cero", { ids: [0, 1] }],
    ["id negativo", { ids: [-1] }],
    ["id null", { ids: [1, null] }],
    ["id fuera de rango seguro", { ids: [1, 1e21] }],
];

for (const [label, body] of invalid) {
    Deno.test(`task-list/order: ${label} → 400 Task list IDs are required, sin llamar a la RPC`, async () => {
        await withFetch(() => jsonRes(200, []), async (calls) => {
            const res = await handleTaskListOrder(patch(body), "tok");
            assertEquals(res.status, 400);
            assertEquals((await res.json()).error, "Task list IDs are required");
            assertEquals(calls.length, 0);
        });
    });
}

Deno.test("task-list/order: ids válidos → RPC reorder_task_lists con p_ids y 200", async () => {
    const applied = [{ id: 3, position: 1 }, { id: 1, position: 2 }];
    await withFetch(() => jsonRes(200, applied), async (calls) => {
        const res = await handleTaskListOrder(patch({ ids: [3, 1] }), "tok");
        assertEquals(res.status, 200);
        assertEquals(await res.json(), applied);
        assertEquals(calls.length, 1);
        assertEquals(calls[0].url.endsWith("/rpc/reorder_task_lists"), true);
        assertEquals(calls[0].body, { p_ids: [3, 1] });
    });
});

Deno.test("task-list/order: errores de la RPC pasan tal cual (Not Allowed 403, Not Found 500)", async () => {
    await withFetch(() => jsonRes(403, { code: "42501", message: "Not Allowed" }), async () => {
        const res = await handleTaskListOrder(patch({ ids: [1, 2] }), "tok");
        assertEquals(res.status, 403);
    });
    await withFetch(() => jsonRes(404, { code: "P0002", message: "Not Found" }), async () => {
        const res = await handleTaskListOrder(patch({ ids: [1, 2] }), "tok");
        assertEquals(res.status, 500);
    });
});
