// Compra compartida: forma compacta, filtros y rutas que lee. Respuestas falsas, sin red.
import { assertEquals, assertFalse } from "jsr:@std/assert@1";
import { verCompra } from "../compra.ts";
import type { LecturaCtx } from "../tipos.ts";

const base = { homeId: "7", timezone: "Europe/Madrid", now: new Date("2030-01-07T10:00:00Z") };

const conLector = (respuestas: Record<string, unknown>) => {
    const llamadas: { ruta: string; params: Record<string, string | undefined> | undefined }[] = [];
    const ctx: LecturaCtx = {
        ...base,
        leer: (ruta, params) => {
            llamadas.push({ ruta, params });
            return Promise.resolve(respuestas[ruta]);
        },
    };
    return { ctx, llamadas };
};

const COMPRA = {
    revision: 4,
    items: [
        { id: 1, label: "Leche", quantity: 2, unit: "l", section: "lácteos", state: "pending", plan_id: 9, sources: [] },
        { id: 2, label: "Pan", quantity: "1.5", unit: "ud", section: "panadería", state: "checked", plan_id: null },
        { id: 3, label: "Sal", quantity: null, unit: "ud", section: "otros", state: "skipped", plan_id: 9 },
    ],
};

Deno.test("verCompra: lee shopping y compacta los artículos", async () => {
    const { ctx, llamadas } = conLector({ shopping: COMPRA });
    const out = await verCompra({}, ctx);
    assertEquals(llamadas, [{ ruta: "shopping", params: undefined }]);
    assertEquals(out.tipo, "compra");
    assertEquals(out.revision, 4);
    assertEquals(out.hay_mas, false);
    assertEquals(out.elementos, [
        { id: 1, articulo: "Leche", cantidad: 2, unidad: "l", seccion: "lácteos", estado: "pendiente", de_menu: true },
        { id: 2, articulo: "Pan", cantidad: 1.5, unidad: "ud", seccion: "panadería", estado: "comprado", de_menu: false },
        { id: 3, articulo: "Sal", cantidad: null, unidad: "ud", seccion: "otros", estado: "ya lo tengo", de_menu: true },
    ]);
});

Deno.test("verCompra: solo_pendientes quita lo comprado y lo que ya hay en casa", async () => {
    const { ctx } = conLector({ shopping: COMPRA });
    const out = await verCompra({ solo_pendientes: true }, ctx);
    assertEquals((out.elementos as { id: number }[]).map((a) => a.id), [1]);
});

Deno.test("verCompra: con plan_id lee shopping/preview y junta las recetas de origen", async () => {
    const { ctx, llamadas } = conLector({
        "shopping/preview": {
            plan_id: 9,
            items: [{ label: "Tomate", quantity: 3, unit: "ud", section: "frutería", sources: [{ name: "Gazpacho" }, { name: "Gazpacho" }, { name: "Ensalada" }] }],
        },
    });
    const out = await verCompra({ plan_id: 9 }, ctx);
    assertEquals(llamadas, [{ ruta: "shopping/preview", params: { plan_id: "9" } }]);
    assertEquals(out.tipo, "previsualizacion");
    assertEquals(out.plan_id, 9);
    assertEquals(out.elementos, [{ articulo: "Tomate", cantidad: 3, unidad: "ud", seccion: "frutería", recetas: ["Gazpacho", "Ensalada"] }]);
});

Deno.test("verCompra: tope de 50 con hay_mas y texto largo acotado", async () => {
    const items = Array.from({ length: 60 }, (_, i) => ({ id: i, label: "x".repeat(200), quantity: 1, unit: "ud", state: "pending" }));
    const { ctx } = conLector({ shopping: { revision: 1, items } });
    const out = await verCompra({}, ctx);
    const el = out.elementos as { articulo: string }[];
    assertEquals(el.length, 50);
    assertEquals(out.hay_mas, true);
    assertEquals(el[0].articulo.length, 80);
});

Deno.test("verCompra: una respuesta de error del api da el error compacto, sin el cuerpo", async () => {
    const { ctx } = conLector({ shopping: { error: 403, detalle: "secreto" } });
    const out = await verCompra({}, ctx);
    assertEquals(out.codigo, 403);
    assertFalse(JSON.stringify(out).includes("secreto"));
});
