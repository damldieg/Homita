// Tests de handler.ts: auth, hogar, validación, límite diario, fallo del modelo y éxito.
// Sin red ni BD: auth, membresía, uso y modelo son falsos. Usa una skill falsa (no el registro real).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { createHandler, parseBody } from "../handler.ts";
import type { HandlerDeps, UsageDb, UsoResultado } from "../handler.ts";
import { ModelError } from "../core.ts";
import type { ModelResponse, Skill, Tokens } from "../core.ts";

const TOKEN = "jwt-de-prueba";
const HOME = "42";

const skillFalsa: Skill = {
    id: "falsa",
    nombre: "Falsa",
    descripcion: "Skill de prueba.",
    instrucciones: "SKILL-FALSA",
    herramientas: [],
    tarjetas: [],
    disponible: () => true,
};

type Opts = {
    key?: boolean;
    consume?: UsoResultado;
    modelo?: () => Promise<ModelResponse>;
    member?: boolean;
    user?: boolean;
};

const deps = (o: Opts = {}) => {
    const registros = { consume: 0, records: [] as { tokens: Tokens; refund: boolean }[], modelo: 0 };
    const usage: UsageDb = {
        consume: () => {
            registros.consume++;
            return Promise.resolve(o.consume ?? { allowed: true, used: 1, limit: 50, day: "2026-11-20" });
        },
        record: (_id, _day, tokens, refund) => {
            registros.records.push({ tokens, refund });
            return Promise.resolve();
        },
    };
    const d: HandlerDeps = {
        verifyUser: (t) => Promise.resolve(t === TOKEN ? { uid: "uid-1" } : null),
        appUserId: () => Promise.resolve(o.user === false ? null : "501"),
        checkHomeMember: () => Promise.resolve(o.member !== false),
        runInHome: (_h, fn) => fn(),
        usage,
        callModel: () => {
            registros.modelo++;
            return (o.modelo ?? (() => Promise.resolve({
                stop_reason: "end_turn",
                content: [{ type: "text", text: "Hola, soy Kito." }],
                usage: { input_tokens: 100, output_tokens: 20 },
            })))();
        },
        model: "claude-haiku-5-5",
        skills: [skillFalsa],
        env: (n) => (n === "ANTHROPIC_API_KEY" ? (o.key === false ? "" : "k-test") : undefined),
        now: () => new Date("2026-11-20T10:00:00Z"),
        log: () => {},
    };
    return { d, registros };
};

const peticion = (over: { method?: string; auth?: string | null; home?: string | null; body?: unknown; raw?: string } = {}) => {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    const auth = over.auth === undefined ? `Bearer ${TOKEN}` : over.auth;
    if (auth !== null) headers.Authorization = auth;
    const home = over.home === undefined ? HOME : over.home;
    if (home !== null) headers["X-Home-Id"] = home;
    const body = over.raw ?? JSON.stringify(over.body ?? { messages: [{ role: "user", content: "¿qué tengo hoy?" }], timezone: "Europe/Madrid" });
    const metodo = over.method ?? "POST";
    return new Request("https://x.local/asistente", { method: metodo, headers, body: metodo === "GET" ? undefined : body });
};

Deno.test("GET no está permitido (405)", async () => {
    const { d } = deps();
    const res = await createHandler(d)(peticion({ method: "GET" }));
    assertEquals(res.status, 405);
});

Deno.test("sin Bearer o con token inválido → 401 y sin tocar el uso", async () => {
    const { d, registros } = deps();
    const h = createHandler(d);
    assertEquals((await h(peticion({ auth: null }))).status, 401);
    assertEquals((await h(peticion({ auth: "Bearer otro" }))).status, 401);
    assertEquals(registros.consume, 0);
});

Deno.test("X-Home-Id ausente o inválido → 400; no miembro → 404", async () => {
    const { d } = deps();
    const h = createHandler(d);
    assertEquals((await h(peticion({ home: null }))).status, 400);
    assertEquals((await h(peticion({ home: "12a" }))).status, 400);
    const sinMembresia = createHandler(deps({ member: false }).d);
    assertEquals((await sinMembresia(peticion())).status, 404);
});

Deno.test("body inválido → 400 (zona, último mensaje, longitud, JSON)", async () => {
    const { d } = deps();
    const h = createHandler(d);
    assertEquals((await h(peticion({ raw: "{no json" }))).status, 400);
    assertEquals((await h(peticion({ body: { messages: [{ role: "user", content: "x" }], timezone: "Marte/X" } }))).status, 400);
    assertEquals((await h(peticion({ body: { messages: [{ role: "assistant", content: "x" }], timezone: "UTC" } }))).status, 400);
    assertEquals((await h(peticion({ body: { messages: [{ role: "user", content: "x".repeat(2001) }], timezone: "UTC" } }))).status, 400);
});

Deno.test("parseBody acepta un historial válido y limita a 20 mensajes", () => {
    const ok = parseBody({ messages: [{ role: "user", content: "a" }, { role: "assistant", content: "b" }, { role: "user", content: "c" }], timezone: "UTC" });
    assertEquals(typeof ok, "object");
    const muchos = Array.from({ length: 21 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: "x" }));
    assertEquals(typeof parseBody({ messages: muchos, timezone: "UTC" }), "string");
});

Deno.test("sin ANTHROPIC_API_KEY → 500 y no consume el contador (falla cerrada)", async () => {
    const { d, registros } = deps({ key: false });
    const res = await createHandler(d)(peticion());
    assertEquals(res.status, 500);
    assertEquals(registros.consume, 0);
    assertEquals(registros.modelo, 0);
});

Deno.test("usuario sin app_user → 404", async () => {
    const { d } = deps({ user: false });
    assertEquals((await createHandler(d)(peticion())).status, 404);
});

Deno.test("mensaje 51 del día → 429 con texto claro y sin llamar al modelo", async () => {
    const { d, registros } = deps({ consume: { allowed: false, used: 50, limit: 50, day: "2026-11-20" } });
    const res = await createHandler(d)(peticion());
    assertEquals(res.status, 429);
    const cuerpo = await res.json();
    assert(String(cuerpo.texto).includes("50 mensajes"));
    assertEquals(registros.modelo, 0);
    assertEquals(registros.records.length, 0);
});

Deno.test("éxito → 200 con texto, uso y tokens registrados (sin refund)", async () => {
    const { d, registros } = deps();
    const res = await createHandler(d)(peticion());
    assertEquals(res.status, 200);
    const cuerpo = await res.json();
    assertEquals(cuerpo.texto, "Hola, soy Kito.");
    assertEquals(cuerpo.uso, { usados: 1, limite: 50 });
    assertEquals(registros.records, [{ tokens: { input: 100, output: 20, cacheRead: 0, cacheWrite: 0 }, refund: false }]);
});

Deno.test("fallo del modelo → 502 y el mensaje se devuelve (refund)", async () => {
    const { d, registros } = deps({ modelo: () => Promise.reject(new ModelError("http 529")) });
    const res = await createHandler(d)(peticion());
    assertEquals(res.status, 502);
    assertEquals(registros.records.length, 1);
    assertEquals(registros.records[0].refund, true);
});
