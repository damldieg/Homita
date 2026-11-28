// Hogar de cada llamada: predeterminado, único sin marca, ambiguo, explícito, ajeno y mal formado; y los errores del
// api como texto en español sin el cuerpo crudo.
import { assert, assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { resolverHogar } from "../hogar.ts";
import { NOMBRES_LECTURA } from "../tools/registro.ts";
import { crearMundo, HOGARES, llamarTool, TOKEN, UID } from "./util.ts";
import type { Entorno } from "../entorno.ts";

const datos = (m: ReturnType<typeof crearMundo>) => m.llamadas.filter((l) => l.ruta !== "home");
const texto = (r: { content: { text: string }[] } | undefined) => r?.content[0]?.text ?? "";

Deno.test("sin hogar: usa el predeterminado de GET /home y llama a los casos de uso dentro de ese hogar", async () => {
    const m = crearMundo({ "task-list": [] });
    const { resultado } = await llamarTool(m, "ver_listas");
    assertFalse(resultado?.isError === true);
    assertEquals(m.llamadas[0].ruta, "home");
    assertEquals(m.llamadas[0].hogar, null);
    assertEquals(m.comprobaciones, []);
    assertEquals(datos(m).map((l) => [l.ruta, l.hogar, l.token, l.uid]), [["task-list", "7", TOKEN, UID]]);
});

Deno.test("sin hogar: un solo hogar sin marca de predeterminado -> ese", async () => {
    const m = crearMundo({ home: [{ home_id: 12, name: "Solo", role: "admin", is_default: false, is_personal: true }] });
    await llamarTool(m, "ver_listas");
    assertEquals(datos(m).map((l) => l.hogar), ["12"]);
});

Deno.test("sin hogar: varios sin predeterminado -> error que pide `hogar` y no se lee nada", async () => {
    const m = crearMundo({ home: HOGARES.map((h) => ({ ...h, is_default: false })) });
    const { resultado } = await llamarTool(m, "ver_listas");
    assertEquals(resultado?.isError, true);
    assertStringIncludes(texto(resultado), "ver_hogares");
    assertEquals(datos(m), []);
});

Deno.test("sin hogar: sin ningún hogar -> error", async () => {
    const m = crearMundo({ home: [] });
    const { resultado } = await llamarTool(m, "ver_listas");
    assertEquals(resultado?.isError, true);
    assertEquals(datos(m), []);
});

Deno.test("hogar explícito del que es miembro: se comprueba la membresía y se lee en ese hogar", async () => {
    const m = crearMundo();
    const { resultado } = await llamarTool(m, "ver_listas", { hogar: "8" });
    assertFalse(resultado?.isError === true);
    assertEquals(m.comprobaciones, ["8"]);
    assertEquals(m.llamadas.map((l) => [l.ruta, l.hogar]), [["task-list", "8"]]);
});

Deno.test("hogar explícito con ceros a la izquierda se normaliza", async () => {
    const m = crearMundo();
    await llamarTool(m, "ver_listas", { hogar: "0008" });
    assertEquals(m.comprobaciones, ["8"]);
    assertEquals(m.llamadas[0].hogar, "8");
});

Deno.test("hogar ajeno en las 11 herramientas con `hogar`: error claro y ningún caso de uso", async () => {
    const con = NOMBRES_LECTURA.filter((n) => n !== "ver_hogares");
    assertEquals(con.length, 11);
    for (const nombre of con) {
        const m = crearMundo();
        m.miembroDe.delete("8");
        const { resultado } = await llamarTool(m, nombre, { hogar: "8" });
        assertEquals(resultado?.isError, true, nombre);
        assertStringIncludes(texto(resultado), "No tienes acceso a ese hogar");
        assertEquals(m.comprobaciones, ["8"], nombre);
        assertEquals(m.llamadas, [], nombre);
    }
});

Deno.test("hogar no numérico -> error sin comprobar membresía ni leer", async () => {
    for (const hogar of ["abc", "1e3", "-1", "7 ", "1234567890123456789"]) {
        const m = crearMundo();
        const { resultado } = await llamarTool(m, "ver_listas", { hogar });
        assertEquals(resultado?.isError, true, hogar);
        assertEquals(m.comprobaciones, [], hogar);
        assertEquals(m.llamadas, [], hogar);
    }
});

Deno.test("resolverHogar: miembro, ajeno y mal formado", async () => {
    const m = crearMundo();
    const env: Entorno = { token: TOKEN, uid: UID, ...m.deps };
    assertEquals(await resolverHogar("7", env, "Europe/Madrid"), { ok: true, homeId: "7" });
    assertEquals((await resolverHogar("99", env, "Europe/Madrid")).ok, false);
    assertEquals((await resolverHogar(7, env, "Europe/Madrid")).ok, false);
});

Deno.test("errores del api: texto en español por estado y nunca el cuerpo crudo", async () => {
    for (const [status, frase] of [[401, "sesión ha caducado"], [403, "No tienes permiso"], [404, "no existe"], [500, "No he podido leer"]] as const) {
        const m = crearMundo({}, {}, { "task-list": status });
        const { resultado } = await llamarTool(m, "ver_listas");
        assertEquals(resultado?.isError, true, String(status));
        assertStringIncludes(texto(resultado), frase);
        assertFalse(texto(resultado).includes("interno secreto"));
    }
});

Deno.test("error al leer los hogares (GET /home falla) -> error de herramienta", async () => {
    const m = crearMundo({}, {}, { home: 500 });
    const { resultado } = await llamarTool(m, "ver_listas");
    assertEquals(resultado?.isError, true);
    assertEquals(datos(m), []);
});

Deno.test("zona horaria inválida -> error; válida se pasa al lector", async () => {
    const mal = crearMundo();
    const r1 = await llamarTool(mal, "ver_listas", { timezone: "Marte/Olimpo" });
    assertEquals(r1.resultado?.isError, true);
    assertEquals(mal.llamadas, []);
    const bien = crearMundo();
    await llamarTool(bien, "ver_listas", { timezone: "America/Argentina/Buenos_Aires" });
    assertEquals(bien.llamadas.map((l) => l.tz), ["America/Argentina/Buenos_Aires", "America/Argentina/Buenos_Aires"]);
    const defecto = crearMundo();
    await llamarTool(defecto, "ver_listas");
    assert(defecto.llamadas.every((l) => l.tz === "Europe/Madrid"));
});

Deno.test("ver_hogares: lista los hogares sin hogar activo y con id en texto", async () => {
    const m = crearMundo();
    const { datos: d } = await llamarTool(m, "ver_hogares");
    assertEquals(d, {
        hogares: [
            { id: "7", nombre: "Casa", rol: "admin", predeterminado: true, personal: true },
            { id: "8", nombre: "Abuelos", rol: "member", predeterminado: false, personal: false },
        ],
    });
    assertEquals(m.llamadas.map((l) => [l.ruta, l.hogar]), [["home", null]]);
});
