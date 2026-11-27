// apuntar_compra y marcar_comprado (criterio 11): idempotencia por día, éxito parcial, desmarcar.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { crearMundo, llamarTool } from "./util.ts";
import type { EscrituraFalsa } from "./util.ts";

const CREA: EscrituraFalsa = (cuerpo, n) => ({ ok: true, status: 201, data: { id: 100 + n, label: cuerpo.label } });

Deno.test("apuntar_compra: POST shopping/item/create por artículo con client_request_id y hogar", async () => {
    const m = crearMundo({}, {}, {}, { "POST shopping/item/create": CREA });
    const { resultado, datos } = await llamarTool(m, "apuntar_compra", {
        articulos: [{ etiqueta: "Leche", cantidad: 2, unidad: "l" }, { alimento_id: 5 }],
    });
    assertEquals(resultado?.isError, undefined);
    assertEquals(m.escrituras.length, 2);
    assertEquals(m.escrituras[0].cuerpo.label, "Leche");
    assertEquals(m.escrituras[0].cuerpo.quantity, 2);
    assertEquals(m.escrituras[0].cuerpo.unit, "l");
    assertEquals(m.escrituras[1].cuerpo.food_id, 5);
    assertEquals(m.escrituras[0].hogar, "7");
    assert(/^[0-9a-f-]{36}$/.test(String(m.escrituras[0].cuerpo.client_request_id)));
    assertNotEquals(m.escrituras[0].cuerpo.client_request_id, m.escrituras[1].cuerpo.client_request_id);
    assertEquals((datos as { ok: boolean }).ok, true);
});

Deno.test("idempotencia por día: mismo artículo el mismo día = mismo id (aunque cambie mayúsculas); otro día, otro", async () => {
    const dia = (iso: string) => crearMundo({}, { now: () => new Date(iso) }, {}, { "POST shopping/item/create": CREA });
    const id = async (m: ReturnType<typeof crearMundo>, etiqueta: string) => {
        await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta }] });
        return m.escrituras.at(-1)!.cuerpo.client_request_id;
    };
    const a = dia("2030-01-07T10:00:00Z");
    const mismo = await id(a, "Leche");
    assertEquals(await id(a, "leche"), mismo);
    assertEquals(await id(dia("2030-01-07T20:00:00Z"), "Leche"), mismo);
    assertNotEquals(await id(dia("2030-01-08T10:00:00Z"), "Leche"), mismo);
    assertNotEquals(await id(a, "Pan"), mismo);
});

Deno.test("apuntar_compra: éxito parcial, todo falla -> error, validaciones sin llamar", async () => {
    const parcial = crearMundo({}, {}, {}, {
        "POST shopping/item/create": (c, n) => n === 2 ? { ok: false, status: 403, data: null } : { ok: true, status: 201, data: { id: n, label: c.label } },
    });
    const { resultado, datos } = await llamarTool(parcial, "apuntar_compra", { articulos: [{ etiqueta: "A" }, { etiqueta: "B" }, { etiqueta: "C" }] });
    assertEquals(resultado?.isError, undefined);
    const d = datos as { ok: boolean; apuntados: unknown[]; fallos: string[] };
    assertEquals([d.ok, d.apuntados.length, d.fallos.length], [false, 2, 1]);
    assertStringIncludes(d.fallos[0], "«B»");

    const todo = crearMundo({}, {}, {}, { "POST shopping/item/create": { ok: false, status: 500, data: null } });
    assertEquals((await llamarTool(todo, "apuntar_compra", { articulos: [{ etiqueta: "A" }] })).resultado?.isError, true);

    for (const articulos of [[], [{}], [{ etiqueta: "A", unidad: "tazas" }], [{ etiqueta: "A", cantidad: -1 }], Array(21).fill({ etiqueta: "A" })]) {
        const m = crearMundo();
        assertEquals((await llamarTool(m, "apuntar_compra", { articulos })).resultado?.isError, true, JSON.stringify(articulos).slice(0, 40));
        assertEquals(m.escrituras, []);
    }
});

Deno.test("marcar_comprado: checked, desmarcar con pending y skipped; ids repetidos una sola vez", async () => {
    for (const estado of ["checked", "pending", "skipped"]) {
        const m = crearMundo({}, {}, {}, { "PATCH shopping/item/check": { ok: true, status: 200, data: {} } });
        const { resultado, datos } = await llamarTool(m, "marcar_comprado", { item_ids: [3, 4, 3], estado });
        assertEquals(resultado?.isError, undefined);
        assertEquals(m.escrituras.map((e) => e.cuerpo), [{ id: 3, state: estado }, { id: 4, state: estado }]);
        assertEquals(datos, { ok: true, estado, actualizados: [3, 4] });
        assertEquals(m.escrituras[0].hogar, "7");
    }
});

Deno.test("marcar_comprado: éxito parcial, todo falla -> error; estado inválido o sin ids no llama", async () => {
    const m = crearMundo({}, {}, {}, { "PATCH shopping/item/check": (c) => c.id === 4 ? { ok: false, status: 404, data: null } : { ok: true, status: 200, data: {} } });
    const { resultado, datos } = await llamarTool(m, "marcar_comprado", { item_ids: [3, 4], estado: "checked" });
    assertEquals(resultado?.isError, undefined);
    assertEquals((datos as { actualizados: number[] }).actualizados, [3]);
    assertEquals((datos as { fallos: { item_id: number }[] }).fallos[0].item_id, 4);
    const t = crearMundo({}, {}, {}, { "PATCH shopping/item/check": { ok: false, status: 404, data: null } });
    assertEquals((await llamarTool(t, "marcar_comprado", { item_ids: [4], estado: "checked" })).resultado?.isError, true);
    for (const args of [{ item_ids: [], estado: "checked" }, { item_ids: [1], estado: "hecho" }, { item_ids: Array.from({ length: 51 }, (_, i) => i + 1), estado: "checked" }]) {
        const x = crearMundo();
        assertEquals((await llamarTool(x, "marcar_comprado", args)).resultado?.isError, true);
        assertEquals(x.escrituras, []);
    }
});

// Servidor falso de artículos: replay por client_request_id (devuelve el artículo tal como está, 404 si se borró).
const servidorCompra = () => {
    const porClave = new Map<string, number>();
    const items = new Map<number, { id: number; label: unknown; state: string }>();
    let sig = 1;
    return {
        items,
        porClave,
        crea: ((c: Record<string, unknown>) => {
            const k = String(c.client_request_id);
            if (porClave.has(k)) {
                const it = items.get(porClave.get(k)!);
                return it ? { ok: true, status: 201, data: { ...it } } : { ok: false, status: 404, data: null, error: "Not Found" };
            }
            const it = { id: sig++, label: c.label, state: "pending" };
            items.set(it.id, it);
            porClave.set(k, it.id);
            return { ok: true, status: 201, data: { ...it } };
        }) as EscrituraFalsa,
    };
};
const ids = (d: unknown) => ((d as { apuntados: { item_id: number }[] }).apuntados).map((a) => a.item_id);

Deno.test("reintento idéntico el mismo día: mismo artículo, sin duplicar", async () => {
    const srv = servidorCompra();
    const m = crearMundo({}, {}, {}, { "POST shopping/item/create": srv.crea });
    const a = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche" }] });
    const b = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "leche" }] });
    assertEquals(ids(a.datos), ids(b.datos));
    assertEquals(srv.items.size, 1);
    assertEquals(m.escrituras.length, 2);
});

Deno.test("reintento tras borrar el artículo (404 del replay): se recrea con otra clave y el cliente recibe el nuevo", async () => {
    const srv = servidorCompra();
    const m = crearMundo({}, {}, {}, { "POST shopping/item/create": srv.crea });
    const a = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche" }] });
    srv.items.delete(ids(a.datos)[0]);
    const b = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche" }] });
    assertEquals(b.resultado?.isError, undefined);
    assertNotEquals(ids(b.datos)[0], ids(a.datos)[0]);
    assertEquals(srv.items.get(ids(b.datos)[0])?.state, "pending");
    assertEquals(m.escrituras.length, 3, "alta, replay 404 y alta con la clave siguiente");
    assertNotEquals(m.escrituras[2].cuerpo.client_request_id, m.escrituras[1].cuerpo.client_request_id);
    // un tercer intento idéntico vuelve a ser idempotente sobre el artículo recreado
    const c = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche" }] });
    assertEquals(ids(c.datos), ids(b.datos));
});

Deno.test("reintento cuando el artículo ya está comprado o «ya lo tengo»: se vuelve a apuntar como pendiente", async () => {
    const srv = servidorCompra();
    const m = crearMundo({}, {}, {}, { "POST shopping/item/create": srv.crea });
    const a = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Pan" }] });
    srv.items.get(ids(a.datos)[0])!.state = "checked";
    const b = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Pan" }] });
    assertNotEquals(ids(b.datos)[0], ids(a.datos)[0]);
    assertEquals(srv.items.get(ids(b.datos)[0])?.state, "pending");
    assertEquals(srv.items.size, 2);
});

Deno.test("mismo día con etiqueta distinta (o alimento distinto): artículo nuevo", async () => {
    const srv = servidorCompra();
    const m = crearMundo({}, {}, {}, { "POST shopping/item/create": srv.crea });
    const a = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche" }] });
    const b = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche entera" }] });
    const c = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche", alimento_id: 5 }] });
    assertEquals(new Set([...ids(a.datos), ...ids(b.datos), ...ids(c.datos)]).size, 3);
    assertEquals(srv.items.size, 3);
});

Deno.test("si el servidor sigue dando 404 en todos los intentos: fallo del artículo, sin bucle infinito", async () => {
    const m = crearMundo({}, {}, {}, { "POST shopping/item/create": { ok: false, status: 404, data: null, error: "Not Found" } });
    const { resultado } = await llamarTool(m, "apuntar_compra", { articulos: [{ etiqueta: "Leche" }] });
    assertEquals(resultado?.isError, true);
    assertEquals(m.escrituras.length, 5);
});
