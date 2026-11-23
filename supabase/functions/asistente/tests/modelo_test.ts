// Tests de la llamada HTTP al modelo: reintento único con retry-after, presupuesto y errores. Fetch falso.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { esperaReintento, crearCallModel } from "../modelo.ts";
import { ModelError } from "../core.ts";
import { createHandler } from "../handler.ts";
import type { HandlerDeps } from "../handler.ts";

const OK = () => new Response(JSON.stringify({ stop_reason: "end_turn", content: [{ type: "text", text: "ok" }] }), { status: 200 });
const err = (status: number, retryAfter?: string) =>
    new Response("{}", { status, headers: retryAfter ? { "retry-after": retryAfter } : {} });

const montar = (respuestas: Array<() => Response>) => {
    const esperas: number[] = [];
    let n = 0;
    const call = crearCallModel("k", {
        fetch: () => Promise.resolve(respuestas[Math.min(n++, respuestas.length - 1)]()),
        sleep: (ms) => { esperas.push(ms); return Promise.resolve(); },
    });
    return { call, esperas, llamadas: () => n };
};

Deno.test("529 y luego ok → responde tras un reintento", async () => {
    const m = montar([() => err(529), OK]);
    const r = await m.call({});
    assertEquals(r.stop_reason, "end_turn");
    assertEquals(m.llamadas(), 2);
    assertEquals(m.esperas, [1000]);
});

Deno.test("429 y 500 también se reintentan; 400 no", async () => {
    assertEquals((await montar([() => err(429, "2"), OK]).call({})).stop_reason, "end_turn");
    assertEquals((await montar([() => err(500), OK]).call({})).stop_reason, "end_turn");
    const m = montar([() => err(400), OK]);
    await assertRejects(() => m.call({}), ModelError, "http 400");
    assertEquals(m.llamadas(), 1);
});

Deno.test("dos fallos seguidos → ModelError (el handler responderá 502)", async () => {
    const m = montar([() => err(529), () => err(529)]);
    await assertRejects(() => m.call({}), ModelError, "http 529");
    assertEquals(m.llamadas(), 2);
});

Deno.test("retry-after de 10 s se trunca a 3 s; hasta 3 s se respeta", async () => {
    const a = montar([() => err(429, "10"), OK]);
    await a.call({});
    assertEquals(a.esperas, [3000]);
    assertEquals(esperaReintento("2"), 2000);
    assertEquals(esperaReintento(null), 1000);
    assertEquals(esperaReintento("basura"), 1000);
});

Deno.test("sin presupuesto para esperar y reintentar → ModelError sin segunda llamada", async () => {
    const m = montar([() => err(529, "3"), OK]);
    await assertRejects(() => m.call({}, { restanteMs: () => 2500 }), ModelError);
    assertEquals(m.llamadas(), 1);
    const agotado = montar([OK]);
    await assertRejects(() => agotado.call({}, { restanteMs: () => 0 }), ModelError, "presupuesto");
    assertEquals(agotado.llamadas(), 0);
});

Deno.test("fallo de red y JSON inválido son ModelError", async () => {
    const red = crearCallModel("k", { fetch: () => Promise.reject(new Error("net")) });
    await assertRejects(() => red({}), ModelError, "red");
    const mal = montar([() => new Response("no json", { status: 200 })]);
    await assertRejects(() => mal.call({}), ModelError, "respuesta no válida");
});

Deno.test("la petición lleva clave, versión y body; no se manda ninguna cabecera beta", async () => {
    let visto: RequestInit | undefined;
    const call = crearCallModel("clave-x", { fetch: (_u, i) => { visto = i; return Promise.resolve(OK()); } });
    await call({ model: "m" });
    const h = visto!.headers as Record<string, string>;
    assertEquals(h["x-api-key"], "clave-x");
    assertEquals(h["anthropic-version"], "2023-06-01");
    assert(!("anthropic-beta" in h));
    assertEquals(visto!.body, '{"model":"m"}');
});

Deno.test("integración con el handler: dos fallos → 502 y refund; 529+ok → 200", async () => {
    const registros: boolean[] = [];
    const base = (call: ReturnType<typeof crearCallModel>): HandlerDeps => ({
        verifyUser: () => Promise.resolve({ uid: "u" }),
        appUserId: () => Promise.resolve("1"),
        checkHomeMember: () => Promise.resolve(true),
        runInHome: (_h, fn) => fn(),
        usage: {
            consume: () => Promise.resolve({ allowed: true, used: 1, limit: 50, day: "2026-11-24" }),
            record: (_a, _d, _t, refund) => { registros.push(refund); return Promise.resolve(); },
        },
        callModel: call, model: "m", skills: [], env: () => "k", now: () => new Date(), log: () => {},
    });
    const req = () => new Request("https://x/asistente", {
        method: "POST",
        headers: { Authorization: "Bearer t", "X-Home-Id": "1" },
        body: JSON.stringify({ messages: [{ role: "user", content: "hola" }], timezone: "UTC" }),
    });
    assertEquals((await createHandler(base(montar([() => err(529), () => err(529)]).call))(req())).status, 502);
    assertEquals(registros, [true]);
    assertEquals((await createHandler(base(montar([() => err(529), OK]).call))(req())).status, 200);
    assertEquals(registros, [true, false]);
});
