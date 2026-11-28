import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { idBorrador, idCambios, idCompra, idReceta } from "../idempotencia.ts";
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
