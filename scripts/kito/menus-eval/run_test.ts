// Tests del script de comparación de modelos de menús: cliente falso, sin red ni clave.
import { assert, assertEquals } from "jsr:@std/assert@1";
import type { CallModel } from "../../../supabase/functions/asistente/core.ts";
import { cargarFixtures, conflictoDieta, costeUsd, evaluarHogar, main, modeloSimulado, resumir, tablaMarkdown, TARIFAS_POR_DEFECTO } from "./run.ts";

const DIR = new URL("./fixtures", import.meta.url).pathname;
const { hogares, recetas } = await cargarFixtures(DIR);
const por = (id: string) => hogares.find((h) => h.id.startsWith(id))!;

/** Modelo falso que propone un menú dado, sin leer nada, y gasta tokens conocidos. */
const proponiendo = (platos: Record<string, unknown>[], semana = "2030-01-07"): CallModel => {
    let n = 0;
    return () => {
        n++;
        return Promise.resolve(n === 1
            ? { stop_reason: "tool_use", content: [{ type: "tool_use", id: "t1", name: "proponer_menu", input: { semana, platos } }], usage: { input_tokens: 100, output_tokens: 50, cache_read_input_tokens: 10, cache_creation_input_tokens: 5 } }
            : { stop_reason: "end_turn", content: [{ type: "text", text: "listo" }], usage: { input_tokens: 200, output_tokens: 20 } });
    };
};

Deno.test("fixtures: entre 10 y 20 hogares con miembros, perfil, semana y mensaje; ids únicos", () => {
    assert(hogares.length >= 10 && hogares.length <= 20);
    assertEquals(new Set(hogares.map((h) => h.id)).size, hogares.length);
    for (const h of hogares) {
        assert((h.perfil.members as unknown[]).length > 0, h.id);
        assert(/^\d{4}-\d{2}-\d{2}$/.test(h.semana) && h.mensaje.length > 0, h.id);
    }
    assert(hogares.some((h) => (h.perfil.members as { allergies: unknown[] }[]).some((m) => m.allergies.length > 0)));
    assert(hogares.some((h) => h.historial !== undefined));
    assert(hogares.some((h) => (h.perfil.schedule as unknown[]).length > 0));
    assert(hogares.some((h) => (h.perfil.countries as unknown[]).length > 1));
});

Deno.test("evaluarHogar: un menú con pasta para una celiaca da conflicto de alergia; uno seguro da 0", async () => {
    const h = por("01");
    const malo = await evaluarHogar(h, recetas, "m-falso", proponiendo([{ dia: "2030-01-07", franja: "lunch", receta_id: 10 }, { dia: "2030-01-07", franja: "dinner", receta_id: 13 }]));
    assert(malo.ok);
    assert(malo.conflictos >= 1, "pasta con gluten");
    assert(malo.detalleConflictos.some((d) => d.includes("gluten")));
    assertEquals(malo.tarjeta, false, "con conflictos la skill no muestra el menú");
    assertEquals(malo.tokens, { input: 300, output: 70, cacheRead: 10, cacheWrite: 5 });
    assertEquals(malo.llamadas, 2);
    const bueno = await evaluarHogar(h, recetas, "m-falso", proponiendo([{ dia: "2030-01-07", franja: "lunch", receta_id: 13 }, { dia: "2030-01-07", franja: "dinner", receta_id: 22 }]));
    assertEquals(bueno.conflictos, 0);
    assertEquals(bueno.tarjeta, true);
});

Deno.test("evaluarHogar: cuenta repeticiones en la semana y contra el historial; título libre con alérgeno cuenta como conflicto", async () => {
    const h = por("03");
    const r = await evaluarHogar(h, recetas, "m", proponiendo([
        { dia: "2030-01-07", franja: "lunch", titulo: "Pollo asado con patatas" },
        { dia: "2030-01-08", franja: "lunch", titulo: "pollo asado con patatas" },
        { dia: "2030-01-09", franja: "lunch", receta_id: 11 },
    ]));
    assertEquals(r.repeticiones, 1);
    assertEquals(r.repeticionesHistorial, 2);
    const f = await evaluarHogar(por("08"), recetas, "m", proponiendo([{ dia: "2030-01-07", franja: "dinner", titulo: "Tostada con tahini" }]));
    assert(f.conflictos >= 1);
});

Deno.test("evaluarHogar: un fallo del modelo se registra sin romper", async () => {
    const r = await evaluarHogar(por("10"), recetas, "m", () => Promise.reject(new Error("http 500")));
    assertEquals(r.ok, false);
    assertEquals(r.error, "http 500");
});

Deno.test("coste y tabla: tarifas con caché y una fila por modelo", async () => {
    assertEquals(costeUsd({ input: 1e6, output: 1e6, cacheRead: 1e6, cacheWrite: 1e6 }, { entrada: 2, salida: 10 }), 2 + 10 + 0.2 + 2.5);
    const rs = [];
    for (const m of ["claude-haiku-5-5", "claude-sonnet-5-5"]) for (const h of hogares.slice(0, 3)) rs.push(await evaluarHogar(h, recetas, m, modeloSimulado(h, recetas)));
    const res = resumir(rs, TARIFAS_POR_DEFECTO);
    assertEquals(res.map((x) => x.modelo), ["claude-haiku-5-5", "claude-sonnet-5-5"]);
    assert(res[1].coste > res[0].coste);
    const t = tablaMarkdown(rs, TARIFAS_POR_DEFECTO);
    assert(t.includes("| claude-haiku-5-5 | 3 |") && t.includes("Detalle por hogar"));
});

Deno.test("main: sin --seco y sin ANTHROPIC_API_KEY sale sin llamar a nada (código 2)", async () => {
    const antes = Deno.env.get("ANTHROPIC_API_KEY");
    Deno.env.delete("ANTHROPIC_API_KEY");
    try {
        assertEquals(await main(["--hogares", "1"]), 2);
    } finally {
        if (antes !== undefined) Deno.env.set("ANTHROPIC_API_KEY", antes);
    }
});

Deno.test("conflictoDieta: las negaciones no cuentan y un plato con carne sí", () => {
    assertEquals(conflictoDieta("vegetarian", "Chili sin carne"), false);
    assertEquals(conflictoDieta("vegan", "Chili sin carne"), false);
    assertEquals(conflictoDieta("vegetarian", "Ensalada sin pescado"), false);
    assertEquals(conflictoDieta("vegan", "Bizcocho sin lactosa ni huevo"), false);
    assertEquals(conflictoDieta("vegan", "Pan sin gluten"), false);
    assertEquals(conflictoDieta("vegetarian", "Arroz con pollo"), true);
    assertEquals(conflictoDieta("vegan", "Tortilla de patatas"), true);
    assertEquals(conflictoDieta("halal", "Lentejas con chorizo"), true);
    // Receta con marisco (Pad thai): no es vegetariana aunque el título no lo diga.
    assertEquals(conflictoDieta("vegetarian", "Pad thai con cacahuetes", ["cacahuete", "huevo", "marisco"]), true);
});

Deno.test("fixtures: el pad thai lleva ingredientes sin food_id (no comprobable para dieta o alergias)", async () => {
    const recetas = JSON.parse(await Deno.readTextFile(new URL("./fixtures/recetas.json", import.meta.url)));
    const pad = recetas.find((r: { id: number }) => r.id === 30);
    assertEquals(pad.ingredientes.every((i: { food_id: unknown }) => i.food_id === null), true);
});
