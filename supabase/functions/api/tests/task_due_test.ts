// Tests de la Edge del change fecha-limite-vencimiento (0041): `due_at` en PATCH /task/update.
// Sin BD ni red: fetch se sustituye por un stub. La semántica real (fijar, borrar, no tocar) la comprueba
// en BD scripts/supabase/tests/task_due_check.sql; aquí se fija el mapeo de la clave a p_due_at / p_clear_due
// y el 400 'Invalid due_at' sin llamar a la RPC para formatos no válidos. Una fecha con formato correcto pero
// imposible (2026-13-01) la rechaza la RPC: lo cubre task_due_check.sql.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { handleTaskUpdate } = await import("../usecases/tasks.ts");

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

const send = (body: unknown): Request =>
    new Request("http://x/task/update", {
        method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const rpcBody = (calls: Call[], rpc: string) => calls.find((x) => x.url.endsWith(`/rpc/${rpc}`))?.body ?? null;
const okTask = () => jsonRes(200, { id: 41, title: "Leche", due_at: null, persons: [] });

const fixed: [unknown, string][] = [
    ["2026-12-01 18:30", "2026-12-01 18:30:00"],
    ["2026-12-01T18:30:45", "2026-12-01 18:30:45"],
];
for (const [input, expected] of fixed) {
    Deno.test(`PATCH /task/update due_at=${input} -> p_due_at=${expected}`, async () => {
        await withFetch(() => okTask(), async (calls) => {
            const res = await handleTaskUpdate(send({ id: 41, title: "Leche", due_at: input }), "jwt");
            assertEquals(res.status, 200);
            const body = rpcBody(calls, "update_task");
            assertEquals(body?.p_due_at, expected);
            assertEquals("p_clear_due" in (body ?? {}), false);
        });
    });
}

Deno.test("PATCH /task/update due_at='' -> p_clear_due=true y sin p_due_at", async () => {
    await withFetch(() => okTask(), async (calls) => {
        await handleTaskUpdate(send({ id: 41, title: "Leche", due_at: "" }), "jwt");
        const body = rpcBody(calls, "update_task");
        assertEquals(body?.p_clear_due, true);
        assertEquals("p_due_at" in (body ?? {}), false);
    });
});

for (const [label, extra] of [["sin la clave", {}], ["con la clave a null", { due_at: null }]] as const) {
    Deno.test(`PATCH /task/update ${label}: la RPC no recibe fecha (no se toca)`, async () => {
        await withFetch(() => okTask(), async (calls) => {
            await handleTaskUpdate(send({ id: 41, title: "Leche", ...extra }), "jwt");
            const body = rpcBody(calls, "update_task") ?? {};
            assertEquals("p_due_at" in body, false);
            assertEquals("p_clear_due" in body, false);
        });
    });
}

for (const value of ["mañana", "2026-12-01", "01/12/2026 10:00", 1700000000]) {
    Deno.test(`PATCH /task/update due_at=${JSON.stringify(value)} -> 400 sin llamar a la RPC`, async () => {
        await withFetch(() => okTask(), async (calls) => {
            const res = await handleTaskUpdate(send({ id: 41, title: "Leche", due_at: value }), "jwt");
            assertEquals(res.status, 400);
            assertEquals(await res.json(), { error: "Invalid due_at" });
            assertEquals(calls.some((x) => x.url.endsWith("/rpc/update_task")), false);
        });
    });
}
