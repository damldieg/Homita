// Caracterización de `errorEscritura` y `uuidDe` (fijada antes de moverlos desde Kito, change mcp-menus-escritura).
import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { errorEscritura } from "../util-escritura.ts";
import { uuidDe } from "../uuid.ts";

const r = (status: number, error?: string) => ({ ok: false, status, data: null, ...(error !== undefined ? { error } : {}) });

Deno.test("errorEscritura: 409 es revisión vieja", () => {
    assertEquals(errorEscritura(r(409)), {
        ok: false, revision_vieja: true,
        error: "El menú ha cambiado desde que lo leí. Léelo otra vez con leer_semana y vuelve a intentarlo.",
    });
});

Deno.test("errorEscritura: 403, 404, 500 Not Found, 400 con y sin motivo, y resto", () => {
    assertEquals(errorEscritura(r(403)), { ok: false, error: "No tienes permiso para hacer eso en el menú del hogar." });
    assertEquals(errorEscritura(r(404)), { ok: false, error: "Ya no existe." });
    assertEquals(errorEscritura(r(500, "Not Found")), { ok: false, error: "Ya no existe." });
    assertEquals(errorEscritura(r(400, "Invalid recipe")), { ok: false, error: "No se ha podido guardar: Invalid recipe." });
    assertEquals(errorEscritura(r(400, "  ")), { ok: false, error: "No se ha podido guardar: datos no válidos." });
    assertEquals(errorEscritura(r(400)), { ok: false, error: "No se ha podido guardar: datos no válidos." });
    assertEquals(errorEscritura(r(500)), { ok: false, error: "No he podido guardarlo ahora mismo." });
    assertEquals(errorEscritura(r(400, "x".repeat(300))), { ok: false, error: `No se ha podido guardar: ${"x".repeat(160)}.` });
});

Deno.test("uuidDe: determinista, con forma de UUID v4 y valor fijo", async () => {
    const a = await uuidDe("clave");
    assertEquals(a, await uuidDe("clave"));
    assertMatch(a, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    assertEquals(a === await uuidDe("otra"), false);
    assertEquals(a, "6d5074b4-bf2b-4138-a615-7d7674f1eda0");
});
