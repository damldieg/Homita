// Tests de la Edge del change ios-offline-outbox-tareas (0035, D-024): client_request_id opcional
// en POST /task/create y POST /task-list/create. Sin BD ni red: fetch se sustituye por un stub.
// La deduplicación real (mismo id, sin segunda fila) la comprueba en BD
// scripts/supabase/tests/client_request_check.sql; aquí se fija el reenvío de la clave a la RPC,
// el 201 en el reenvío, la ausencia de la clave cuando no llega y el 400 con un UUID inválido.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { handleTaskCreate } = await import("../usecases/tasks.ts");
const { handleTaskListCreate } = await import("../usecases/task-lists.ts");

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

const post = (path: string, body: unknown): Request =>
    new Request(`http://x/${path}`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const UUID = "3f2c8a1e-5b7d-4c9e-8f10-2a3b4c5d6e7f";
const TASK = { id: 41, task_list_id: 3, title: "Leche", completed_at: null, order: 1, persons: [] };
const LIST = { id: 9, name: "Compra", color: "#6923E2", token: "t", sort: "updated_at", home_id: 1 };

const cases = [
    {
        label: "task/create",
        handler: handleTaskCreate,
        path: "task/create",
        rpc: "/rpc/create_task",
        body: { task_list_id: 3, title: "Leche" },
        result: TASK,
    },
    {
        label: "task-list/create",
        handler: handleTaskListCreate,
        path: "task-list/create",
        rpc: "/rpc/create_task_list",
        body: { name: "Compra" },
        result: LIST,
    },
] as const;

for (const c of cases) {
    Deno.test(`${c.label} con client_request_id: la RPC recibe la clave y el reenvío responde 201 igual`, async () => {
        await withFetch(() => jsonRes(200, c.result), async (calls) => {
            const first = await c.handler(post(c.path, { ...c.body, client_request_id: UUID }), "jwt");
            const second = await c.handler(post(c.path, { ...c.body, client_request_id: UUID }), "jwt");
            assertEquals(first.status, 201);
            assertEquals(second.status, 201);
            assertEquals(await first.json(), c.result);
            assertEquals(await second.json(), c.result);
            const rpcCalls = calls.filter((x) => x.url.endsWith(c.rpc));
            assertEquals(rpcCalls.length, 2);
            for (const call of rpcCalls) assertEquals(call.body?.p_client_request_id, UUID);
        });
    });

    Deno.test(`${c.label} con client_request_id en mayúsculas: se normaliza a minúsculas`, async () => {
        await withFetch(() => jsonRes(200, c.result), async (calls) => {
            const res = await c.handler(post(c.path, { ...c.body, client_request_id: UUID.toUpperCase() }), "jwt");
            assertEquals(res.status, 201);
            assertEquals(calls.find((x) => x.url.endsWith(c.rpc))!.body?.p_client_request_id, UUID);
        });
    });

    for (const [label, extra] of [
        ["sin la clave", {}],
        ["con la clave a null", { client_request_id: null }],
    ] as const) {
        Deno.test(`${c.label} ${label}: la RPC no recibe p_client_request_id (contrato previo)`, async () => {
            await withFetch(() => jsonRes(200, c.result), async (calls) => {
                const res = await c.handler(post(c.path, { ...c.body, ...extra }), "jwt");
                assertEquals(res.status, 201);
                const rpcCall = calls.find((x) => x.url.endsWith(c.rpc))!;
                assertEquals("p_client_request_id" in (rpcCall.body ?? {}), false);
            });
        });
    }

    for (const [label, value] of [
        ["texto libre", "no-es-un-uuid"],
        ["vacío", ""],
        ["número", 12345],
        ["UUID sin guiones", UUID.replaceAll("-", "")],
    ] as const) {
        Deno.test(`${c.label} con client_request_id inválido (${label}) -> 400 sin llamar a la RPC`, async () => {
            await withFetch(() => jsonRes(200, c.result), async (calls) => {
                const res = await c.handler(post(c.path, { ...c.body, client_request_id: value }), "jwt");
                assertEquals(res.status, 400);
                assertEquals((await res.json()).error, "Invalid client_request_id");
                assertEquals(calls.length, 0);
            });
        });
    }

    Deno.test(`${c.label}: 'Invalid client_request_id' de la RPC (otro kind) -> 400`, async () => {
        await withFetch(
            () => jsonRes(400, { code: "P0001", message: "Invalid client_request_id" }),
            async () => {
                const res = await c.handler(post(c.path, { ...c.body, client_request_id: UUID }), "jwt");
                assertEquals(res.status, 400);
                assertEquals((await res.json()).error, "Invalid client_request_id");
            },
        );
    });
}
