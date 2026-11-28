import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { idBorrador, idCambios, idCompra, idOrganizar, idReceta } from "../idempotencia.ts";
import { uuidDe } from "../uuid.ts";

Deno.test("idBorrador: determinista y cambia con revisión, contenido, semana, hogar y usuario", async () => {
    const base = await idBorrador("u", "7", "2030-01-07", 3, [{ a: 1 }]);
    assertEquals(base, await idBorrador("u", "7", "2030-01-07", 3, [{ a: 1 }]));
    for (const otro of [
        await idBorrador("u", "7", "2030-01-07", 4, [{ a: 1 }]),
        await idBorrador("u", "7", "2030-01-07", 3, [{ a: 2 }]),
        await idBorrador("u", "7", "2030-01-14", 3, [{ a: 1 }]),
        await idBorrador("u", "8", "2030-01-07", 3, [{ a: 1 }]),
        await idBorrador("v", "7", "2030-01-07", 3, [{ a: 1 }]),
    ]) assertNotEquals(otro, base);
});

Deno.test("idCambios, idReceta, idCompra: deterministas y sensibles a lo suyo", async () => {
    assertEquals(await idCambios("u", "7", 5, 2, []), await idCambios("u", "7", 5, 2, []));
    assertNotEquals(await idCambios("u", "7", 5, 2, []), await idCambios("u", "7", 5, 3, []));
    assertNotEquals(await idCambios("u", "7", 5, 2, []), await idCambios("u", "7", 6, 2, []));
    assertEquals(await idReceta("u", "7", { n: 1 }), await idReceta("u", "7", { n: 1 }));
    assertNotEquals(await idReceta("u", "7", { n: 1 }), await idReceta("u", "7", { n: 2 }));
    assertEquals(await idCompra("u", "7", "2030-01-07", "leche"), await idCompra("u", "7", "2030-01-07", "leche"));
    assertNotEquals(await idCompra("u", "7", "2030-01-07", "leche"), await idCompra("u", "7", "2030-01-08", "leche"));
    assertNotEquals(await idCompra("u", "7", "2030-01-07", "leche"), await idCompra("u", "7", "2030-01-07", "pan"));
});

Deno.test("no colisionan con los ids de Kito (otro prefijo) y tienen forma de UUID", async () => {
    const kito = await uuidDe(`menu-rango|u|7|2030-01-07|3|${JSON.stringify([{ a: 1 }])}`);
    const mcp = await idBorrador("u", "7", "2030-01-07", 3, [{ a: 1 }]);
    assertNotEquals(kito, mcp);
    assert(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(mcp));
});

Deno.test("idOrganizar: determinista, independiente del orden de claves y de client_request_id; cambia con minuto, hogar, usuario, herramienta y cuerpo", async () => {
    const t0 = new Date("2030-01-07T10:00:05Z");
    const base = await idOrganizar("u", "7", "crear_tarea", { title: "Pan", task_list_id: 2 }, t0);
    assertEquals(base, await idOrganizar("u", "7", "crear_tarea", { task_list_id: 2, title: "Pan" }, new Date("2030-01-07T10:00:59Z")));
    assertEquals(base, await idOrganizar("u", "7", "crear_tarea", { task_list_id: 2, title: "Pan", client_request_id: "x" }, t0));
    for (const otro of [
        await idOrganizar("u", "7", "crear_tarea", { title: "Pan", task_list_id: 2 }, new Date("2030-01-07T10:01:00Z")),
        await idOrganizar("u", "8", "crear_tarea", { title: "Pan", task_list_id: 2 }, t0),
        await idOrganizar("v", "7", "crear_tarea", { title: "Pan", task_list_id: 2 }, t0),
        await idOrganizar("u", "7", "crear_lista", { title: "Pan", task_list_id: 2 }, t0),
        await idOrganizar("u", "7", "crear_tarea", { title: "Pan", task_list_id: 3 }, t0),
        await idOrganizar("u", "7", "crear_tarea", { title: "Pan", task_list_id: 2, priority: "alta" }, t0),
    ]) assertNotEquals(otro, base);
});

Deno.test("idOrganizar: prefijo mcp-organizar (distinto del de Kito) y forma de UUID", async () => {
    const kito = await uuidDe("u|7|toolu_1|0");
    const mcp = await idOrganizar("u", "7", "crear_lista", { name: "A" }, new Date(0));
    assertNotEquals(kito, mcp);
    assert(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(mcp));
});
