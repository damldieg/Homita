// La regla compartida que protege al menú: conflictos del servidor + «sin comprobar» con dieta o alergias.
import { assertEquals } from "jsr:@std/assert@1";
import { comprobar, evaluar, recetasNoComprobables } from "../conflictos.ts";
import type { Leer } from "../tipos.ts";

const PERFIL_SIN = { members: [{ home_member_id: 1, name: "Ana", allergies: [], diet: null }] };
const PERFIL_DIETA = { members: [{ home_member_id: 1, name: "Ana", allergies: [], diet: "vegetarian" }] };
const PERFIL_ALERGIA = { members: [{ home_member_id: 1, name: "Ana", allergies: [{ allergen: "gluten" }], diet: null }] };

const plan = (extra: Record<string, unknown> = {}) => ({
    id: 5, unchecked_item_ids: [11],
    items: [{ id: 11, kind: "recipe", title: "Guiso", day: "2030-01-08", slot: "lunch", members: [1] }],
    ...extra,
});

const lector = (respuestas: Record<string, unknown>): { leer: Leer; llamadas: string[] } => {
    const llamadas: string[] = [];
    return {
        llamadas,
        leer: (ruta, params) => {
            llamadas.push(`${ruta}?${JSON.stringify(params ?? {})}`);
            return Promise.resolve(respuestas[ruta]);
        },
    };
};

Deno.test("comprobar: lista de conflictos o null si el servidor no da lista", async () => {
    assertEquals(await comprobar(lector({ "meal/plan/check": [{ code: "diet" }] }).leer, 5), [{ code: "diet" }]);
    assertEquals(await comprobar(lector({ "meal/plan/check": { error: "x" } }).leer, 5), null);
});

Deno.test("evaluar: sin comprobar + dieta -> bloquea", async () => {
    const { leer } = lector({ "meal/plan/check": [] });
    const r = await evaluar(leer, plan(), PERFIL_DIETA);
    assertEquals(r.estado, "sin_comprobar");
});

Deno.test("evaluar: sin comprobar + alergia -> bloquea", async () => {
    const { leer } = lector({ "meal/plan/check": [] });
    assertEquals((await evaluar(leer, plan(), PERFIL_ALERGIA)).estado, "sin_comprobar");
});

Deno.test("evaluar: sin comprobar sin restricciones -> ok; texto libre sin comprobar no bloquea", async () => {
    const { leer } = lector({ "meal/plan/check": [] });
    assertEquals((await evaluar(leer, plan(), PERFIL_SIN)).estado, "ok");
    const libre = plan({ items: [{ id: 11, kind: "free_text", title: "Algo", members: [1] }] });
    assertEquals((await evaluar(leer, libre, PERFIL_DIETA)).estado, "ok");
});

Deno.test("evaluar: conflictos del servidor compactados con nombre y plato; sin lista -> no_comprobado", async () => {
    const c = [{ item_id: 11, day: "2030-01-08", slot: "lunch", member_id: 1, code: "allergen", detail: { allergen: "gluten" } }];
    const r = await evaluar(lector({ "meal/plan/check": c }).leer, plan({ unchecked_item_ids: [] }), PERFIL_SIN);
    assertEquals(r, {
        estado: "conflictos",
        conflictos: [{ casilla: 11, plato: "Guiso", dia: "2030-01-08", franja: "comida", persona: "Ana", tipo: "alergia", detalle: { allergen: "gluten" } }],
    });
    assertEquals((await evaluar(lector({ "meal/plan/check": null }).leer, plan(), PERFIL_SIN)).estado, "no_comprobado");
    assertEquals((await evaluar(lector({}).leer, { items: [] }, PERFIL_SIN)).estado, "no_comprobado");
});

Deno.test("recetasNoComprobables: solo mira recetas que come alguien con restricciones", async () => {
    const { leer, llamadas } = lector({ "recipe/detail": { ingredients: [{ food_id: 1 }, { label: "sal" }] } });
    assertEquals(await recetasNoComprobables(leer, PERFIL_SIN, [{ receta_id: 3, donde: "plato 1", comen: [1] }]), []);
    assertEquals(llamadas.length, 0);
    const e = await recetasNoComprobables(leer, PERFIL_DIETA, [{ receta_id: 3, donde: "plato 1", comen: [1] }]);
    assertEquals(e.length, 1);
    assertEquals(e[0].startsWith("plato 1: la receta 3 tiene ingredientes sin catálogo"), true);
    // sin lector utilizable -> falla cerrado
    const roto: Leer = () => Promise.reject(new Error("x"));
    assertEquals((await recetasNoComprobables(roto, PERFIL_DIETA, [{ receta_id: 3, donde: "p", comen: [1] }])).length, 1);
});
