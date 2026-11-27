// guardar_receta (criterio 9): pasos e ingredientes obligatorios sin llamar al api; mapeo de ingredientes; idempotencia.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { crearMundo, llamarTool } from "./util.ts";

const FOOD = [
    { id: 1, home_id: null, name: "Huevo", allergens: ["huevo"] },
    { id: 2, home_id: 7, name: "Harina de trigo", allergens: ["gluten"] },
];
const CREADA = { ok: true, status: 201, data: { id: 33, name: "Tortilla", ingredients: [{ food_id: 1, label: "Huevo", quantity: 4, unit: "ud", optional: false }], allergens: ["huevo"] } };

const mundo = (escritura: Record<string, never> | Record<string, typeof CREADA> = { "POST recipe/create": CREADA }) =>
    crearMundo({ food: FOOD }, {}, {}, escritura as never);

const BASE = { nombre: "Tortilla", pasos: ["Batir", "Cuajar"], ingredientes: [{ texto: "huevo", cantidad: 4, unidad: "ud" }] };

Deno.test("sin pasos o sin ingredientes: error en español y no se llama al api", async () => {
    for (const args of [{ ...BASE, pasos: [] }, { ...BASE, ingredientes: [] }, { ...BASE, pasos: ["  "] }]) {
        const m = mundo();
        const { resultado } = await llamarTool(m, "guardar_receta", args);
        assertEquals(resultado?.isError, true, JSON.stringify(args));
        assertEquals(m.escrituras, []);
        assertEquals(m.llamadas.filter((l) => l.ruta !== "home"), []);
    }
});

Deno.test("ingrediente con texto que no está en el catálogo: error útil con el texto que falta y sin escribir", async () => {
    const m = mundo();
    const { resultado, datos } = await llamarTool(m, "guardar_receta", { ...BASE, ingredientes: [{ texto: "huevo" }, { texto: "Azafrán" }] });
    assertEquals(resultado?.isError, true);
    assertStringIncludes(resultado?.content[0].text ?? "", "crear_alimento");
    assertEquals((datos as { sin_alimento: string[] }).sin_alimento, ["Azafrán"]);
    assertEquals(m.escrituras, []);
});

Deno.test("ingrediente sin alimento_id ni texto, unidad o cantidad inválidas: error sin escribir", async () => {
    for (const ing of [{}, { texto: "huevo", unidad: "tazas" }, { texto: "huevo", cantidad: -1 }]) {
        const m = mundo();
        const { resultado } = await llamarTool(m, "guardar_receta", { ...BASE, ingredientes: [ing] });
        assertEquals(resultado?.isError, true, JSON.stringify(ing));
        assertEquals(m.escrituras, []);
    }
});

Deno.test("receta válida: POST recipe/create con origin kito, food_id resuelto, JWT y hogar; devuelve receta_id", async () => {
    const m = mundo();
    const { resultado, datos } = await llamarTool(m, "guardar_receta", { ...BASE, raciones: 2, minutos: 20, franjas: ["dinner"] });
    assertEquals(resultado?.isError, undefined);
    assertEquals(m.escrituras.length, 1);
    const e = m.escrituras[0];
    assertEquals([e.metodo, e.ruta, e.hogar], ["POST", "recipe/create", "7"]);
    assertEquals(e.cuerpo.origin, "kito");
    assertEquals(e.cuerpo.servings, 2);
    assertEquals(e.cuerpo.minutes, 20);
    assertEquals(e.cuerpo.slots, ["dinner"]);
    assertEquals(e.cuerpo.steps, ["Batir", "Cuajar"]);
    assertEquals(e.cuerpo.ingredients, [{ food_id: 1, label: "huevo", quantity: 4, unit: "ud" }]);
    assert(/^[0-9a-f-]{36}$/.test(String(e.cuerpo.client_request_id)));
    const d = datos as Record<string, unknown>;
    assertEquals(d.receta_id, 33);
    assertEquals(d.alergenos, ["huevo"]);
});

Deno.test("alimento_id explícito se envía tal cual (sin buscar) y el reintento usa el mismo client_request_id", async () => {
    const m = mundo();
    const args = { ...BASE, ingredientes: [{ alimento_id: 2, cantidad: 100, unidad: "g" }] };
    await llamarTool(m, "guardar_receta", args);
    await llamarTool(m, "guardar_receta", args);
    assertEquals(m.escrituras[0].cuerpo.ingredients, [{ food_id: 2, quantity: 100, unit: "g" }]);
    assertEquals(m.llamadas.filter((l) => l.ruta === "food"), []);
    assertEquals(m.escrituras[0].cuerpo.client_request_id, m.escrituras[1].cuerpo.client_request_id);
    const otra = mundo();
    await llamarTool(otra, "guardar_receta", { ...args, nombre: "Otra" });
    assert(otra.escrituras[0].cuerpo.client_request_id !== m.escrituras[0].cuerpo.client_request_id);
});

Deno.test("el api rechaza un alimento (400): mensaje con la pista, sin el cuerpo crudo; 403 permiso", async () => {
    const m = mundo({ "POST recipe/create": { ok: false, status: 400, data: { error: "Invalid recipe" }, error: "Invalid recipe" } } as never);
    const { resultado } = await llamarTool(m, "guardar_receta", { ...BASE, ingredientes: [{ alimento_id: 999 }] });
    assertEquals(resultado?.isError, true);
    assertStringIncludes(resultado?.content[0].text ?? "", "alimento_id");
    const p = mundo({ "POST recipe/create": { ok: false, status: 403, data: null } } as never);
    assertStringIncludes((await llamarTool(p, "guardar_receta", BASE)).resultado?.content[0].text ?? "", "No tienes permiso");
});
