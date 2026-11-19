// Tests de POST /feedback (change control-ios-feedback). Sin BD ni red: fetch se sustituye por un stub.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { validateFeedback } = await import("../_shared/validate.ts");
const { handleFeedbackCreate } = await import("../usecases/feedback.ts");

const valid = { seccion: "Inicio", subseccion: "eventos de hoy: ver", tipo: "bug", texto: "  Falla al abrir  " };

Deno.test("validateFeedback: válido recorta texto", () => {
    const v = validateFeedback(valid);
    assertEquals(v instanceof Response, false);
    assertEquals(v, { seccion: "Inicio", subseccion: "eventos de hoy: ver", tipo: "bug", texto: "Falla al abrir" });
});

Deno.test("validateFeedback: subseccion opcional", () => {
    const v = validateFeedback({ ...valid, subseccion: undefined });
    assertEquals((v as { subseccion: string | null }).subseccion, null);
});

const status = (v: unknown): number | null => (v instanceof Response ? v.status : null);

Deno.test("validateFeedback: rechazos 400", () => {
    assertEquals(status(validateFeedback({ ...valid, texto: "   " })), 400);
    assertEquals(status(validateFeedback({ ...valid, texto: "x".repeat(2001) })), 400);
    assertEquals(status(validateFeedback({ ...valid, tipo: "otro" })), 400);
    assertEquals(status(validateFeedback({ ...valid, tipo: undefined })), 400);
    assertEquals(status(validateFeedback({ ...valid, seccion: "Otra" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "sin accion" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "eventos: volar" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "a".repeat(100) + ": ver" })), 400);
});

type Call = { url: string; headers: Headers; body: unknown };

const withFetch = async (
    respond: () => Response,
    fn: (calls: Call[]) => Promise<void>,
): Promise<void> => {
    const original = globalThis.fetch;
    const calls: Call[] = [];
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
        calls.push({
            url: String(input), headers: new Headers(init?.headers),
            body: init?.body ? JSON.parse(String(init.body)) : null,
        });
        return Promise.resolve(respond());
    }) as typeof fetch;
    try {
        await fn(calls);
    } finally {
        globalThis.fetch = original;
    }
};

const post = (body: unknown): Request =>
    new Request("http://x/feedback", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const jsonRes = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.test("handleFeedbackCreate: inserta con el JWT del usuario y devuelve 201 {ok}", async () => {
    await withFetch(() => new Response(null, { status: 201 }), async (calls) => {
        const res = await handleFeedbackCreate(post({ ...valid, user_id: "ajeno" }), "tok-user");
        assertEquals(res.status, 201);
        assertEquals(await res.json(), { ok: true });
        assertEquals(calls.length, 1);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/feedback");
        assertEquals(calls[0].headers.get("Authorization"), "Bearer tok-user");
        assertEquals(calls[0].headers.get("Prefer"), "return=minimal");
        // no se reenvía user_id del cliente; se usa solo la whitelist
        assertEquals(calls[0].body, {
            seccion: "Inicio", subseccion: "eventos de hoy: ver", tipo: "bug", texto: "Falla al abrir",
        });
    });
});

Deno.test("handleFeedbackCreate: validación 400 sin llamar a PostgREST", async () => {
    await withFetch(() => new Response(null, { status: 201 }), async (calls) => {
        const res = await handleFeedbackCreate(post({ ...valid, texto: "" }), "t");
        assertEquals(res.status, 400);
        assertEquals(calls.length, 0);
    });
});

Deno.test("handleFeedbackCreate: RLS denegada -> 403", async () => {
    await withFetch(() => jsonRes(403, { code: "42501", message: "new row violates row-level security policy" }), async () => {
        const res = await handleFeedbackCreate(post(valid), "t");
        assertEquals(res.status, 403);
    });
});

Deno.test("handleFeedbackCreate: fallo de PostgREST 5xx -> 500", async () => {
    await withFetch(() => jsonRes(500, { message: "boom" }), async () => {
        const res = await handleFeedbackCreate(post(valid), "t");
        assertEquals(res.status, 500);
    });
});
