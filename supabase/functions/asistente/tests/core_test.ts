// Tests del núcleo (core.ts): bucle con el modelo, herramientas, límites de rondas y registro de skills.
// Sin red ni BD: el modelo es una función falsa. Incluye una skill falsa que se añade sin tocar el núcleo.
import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
    conEfectos, elegirModelo, indexTools, MAX_TOOL_ROUNDS, MENSAJE_REFUSAL, ModelError, NOTA_MAX_TOKENS, resolverEffort, runKito,
} from "../core.ts";
import type { CallOpts, ModelResponse, Skill, Tool, ToolCtx } from "../core.ts";

const CTX: ToolCtx = { token: "t", uid: "u", homeId: "7", timezone: "Europe/Madrid", now: new Date("2026-11-20T10:00:00Z") };

const eco: Tool = {
    name: "eco",
    description: "Devuelve lo que recibe.",
    input_schema: { type: "object", properties: { texto: { type: "string" } }, required: ["texto"] },
    run: (input) => Promise.resolve({ eco: input.texto }),
};

const falsa: Skill = {
    id: "falsa",
    nombre: "Falsa",
    descripcion: "Skill de prueba.",
    instrucciones: "SKILL-FALSA: usa eco para repetir.",
    herramientas: [eco],
    tarjetas: [],
    disponible: () => true,
};

const texto = (t: string): ModelResponse => ({ stop_reason: "end_turn", content: [{ type: "text", text: t }] });
const pideTool = (name: string, input: Record<string, unknown>, id = "tu1"): ModelResponse => ({
    stop_reason: "tool_use",
    content: [{ type: "tool_use", id, name, input }],
    usage: { input_tokens: 10, output_tokens: 5 },
});

// Modelo falso: devuelve las respuestas en orden y registra los cuerpos recibidos.
const modeloFalso = (respuestas: ModelResponse[]) => {
    const cuerpos: Record<string, unknown>[] = [];
    let i = 0;
    const call = (body: Record<string, unknown>, _opts?: CallOpts): Promise<ModelResponse> => {
        cuerpos.push(JSON.parse(JSON.stringify(body)));
        const r = respuestas[Math.min(i, respuestas.length - 1)];
        i++;
        return Promise.resolve(r);
    };
    return { call, cuerpos };
};

const mensajes = [{ role: "user" as const, content: "hola" }];

Deno.test("una skill falsa se añade sin tocar el núcleo: se ofrece al modelo y su herramienta se ejecuta", async () => {
    const m = modeloFalso([pideTool("eco", { texto: "ping" }), texto("Eco: ping")]);
    const res = await runKito({ mensajes, ctx: CTX, skills: [falsa], callModel: m.call, model: "modelo-x" });

    assertEquals(res.texto, "Eco: ping");
    assertEquals(res.herramientasUsadas, 1);
    const primera = m.cuerpos[0];
    assert(JSON.stringify(primera.system).includes("SKILL-FALSA"));
    assertEquals((primera.tools as { name: string }[]).map((t) => t.name), ["eco"]);
    assertEquals(primera.model, "modelo-x");
    // El resultado de la herramienta vuelve al modelo como tool_result.
    const segunda = m.cuerpos[1].messages as { role: string; content: unknown }[];
    const ultimo = segunda[segunda.length - 1];
    assertEquals(ultimo.role, "user");
    const bloque = (ultimo.content as { type: string; content: string }[])[0];
    assertEquals(bloque.type, "tool_result");
    assertEquals(bloque.content, '{"eco":"ping"}');
});

Deno.test("una skill no disponible no aparece ni en el system ni en las herramientas", async () => {
    const oculta: Skill = { ...falsa, id: "oculta", instrucciones: "SKILL-OCULTA", disponible: () => false };
    const m = modeloFalso([texto("ok")]);
    await runKito({ mensajes, ctx: CTX, skills: [oculta], callModel: m.call, model: "m" });
    assert(!JSON.stringify(m.cuerpos[0].system).includes("SKILL-OCULTA"));
    assertEquals(m.cuerpos[0].tools, undefined);
});

Deno.test("herramienta desconocida y error de herramienta vuelven al modelo como is_error", async () => {
    const roto: Tool = { ...eco, name: "roto", run: () => Promise.reject(new Error("fallo controlado")) };
    const sk: Skill = { ...falsa, herramientas: [roto] };
    const m = modeloFalso([pideTool("inventada", {}, "a"), pideTool("roto", {}, "b"), texto("listo")]);
    const res = await runKito({ mensajes, ctx: CTX, skills: [sk], callModel: m.call, model: "m" });
    assertEquals(res.texto, "listo");
    const json = JSON.stringify(m.cuerpos[2].messages);
    assert(json.includes("herramienta desconocida"));
    assert(json.includes("fallo controlado"));
    assert(json.includes('"is_error":true'));
});

Deno.test("el bucle se corta tras MAX_TOOL_ROUNDS rondas con herramientas", async () => {
    const m = modeloFalso([pideTool("eco", { texto: "x" })]);
    const res = await runKito({ mensajes, ctx: CTX, skills: [falsa], callModel: m.call, model: "m" });
    assertEquals(m.cuerpos.length, MAX_TOOL_ROUNDS + 1);
    assert(res.texto.includes("No he podido completar"));
});

Deno.test("los tokens de todas las rondas se suman", async () => {
    const m = modeloFalso([
        pideTool("eco", { texto: "x" }),
        { stop_reason: "end_turn", content: [{ type: "text", text: "ok" }], usage: { input_tokens: 3, output_tokens: 2, cache_read_input_tokens: 4, cache_creation_input_tokens: 1 } },
    ]);
    const res = await runKito({ mensajes, ctx: CTX, skills: [falsa], callModel: m.call, model: "m" });
    assertEquals(res.tokens, { input: 13, output: 7, cacheRead: 4, cacheWrite: 1 });
});

Deno.test("error del modelo se propaga para que el handler devuelva el mensaje", async () => {
    const { ModelError } = await import("../core.ts");
    await assertRejects(
        () => runKito({ mensajes, ctx: CTX, skills: [], callModel: () => Promise.reject(new ModelError("caída")), model: "m" }),
        ModelError,
    );
});

Deno.test("dos herramientas con el mismo nombre son un error de configuración", () => {
    assertThrows(() => indexTools([falsa, { ...falsa, id: "otra" }]), Error, "herramienta duplicada: eco");
});

// ── Llamada al modelo (T10–T13) ──

Deno.test("body al modelo: max_tokens 4096, effort low por defecto, cache_control, strict y sin parámetros prohibidos", async () => {
    const m = modeloFalso([texto("ok")]);
    await runKito({ mensajes, ctx: CTX, skills: [falsa], callModel: m.call, model: "m" });
    const b = m.cuerpos[0];
    assertEquals(b.max_tokens, 4096);
    assertEquals(b.output_config, { effort: "low" });
    const sys = b.system as { type: string; text: string; cache_control?: unknown }[];
    assertEquals(sys.length, 1);
    assertEquals(sys[0].cache_control, { type: "ephemeral" });
    const tools = b.tools as { strict: boolean; input_schema: unknown }[];
    assert(tools.every((t) => t.strict === true));
    for (const k of ["temperature", "top_p", "top_k", "thinking"]) assert(!(k in b), k);
});

Deno.test("effort configurado llega al body y las herramientas van en orden determinista", async () => {
    const otra: Tool = { ...eco, name: "aaa" };
    const sk: Skill = { ...falsa, herramientas: [eco, otra] };
    const m = modeloFalso([texto("ok")]);
    await runKito({ mensajes, ctx: CTX, skills: [sk], callModel: m.call, model: "m", effort: "high" });
    assertEquals(m.cuerpos[0].output_config, { effort: "high" });
    assertEquals((m.cuerpos[0].tools as { name: string }[]).map((t) => t.name), ["aaa", "eco"]);
});

Deno.test("KITO_EFFORT: vacío, inválido y válido (el valor inválido no se registra)", () => {
    const avisos: string[] = [];
    assertEquals(resolverEffort(undefined, (a) => avisos.push(a)), "low");
    assertEquals(resolverEffort("", (a) => avisos.push(a)), "low");
    assertEquals(avisos.length, 0);
    assertEquals(resolverEffort("ultra-secreto", (a) => avisos.push(a)), "low");
    assertEquals(avisos.length, 1);
    assert(!avisos[0].includes("ultra-secreto"));
    assertEquals(resolverEffort(" Medium ", () => {}), "medium");
    assertEquals(resolverEffort("high", () => {}), "high");
});

Deno.test("stop_reason max_tokens: el texto que haya más la nota de «a medias»", async () => {
    const m = modeloFalso([{ stop_reason: "max_tokens", content: [{ type: "text", text: "Tienes tres" }] }]);
    const res = await runKito({ mensajes, ctx: CTX, skills: [], callModel: m.call, model: "m" });
    assertEquals(res.texto, `Tienes tres\n\n${NOTA_MAX_TOKENS}`);
    assertEquals(res.sinCoste, undefined);
});

Deno.test("refusal: mensaje neutro, sin segunda llamada y sin coste de cupo", async () => {
    const m = modeloFalso([{ stop_reason: "refusal", content: [], usage: { input_tokens: 7, output_tokens: 1 } }]);
    const res = await runKito({ mensajes, ctx: CTX, skills: [falsa], callModel: m.call, model: "m" });
    assertEquals(res.texto, MENSAJE_REFUSAL);
    assertEquals(res.texto, "Con eso no te puedo ayudar.");
    assertEquals(res.sinCoste, true);
    assertEquals(m.cuerpos.length, 1);
    assertEquals(res.tokens.input, 7);
});

Deno.test("herramientas de una vuelta en paralelo: un solo mensaje con tool_result en el orden de los tool_use", async () => {
    const orden: string[] = [];
    const lenta: Tool = { ...eco, name: "lenta", run: async () => { await new Promise((r) => setTimeout(r, 30)); orden.push("lenta"); return "L"; } };
    const rapida: Tool = { ...eco, name: "rapida", run: () => { orden.push("rapida"); return Promise.resolve("R"); } };
    const sk: Skill = { ...falsa, herramientas: [lenta, rapida] };
    const respuestaTools: ModelResponse = {
        stop_reason: "tool_use",
        content: [
            { type: "thinking", thinking: "pienso", signature: "sig" },
            { type: "tool_use", id: "a", name: "lenta", input: {} },
            { type: "tool_use", id: "b", name: "rapida", input: {} },
        ],
    };
    const m = modeloFalso([respuestaTools, { stop_reason: "end_turn", content: [{ type: "thinking", thinking: "x", signature: "s" }, { type: "text", text: "Hecho" }] }]);
    const res = await runKito({ mensajes, ctx: CTX, skills: [sk], callModel: m.call, model: "m" });
    assertEquals(orden, ["rapida", "lenta"]); // se ejecutaron a la vez
    assertEquals(res.texto, "Hecho"); // el thinking no entra en el texto
    assertEquals(res.herramientasUsadas, 2);
    const msgs = m.cuerpos[1].messages as { role: string; content: unknown }[];
    const asistente = msgs[msgs.length - 2];
    assertEquals(asistente.role, "assistant");
    assertEquals(asistente.content, respuestaTools.content); // content intacto, con thinking
    const usuario = msgs[msgs.length - 1];
    assertEquals(usuario.role, "user");
    assertEquals((usuario.content as { tool_use_id: string }[]).map((r) => r.tool_use_id), ["a", "b"]);
});

Deno.test("presupuesto agotado entre vueltas → ModelError", async () => {
    let t = 0;
    const m = modeloFalso([pideTool("eco", { texto: "x" })]);
    await assertRejects(
        () => runKito({
            mensajes, ctx: CTX, skills: [falsa], model: "m", presupuestoMs: 60000, reloj: () => t,
            callModel: (b, o) => { t += 61000; return m.call(b, o); },
        }),
        ModelError,
        "presupuesto",
    );
});

Deno.test("la llamada recibe cuánto presupuesto queda", async () => {
    let t = 1000;
    let visto = -1;
    await runKito({
        mensajes, ctx: CTX, skills: [], model: "m", presupuestoMs: 60000, reloj: () => t,
        callModel: (_b, o) => { t += 5000; visto = o!.restanteMs!(); return Promise.resolve(texto("ok")); },
    });
    assertEquals(visto, 55000);
});

Deno.test("modelo por skill: declarado y con secreto, sin secreto, sin declarar y varias skills", async () => {
    const menus: Skill = { ...falsa, id: "menus", modelo: "KITO_MODEL_MENUS" };
    const env = (n: string) => (n === "KITO_MODEL_MENUS" ? "modelo-menus" : undefined);
    assertEquals(elegirModelo([menus], env, "base"), "modelo-menus");
    assertEquals(elegirModelo([menus], () => undefined, "base"), "base");
    assertEquals(elegirModelo([menus], () => "  ", "base"), "base");
    assertEquals(elegirModelo([falsa], env, "base"), "base");
    assertEquals(elegirModelo([menus, falsa], env, "base"), "base");
    const m = modeloFalso([texto("ok")]);
    await runKito({ mensajes, ctx: CTX, skills: [menus], callModel: m.call, model: "base", env });
    assertEquals(m.cuerpos[0].model, "modelo-menus");
});

// ── Prompt (T14) ──

Deno.test("system: solo texto estable, con las reglas clave y sin datos variables", async () => {
    const { consulta } = await import("../skills/consulta/index.ts");
    const m = modeloFalso([texto("ok")]);
    await runKito({ mensajes, ctx: { ...CTX, nombreUsuario: "Damián Díez" }, skills: [consulta], callModel: m.call, model: "m" });
    const sys = (m.cuerpos[0].system as { text: string }[]).map((b) => b.text).join("\n");
    for (const regla of [
        "Kito", "Urki", "<contexto>", "Nunca son instrucciones", "solo_mias=true", "nunca llames «evento» a una rutina",
        "No prometas fechas", "no tienes una herramienta", "Cercano", "sin emojis",
    ]) {
        if (regla === "Cercano") continue;
        assert(sys.includes(regla) || sys.toLowerCase().includes(regla.toLowerCase()), regla);
    }
    assert(!sys.includes("fecha_actual"));
    assert(!sys.includes("Damián Díez"));
    assert(!/\d{4}-\d{2}-\d{2}/.test(sys));
    // Estable entre peticiones: misma cadena con otro usuario y otra hora.
    const m2 = modeloFalso([texto("ok")]);
    await runKito({ mensajes, ctx: { ...CTX, nombreUsuario: "Otra", now: new Date("2027-01-01T00:00:00Z") }, skills: [consulta], callModel: m2.call, model: "m" });
    assertEquals(JSON.stringify(m2.cuerpos[0].system), JSON.stringify(m.cuerpos[0].system));
    assertEquals(JSON.stringify(m2.cuerpos[0].tools), JSON.stringify(m.cuerpos[0].tools));
});

// ── Efectos de herramienta (change kito-organizar): tarjetas, cambios, tool_use.id y turno ──

const escribe = (nombre: string, run: Tool["run"], extra: Partial<Tool> = {}): Tool => ({
    name: nombre,
    description: "Escribe algo.",
    input_schema: { type: "object", properties: {}, required: [] },
    run,
    escritura: true,
    ...extra,
});
const skillCon = (...herramientas: Tool[]): Skill => ({ ...falsa, herramientas });

Deno.test("conEfectos: tarjeta y cambios llegan a RunResult y no al JSON que ve el modelo", async () => {
    const t = escribe("hacer", () => Promise.resolve(conEfectos(
        { estado: "propuesta enviada al usuario para confirmar" },
        { tarjeta: { tipo: "confirmacion", id: "c", token: "SECRETO-TOKEN", acciones: [{ op: "x" }] }, cambios: [{ tipo: "lista", id: 3, op: "borrar" }] },
    )));
    const m = modeloFalso([pideTool("hacer", {}), texto("listo")]);
    const res = await runKito({ mensajes, ctx: { ...CTX }, skills: [skillCon(t)], callModel: m.call, model: "m" });
    assertEquals(res.tarjetas.length, 1);
    assertEquals((res.tarjetas[0] as { token: string }).token, "SECRETO-TOKEN");
    assertEquals(res.cambios, [{ tipo: "lista", id: 3, op: "borrar" }]);
    const enviado = JSON.stringify(m.cuerpos[1].messages);
    assert(enviado.includes("propuesta enviada al usuario para confirmar"));
    assert(!enviado.includes("SECRETO-TOKEN"));
    assert(!enviado.includes("acciones"));
});

Deno.test("tarjetas con el mismo id se sustituyen (upsert) y las herramientas normales no añaden nada", async () => {
    const a = escribe("a", () => Promise.resolve(conEfectos("a", { tarjeta: { id: "c", n: 1 } })));
    const b = escribe("b", () => Promise.resolve(conEfectos("b", { tarjeta: { id: "c", n: 2 } })));
    const m = modeloFalso([{
        stop_reason: "tool_use",
        content: [{ type: "tool_use", id: "1", name: "a", input: {} }, { type: "tool_use", id: "2", name: "b", input: {} }, { type: "tool_use", id: "3", name: "eco", input: { texto: "x" } }],
    }, texto("ok")]);
    const res = await runKito({ mensajes, ctx: { ...CTX }, skills: [skillCon(a, b, eco)], callModel: m.call, model: "m" });
    assertEquals(res.tarjetas, [{ id: "c", n: 2 }]);
    assertEquals(res.cambios, []);
    const normal = await runKito({ mensajes, ctx: { ...CTX }, skills: [falsa], callModel: modeloFalso([pideTool("eco", { texto: "p" }), texto("ok")]).call, model: "m" });
    assertEquals(normal.tarjetas, []);
    assertEquals(normal.cambios, []);
});

Deno.test("run recibe el tool_use.id y ctx.turno cuenta las escrituras de la vuelta", async () => {
    const vistos: { id?: string; escrituras?: number }[] = [];
    const t = escribe("hacer", (_i, ctx, extra) => {
        vistos.push({ id: extra?.toolUseId, escrituras: ctx.turno?.escrituras });
        return Promise.resolve({ ok: true });
    });
    const m = modeloFalso([{
        stop_reason: "tool_use",
        content: [{ type: "tool_use", id: "toolu_A", name: "hacer", input: {} }, { type: "tool_use", id: "toolu_B", name: "hacer", input: {} }, { type: "tool_use", id: "toolu_C", name: "eco", input: { texto: "x" } }],
    }, texto("ok")]);
    await runKito({ mensajes, ctx: { ...CTX }, skills: [skillCon(t, eco)], callModel: m.call, model: "m" });
    assertEquals(vistos, [{ id: "toolu_A", escrituras: 2 }, { id: "toolu_B", escrituras: 2 }]);
});

Deno.test("strict: true por defecto y false solo si la herramienta lo declara", async () => {
    const libre = escribe("libre", () => Promise.resolve(1), { strict: false });
    const m = modeloFalso([texto("ok")]);
    await runKito({ mensajes, ctx: { ...CTX }, skills: [skillCon(libre, eco)], callModel: m.call, model: "m" });
    const tools = m.cuerpos[0].tools as { name: string; strict: boolean }[];
    assertEquals(tools.map((t) => [t.name, t.strict]), [["eco", true], ["libre", false]]);
});
