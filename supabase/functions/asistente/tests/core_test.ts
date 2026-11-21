// Tests del núcleo (core.ts): bucle con el modelo, herramientas, límites de rondas y registro de skills.
// Sin red ni BD: el modelo es una función falsa. Incluye una skill falsa que se añade sin tocar el núcleo.
import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { indexTools, MAX_TOOL_ROUNDS, runKito } from "../core.ts";
import type { ModelResponse, Skill, Tool, ToolCtx } from "../core.ts";

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
    const call = (body: Record<string, unknown>): Promise<ModelResponse> => {
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
    assert(String(primera.system).includes("SKILL-FALSA"));
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
    assert(!String(m.cuerpos[0].system).includes("SKILL-OCULTA"));
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
