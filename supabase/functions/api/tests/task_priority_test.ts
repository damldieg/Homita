// Tests de la Edge del change prioridad-tarea (0037, D-026): `priority` opcional en POST /task/create
// y PATCH /task/update, filtro `priority` y `sort=priority` en GET /task. Sin BD ni red: fetch se
// sustituye por un stub. La semántica real (default media, conservar en update, orden) la comprueba
// en BD scripts/supabase/tests/task_priority_check.sql; aquí se fija que la RPC solo recibe los
// parámetros nuevos cuando el cliente los envía (la Edge sirve igual sobre la BD sin 0037) y el 400.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { handleTask, handleTaskCreate, handleTaskUpdate } = await import("../usecases/tasks.ts");

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

const send = (method: string, path: string, body: unknown): Request =>
    new Request(`http://x/${path}`, {
        method, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const TASK = { id: 41, task_list_id: 3, title: "Leche", completed_at: null, order: 1, priority: "media", persons: [] };
const rpcBody = (calls: Call[], rpc: string) => calls.find((x) => x.url.endsWith(`/rpc/${rpc}`))?.body ?? null;

const writes = [
    { label: "task/create", handler: handleTaskCreate, method: "POST", rpc: "create_task", body: { task_list_id: 3, title: "Leche" }, status: 201 },
    { label: "task/update", handler: handleTaskUpdate, method: "PATCH", rpc: "update_task", body: { id: 41, title: "Leche" }, status: 200 },
] as const;

for (const w of writes) {
    for (const value of ["alta", "media", "baja"]) {
        Deno.test(`${w.label} con priority=${value}: la RPC recibe p_priority`, async () => {
            await withFetch(() => jsonRes(200, TASK), async (calls) => {
                const res = await w.handler(send(w.method, w.label, { ...w.body, priority: value }), "jwt");
                assertEquals(res.status, w.status);
                assertEquals(rpcBody(calls, w.rpc)?.p_priority, value);
            });
        });
    }

    for (const [label, extra] of [["sin la clave", {}], ["con la clave a null", { priority: null }]] as const) {
        Deno.test(`${w.label} ${label}: la RPC no recibe p_priority (contrato previo)`, async () => {
            await withFetch(() => jsonRes(200, TASK), async (calls) => {
                const res = await w.handler(send(w.method, w.label, { ...w.body, ...extra }), "jwt");
                assertEquals(res.status, w.status);
                assertEquals("p_priority" in (rpcBody(calls, w.rpc) ?? {}), false);
            });
        });
    }

    for (const [label, value] of [["urgente", "urgente"], ["vacía", ""], ["número", 1], ["mayúsculas", "ALTA"], ["booleano", true]] as const) {
        Deno.test(`${w.label} con priority inválida (${label}) -> 400 sin llamar a la RPC`, async () => {
            await withFetch(() => jsonRes(200, TASK), async (calls) => {
                const res = await w.handler(send(w.method, w.label, { ...w.body, priority: value }), "jwt");
                assertEquals(res.status, 400);
                assertEquals(await res.json(), { error: "Invalid priority" });
                assertEquals(calls.length, 0);
            });
        });
    }

    Deno.test(`${w.label}: 'Invalid priority' de la RPC -> 400`, async () => {
        await withFetch(() => jsonRes(400, { code: "P0001", message: "Invalid priority" }), async () => {
            const res = await w.handler(send(w.method, w.label, { ...w.body, priority: "alta" }), "jwt");
            assertEquals(res.status, 400);
            assertEquals((await res.json()).error, "Invalid priority");
        });
    });
}

const get = (query: string): Request => new Request(`http://x/task${query}`, { method: "GET" });

Deno.test("GET /task sin parámetros nuevos: payload de get_tasks idéntico al previo", async () => {
    await withFetch(() => jsonRes(200, [TASK]), async (calls) => {
        const res = await handleTask(get("?dashboard=true"), "jwt");
        assertEquals(res.status, 200);
        assertEquals(rpcBody(calls, "get_tasks"), { p_dashboard: true, p_task_list_id: null, p_widget: null });
    });
});

Deno.test("GET /task?priority=alta&sort=priority: la RPC recibe p_priority y p_sort", async () => {
    await withFetch(() => jsonRes(200, [TASK]), async (calls) => {
        const res = await handleTask(get("?priority=alta&sort=priority"), "jwt");
        assertEquals(res.status, 200);
        const body = rpcBody(calls, "get_tasks");
        assertEquals(body?.p_priority, "alta");
        assertEquals(body?.p_sort, "priority");
    });
});

Deno.test("GET /task?sort=title: un sort desconocido se ignora (sin p_sort)", async () => {
    await withFetch(() => jsonRes(200, [TASK]), async (calls) => {
        const res = await handleTask(get("?sort=title"), "jwt");
        assertEquals(res.status, 200);
        assertEquals("p_sort" in (rpcBody(calls, "get_tasks") ?? {}), false);
    });
});

for (const value of ["x", "", "ALTA"]) {
    Deno.test(`GET /task?priority=${value} -> 400 sin llamar a la RPC`, async () => {
        await withFetch(() => jsonRes(200, [TASK]), async (calls) => {
            const res = await handleTask(get(`?priority=${value}`), "jwt");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid priority" });
            assertEquals(calls.length, 0);
        });
    });
}
