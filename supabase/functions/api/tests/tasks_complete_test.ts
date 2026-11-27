// Tests de PATCH /task/complete con clave de cliente (0050, dashboard-marcar-hecho). Sin BD ni red: fetch se
// sustituye por un stub. La regla de la pantalla (solo completar, idempotencia, auditoría) la comprueba
// scripts/supabase/tests/marcar_hecho_check.sql.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { handleTaskComplete } = await import("../usecases/tasks.ts");

type Call = { url: string; body: unknown };

const withFetch = async (fn: (calls: Call[]) => Promise<void>): Promise<void> => {
    const original = globalThis.fetch;
    const calls: Call[] = [];
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
        const url = String(input instanceof Request ? input.url : input);
        const body = init?.body ? JSON.parse(String(init.body)) : null;
        calls.push({ url, body });
        return Promise.resolve(new Response(JSON.stringify({ id: 7, completed_at: null }), { status: 200, headers: { "Content-Type": "application/json" } }));
    }) as typeof fetch;
    try {
        await fn(calls);
    } finally {
        globalThis.fetch = original;
    }
};

const patch = (body: unknown): Request =>
    new Request("http://x/task/complete", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

Deno.test("complete reenvía la clave de cliente a la RPC", async () => {
    await withFetch(async (calls) => {
        const res = await handleTaskComplete(patch({ id: 7, completed: true, client_request_id: "A0000000-0000-4000-8000-000000000001" }), "tok");
        assertEquals(res.status, 200);
        const rpcCall = calls.find((c) => c.url.includes("/rpc/complete_task"))!;
        assertEquals(rpcCall.body, { p_id: 7, p_completed: true, p_client_request_id: "a0000000-0000-4000-8000-000000000001" });
    });
});

Deno.test("complete sin clave no envía p_client_request_id (clientes antiguos; sirve tras rollback de 0050)", async () => {
    await withFetch(async (calls) => {
        await handleTaskComplete(patch({ id: 7, completed: false }), "tok");
        const rpcCall = calls.find((c) => c.url.includes("/rpc/complete_task"))!;
        assertEquals(rpcCall.body, { p_id: 7, p_completed: false });
    });
});

Deno.test("clave que no es UUID → 400 sin llamar a la RPC", async () => {
    await withFetch(async (calls) => {
        const res = await handleTaskComplete(patch({ id: 7, completed: true, client_request_id: "no-es-uuid" }), "tok");
        assertEquals(res.status, 400);
        assertEquals(calls.length, 0);
    });
});
