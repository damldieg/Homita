// Traducción de errores del api a frases para el usuario.
import { assertEquals } from "jsr:@std/assert@1";
import { esNoExiste, traducir } from "../skills/organizar/errores.ts";

const CASOS: [number, unknown, string | undefined, string][] = [
    [403, "Not Allowed", "Fútbol", "No tienes permiso de edición en «Fútbol»."],
    [403, "Not Allowed", undefined, "No tienes permiso de edición en eso."],
    [404, "Not Found", "X", "Ya no existe."],
    [500, "Not Found", "X", "Ya no existe."],
    [400, "Invalid priority", undefined, "No se ha podido hacer: Invalid priority."],
    [400, undefined, undefined, "No se ha podido hacer: datos no válidos."],
    [500, "Internal error", undefined, "No he podido hacerlo ahora mismo."],
    [502, undefined, undefined, "No he podido hacerlo ahora mismo."],
];

Deno.test("traducir: tabla de casos (403, 404, 500 «Not Found», 400 y otros)", () => {
    for (const [status, error, nombre, esperado] of CASOS) assertEquals(traducir(status, error, nombre), esperado, `${status} ${error}`);
});

Deno.test("esNoExiste: 500 solo cuenta con «Not Found»", () => {
    assertEquals(esNoExiste(500, "Not Found"), true);
    assertEquals(esNoExiste(500, "Internal error"), false);
    assertEquals(esNoExiste(404, undefined), true);
    assertEquals(esNoExiste(403, "Not Found"), false);
});
