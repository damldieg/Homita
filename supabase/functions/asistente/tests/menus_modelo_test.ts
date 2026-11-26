// T4 kito-menus: activación de la skill `menus` por intención y modelo propio (KITO_MODEL_MENUS ?? KITO_MODEL).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { elegirModelo, hayIntencion, MAX_TOOL_ROUNDS, runKito } from "../core.ts";
import type { ModelResponse, Skill, ToolCtx } from "../core.ts";
import { INTENCION_MENUS } from "../skills/menus/intencion.ts";
import { menus } from "../skills/menus/index.ts";
import { SKILLS } from "../skills/registry.ts";

const CTX: ToolCtx = { token: "t", uid: "u", homeId: "7", timezone: "Europe/Madrid", now: new Date("2026-11-26T10:00:00Z") };
const texto = (t: string): ModelResponse => ({ stop_reason: "end_turn", content: [{ type: "text", text: t }] });
const eco = { name: "eco", description: "d", input_schema: { type: "object" as const, properties: {} }, run: () => Promise.resolve({}) };
const otra: Skill = {
    id: "otra", nombre: "Otra", descripcion: "x", instrucciones: "SKILL-OTRA", herramientas: [eco], tarjetas: [], disponible: () => true,
};
// Skill de prueba con la misma forma que `menus` (intención, modelo y rondas) pero con una herramienta de verdad.
const conTool: Skill = { ...menus, instrucciones: "SKILL-MENUS", herramientas: [{ ...eco, name: "menu_eco" }] };
const ENV = (n: string) => (n === "KITO_MODEL_MENUS" ? "modelo-menus" : undefined);

const llamar = async (skills: Skill[], mensajes: { role: "user" | "assistant"; content: string }[], env = ENV) => {
    const cuerpos: Record<string, unknown>[] = [];
    await runKito({
        mensajes, ctx: CTX, skills, model: "base", env,
        callModel: (b) => {
            cuerpos.push(JSON.parse(JSON.stringify(b)));
            return Promise.resolve(texto("ok"));
        },
    });
    return cuerpos[0];
};

Deno.test("la skill menus está registrada con intención, secreto y tarjeta propios", () => {
    assert(SKILLS.includes(menus));
    assertEquals(menus.modelo, "KITO_MODEL_MENUS");
    assertEquals(menus.tarjetas, ["menu"]);
    assertEquals(menus.intencion, INTENCION_MENUS);
});

Deno.test("hayIntencion: palabras clave sin acentos ni mayúsculas; «semana» suelta no activa", () => {
    const hay = (t: string) => hayIntencion(INTENCION_MENUS, [{ role: "user", content: t }]);
    for (const t of [
        "Proponme el menú de la semana", "MENU semanal", "qué hacemos de comer? ideas de comidas", "las cenas de esta semana",
        "almuerzos para el lunes", "dame las recetas de la semana", "Menús",
        // rangos
        "planifica desde esta noche hasta el viernes a mediodía", "Desde el lunes por la noche hasta el viernes a mediodia",
        "organiza de esta noche a mediodía hasta el jueves a mediodía", "organiza qué cenar desde esta noche hasta el domingo por la noche",
    ]) assert(hay(t), t);
    for (const t of [
        "qué tengo esta semana", "crea una tarea para el viernes", "añade un evento mañana", "menudo día", "comidilla", "",
        // «desde», «hasta» y «esta noche» sueltos no son menú
        "eventos desde el lunes hasta el viernes", "recuérdame esta noche que llame a mamá", "tareas hasta el viernes a mediodía",
    ]) assert(!hay(t), t);
});

Deno.test("hayIntencion mira los últimos mensajes: el seguimiento «cambia el martes» sigue en menús", () => {
    const seguimiento = [
        { role: "user" as const, content: "proponme el menú" },
        { role: "assistant" as const, content: "Aquí lo tienes." },
        { role: "user" as const, content: "cambia el martes" },
    ];
    assert(hayIntencion(INTENCION_MENUS, seguimiento));
    const lejano = [{ role: "user" as const, content: "proponme el menú" }, ...Array(3).fill({ role: "user", content: "hola" })];
    assert(!hayIntencion(INTENCION_MENUS, lejano));
});

Deno.test("elegirModelo: con intención usa KITO_MODEL_MENUS; sin secreto o vacío, KITO_MODEL; una o varias skills", () => {
    assertEquals(elegirModelo([menus], ENV, "base"), "modelo-menus");
    assertEquals(elegirModelo([menus, otra], ENV, "base"), "modelo-menus");
    assertEquals(elegirModelo([otra, menus, otra], ENV, "base"), "modelo-menus");
    assertEquals(elegirModelo([menus], () => undefined, "base"), "base");
    assertEquals(elegirModelo([menus, otra], () => "   ", "base"), "base");
    assertEquals(elegirModelo([otra], ENV, "base"), "base");
    assertEquals(elegirModelo([], ENV, "base"), "base");
});

Deno.test("runKito: con intención de menú la skill entra y el modelo es el de menús", async () => {
    const b = await llamar([otra, conTool], [{ role: "user", content: "proponme el menú de la semana" }]);
    assertEquals(b.model, "modelo-menus");
    assert((b.system as { text: string }[])[0].text.includes("SKILL-MENUS"));
    assertEquals((b.tools as { name: string }[]).map((t) => t.name).sort(), ["eco", "menu_eco"]);
});

Deno.test("runKito: sin intención de menú la skill no entra (ni prompt ni herramientas) y se usa KITO_MODEL", async () => {
    const b = await llamar([otra, conTool], [{ role: "user", content: "qué eventos tengo esta semana" }]);
    assertEquals(b.model, "base");
    assert(!(b.system as { text: string }[])[0].text.includes("SKILL-MENUS"));
    assertEquals((b.tools as { name: string }[]).map((t) => t.name), ["eco"]);
});

Deno.test("runKito: con intención pero sin secreto KITO_MODEL_MENUS, KITO_MODEL", async () => {
    const b = await llamar([otra, conTool], [{ role: "user", content: "las cenas de la semana" }], () => undefined);
    assertEquals(b.model, "base");
    assertEquals((b.tools as unknown[]).length, 2);
});

Deno.test("rondas: menus permite más que MAX_TOOL_ROUNDS y las demás skills se quedan en MAX_TOOL_ROUNDS", async () => {
    assert((menus.maxRondas ?? 0) > MAX_TOOL_ROUNDS);
    const pide: ModelResponse = { stop_reason: "tool_use", content: [{ type: "tool_use", id: "t1", name: "menu_eco", input: {} }] };
    const contar = async (skills: Skill[], mensaje: string) => {
        let n = 0;
        const r = await runKito({
            mensajes: [{ role: "user", content: mensaje }], ctx: CTX, skills, model: "m", env: ENV,
            callModel: () => {
                n++;
                return Promise.resolve(pide);
            },
        });
        return { n, r };
    };
    const con = await contar([conTool], "el menú");
    assertEquals(con.n, (menus.maxRondas ?? 0) + 1);
    const sin = await contar([conTool], "hola");
    assertEquals(sin.n, MAX_TOOL_ROUNDS + 1); // sin intención, el límite sigue siendo el de siempre
});
