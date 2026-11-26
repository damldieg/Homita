// T8 kito-menus: guardar_receta, apuntar_compra y apuntar_preferencia con un mundo falso.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { indexTools } from "../core.ts";
import type { Tool } from "../core.ts";
import { menus } from "../skills/menus/index.ts";
import { apuntarCompraTool, apuntarPreferenciaTool, guardarRecetaTool } from "../skills/menus/escritura.ts";
import { abrir, ANA, crearMundo, ctxDe, LEO } from "./menus_util.ts";

type Obj = Record<string, unknown>;
const correr = (t: Tool, input: Obj, ctx: unknown, id = "toolu_1") => t.run(input, ctx as never, { toolUseId: id, orden: 0 } as never);

Deno.test("las tres herramientas están en la skill: escritura, strict false y sin propiedades extra", () => {
    const tools = indexTools([menus]);
    for (const n of ["guardar_receta", "apuntar_compra", "apuntar_preferencia"]) {
        const t = tools.get(n)!;
        assert(t, n);
        assertEquals([t.escritura, t.strict, t.input_schema.additionalProperties], [true, false, false], n);
    }
});

Deno.test("guardar_receta sin pasos se rechaza sin llamar al api", async () => {
    const m = crearMundo();
    const a = await correr(guardarRecetaTool, { nombre: "Sopa", pasos: [] }, ctxDe(m)) as Obj;
    assertEquals(a.falta, ["pasos"]);
    const b = await correr(guardarRecetaTool, { nombre: "Sopa", pasos: ["  ", "ok"] }, ctxDe(m)) as Obj;
    assertEquals(b.ok, false);
    assertEquals(m.escrituras.length, 0);
});

Deno.test("guardar_receta guarda con origin kito, pasos, enlaza alimentos exactos y avisa de los no enlazados", async () => {
    const m = crearMundo({ alimentos: [{ id: 77, name: "Huevo" }, { id: 78, name: "Huevo de codorniz" }] });
    const { valor, cambios } = abrir(await correr(guardarRecetaTool, {
        nombre: "Revuelto", raciones: 2, franjas: ["dinner", "nope"], pasos: ["Batir", "Cocinar"],
        ingredientes: [{ nombre: "huevo", cantidad: 3, unidad: "ud" }, { nombre: "azafrán" }],
    }, ctxDe(m)));
    assertEquals(valor.ok, true);
    assertEquals(typeof valor.receta_id, "number");
    assertEquals(valor.ingredientes_sin_enlazar, ["azafrán"]);
    const c = m.escrituras[0].cuerpo;
    assertEquals([c.origin, c.steps, c.servings, c.slots], ["kito", ["Batir", "Cocinar"], 2, ["dinner"]]);
    assertEquals((c.ingredients as Obj[])[0].food_id, 77);
    assertEquals((c.ingredients as Obj[])[1].food_id, undefined);
    assertEquals(cambios, [{ tipo: "receta", id: valor.receta_id, op: "crear" }]);
});

Deno.test("guardar_receta es idempotente: repetirla no duplica", async () => {
    const m = crearMundo();
    const entrada = { nombre: "Sopa", pasos: ["Hervir"] };
    const a = abrir(await correr(guardarRecetaTool, entrada, ctxDe(m))).valor;
    const b = abrir(await correr(guardarRecetaTool, entrada, ctxDe(m))).valor;
    assertEquals(a.receta_id, b.receta_id);
    assertEquals(m.claves.size, 1);
    assertEquals(m.recetas.filter((r) => r.name === "Sopa").length, 1);
});

Deno.test("guardar_receta valida unidades y cantidades de los ingredientes", async () => {
    const m = crearMundo();
    const r = await correr(guardarRecetaTool, { nombre: "X", pasos: ["a"], ingredientes: [{ nombre: "sal", unidad: "cubos" }] }, ctxDe(m)) as Obj;
    assertEquals(r.ok, false);
    assertEquals(m.escrituras.length, 0);
});

Deno.test("apuntar_compra apunta con clave por tool_use: el reintento no duplica y otra petición sí", async () => {
    const m = crearMundo();
    const entrada = { articulos: [{ nombre: "Leche", cantidad: 2, unidad: "l" }, { nombre: "Huevos" }] };
    const { valor, cambios } = abrir(await correr(apuntarCompraTool, entrada, ctxDe(m), "toolu_a"));
    assertEquals(valor.apuntados, ["Leche", "Huevos"]);
    assertEquals(cambios, [{ tipo: "compra", id: null, op: "crear" }]);
    await correr(apuntarCompraTool, entrada, ctxDe(m), "toolu_a");
    assertEquals(m.claves.size, 2, "mismo tool_use: sin duplicados");
    await correr(apuntarCompraTool, entrada, ctxDe(m), "toolu_b");
    assertEquals(m.claves.size, 4);
});

Deno.test("apuntar_compra rechaza vacío, demasiados artículos y entradas mal formadas", async () => {
    const m = crearMundo();
    assertEquals(((await correr(apuntarCompraTool, { articulos: [] }, ctxDe(m))) as Obj).falta, ["articulos"]);
    const muchos = { articulos: Array.from({ length: 21 }, (_, i) => ({ nombre: `a${i}` })) };
    assertEquals(((await correr(apuntarCompraTool, muchos, ctxDe(m))) as Obj).ok, false);
    const r = await correr(apuntarCompraTool, { articulos: [{ cantidad: 1 }, { nombre: "Sal", unidad: "cubos" }] }, ctxDe(m)) as Obj;
    assertEquals((r.fallos as string[]).length, 2);
    assertEquals(m.escrituras.length, 0);
});

Deno.test("apuntar_preferencia sin confirmación del usuario no hace nada", async () => {
    const m = crearMundo();
    for (const c of [undefined, false, "true"]) {
        const r = await correr(apuntarPreferenciaTool, { persona_id: LEO, tipo: "no_le_gusta", valor: "coliflor", confirmado_por_usuario: c }, ctxDe(m)) as Obj;
        assertEquals(r.ok, false);
    }
    assertEquals(m.escrituras.length, 0);
    assertEquals(m.lecturas.length, 0);
});

Deno.test("apuntar_preferencia con confirmación añade a no le gusta (C1), favoritos (C2) y picante (C4) sin duplicar", async () => {
    const m = crearMundo();
    const base = { persona_id: LEO, confirmado_por_usuario: true };
    assertEquals(((await correr(apuntarPreferenciaTool, { ...base, tipo: "no_le_gusta", valor: "Brócoli" }, ctxDe(m))) as Obj).ok, true);
    assertEquals(m.escrituras[0].cuerpo, { home_member_id: LEO, dislikes: ["Brócoli"] });
    assertEquals(((await correr(apuntarPreferenciaTool, { ...base, tipo: "le_encanta", valor: "milanesas" }, ctxDe(m))) as Obj).ok, true);
    assertEquals(m.escrituras[1].cuerpo, { home_member_id: LEO, favorites: ["pasta", "milanesas"] });
    // ya apuntado (sin acentos ni mayúsculas): no escribe
    const dup = await correr(apuntarPreferenciaTool, { ...base, tipo: "le_encanta", valor: "PASTA" }, ctxDe(m)) as Obj;
    assertEquals(dup.hecho, "Ya estaba apuntado.");
    assertEquals(m.escrituras.length, 2);
    assertEquals(((await correr(apuntarPreferenciaTool, { persona_id: ANA, confirmado_por_usuario: true, tipo: "picante", valor: "3" }, ctxDe(m))) as Obj).ok, true);
    assertEquals(m.escrituras[2].cuerpo, { home_member_id: ANA, spice: 3 });
});

Deno.test("apuntar_preferencia valida persona, tipo y picante", async () => {
    const m = crearMundo();
    const ok = { confirmado_por_usuario: true };
    assertEquals(((await correr(apuntarPreferenciaTool, { ...ok, persona_id: 999, tipo: "no_le_gusta", valor: "x" }, ctxDe(m))) as Obj).ok, false);
    assertEquals(((await correr(apuntarPreferenciaTool, { ...ok, persona_id: LEO, tipo: "picante", valor: "9" }, ctxDe(m))) as Obj).ok, false);
    assert(Array.isArray(((await correr(apuntarPreferenciaTool, { ...ok, persona_id: LEO, tipo: "otro", valor: "x" }, ctxDe(m))) as Obj).falta));
    assertEquals(m.escrituras.length, 0);
});
