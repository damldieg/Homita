// Errores y argumentos compartidos de «organizar» (los usan Kito y el MCP).
import { assertEquals } from "jsr:@std/assert@1";
import { detalle, entero, falta, filaPorId, ids, resolverDestino, texto } from "../organizar/argumentos.ts";
import { esNoExiste, traducir } from "../organizar/errores.ts";
import { localAUtc, parsearPared } from "../organizar/tiempo.ts";
import type { OrgCtx } from "../organizar/tipos.ts";

Deno.test("traducir: 403 con y sin nombre, no existe, 400 con motivo recortado y genérico", () => {
    assertEquals(traducir(403, "x", "Compra"), "No tienes permiso de edición en «Compra».");
    assertEquals(traducir(403, "x"), "No tienes permiso de edición en eso.");
    assertEquals(traducir(404, "x"), "Ya no existe.");
    assertEquals(traducir(500, "Not Found"), "Ya no existe.");
    assertEquals(traducir(400, "Falta el nombre"), "No se ha podido hacer: Falta el nombre.");
    assertEquals(traducir(400, undefined), "No se ha podido hacer: datos no válidos.");
    assertEquals(traducir(400, "x".repeat(300)), `No se ha podido hacer: ${"x".repeat(160)}.`);
    assertEquals(traducir(500, "otro"), "No he podido hacerlo ahora mismo.");
    assertEquals(traducir(409, "x"), "No he podido hacerlo ahora mismo.");
});

Deno.test("esNoExiste: 404 y 500 «Not Found»", () => {
    assertEquals([esNoExiste(404, ""), esNoExiste(500, "Not Found"), esNoExiste(500, "x"), esNoExiste(403, "Not Found")], [true, true, false, false]);
});

Deno.test("argumentos: texto, entero, ids y falta", () => {
    assertEquals(texto({ a: "  x " }, "a"), "x");
    assertEquals(texto({ a: "  " }, "a"), undefined);
    assertEquals([entero({ a: 3 }, "a"), entero({ a: "7" }, "a"), entero({ a: 0 }, "a"), entero({ a: 1.5 }, "a")], [3, 7, undefined, undefined]);
    assertEquals([ids({ a: [1, 1, 2] }, "a"), ids({ a: [1, "x"] }, "a"), ids({}, "a")], [[1, 2], null, undefined]);
    assertEquals(falta(["x"], { opciones: [] }), { falta: ["x"], opciones: [] });
});

Deno.test("tiempo: hora local → UTC (Madrid, invierno y verano) y fechas inexistentes", () => {
    assertEquals(localAUtc(parsearPared("2026-11-27")!, "Europe/Madrid"), "2026-11-27 22:59:00");
    assertEquals(localAUtc(parsearPared("2026-07-01 09:15")!, "Europe/Madrid"), "2026-07-01 07:15:00");
    assertEquals(parsearPared("2026-02-30"), null);
});

const ctx = (over: Partial<OrgCtx>): OrgCtx => ({ homeId: "1", timezone: "Europe/Madrid", now: new Date(), ...over });

Deno.test("filaPorId, detalle y resolverDestino con lector y escritor recibidos", async () => {
    const leer = (ruta: string) => Promise.resolve(ruta === "calendar" ? [{ id: 1, name: "A" }, { id: 2, name: "B", can_edit: false }] : []);
    const c = ctx({
        leer,
        escribir: (_m, _r, cuerpo) => Promise.resolve(cuerpo?.id === 1 ? { ok: true, status: 200, data: { id: 1 } } : { ok: false, status: 500, data: null, error: "Not Found" }),
    });
    assertEquals(await filaPorId(c, "calendar", 1), { id: 1, name: "A" });
    assertEquals(await filaPorId(c, "calendar", 9), null);
    assertEquals(await detalle(c, "task/detail", 1), { id: 1 });
    assertEquals(await detalle(c, "task/detail", 2), null);
    assertEquals(await resolverDestino(c, "calendar", "calendario", undefined), { id: 1, nombre: "A" });
    assertEquals(await resolverDestino(c, "calendar", "calendario", 9), { error: "Ya no existe." });
    assertEquals(await resolverDestino(ctx({}), "calendar", "calendario", undefined), { error: "No he podido leer tus calendarios ahora mismo." });
});
