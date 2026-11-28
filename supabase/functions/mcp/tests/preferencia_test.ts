// apuntar_preferencia (criterio 12): exige confirmación, topes, solo C1/C2/C4.
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { crearMundo, llamarTool } from "./util.ts";

const perfil = (extra: Record<string, unknown> = {}) => ({
    profile: { week_start_day: 1 },
    members: [{ home_member_id: 1, name: "Ana", dislikes: ["Cebolla"], favorites: [], ...extra }],
});
const OK = { "PATCH meal/profile/member": { ok: true, status: 200, data: {} } };
const base = { persona_id: 1, campo: "no_le_gusta", valor: "Coliflor", confirmado_por_usuario: true };

Deno.test("sin confirmado_por_usuario=true no hace nada (ni lee ni escribe)", async () => {
    for (const confirmado_por_usuario of [false]) {
        const m = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
        const { resultado } = await llamarTool(m, "apuntar_preferencia", { ...base, confirmado_por_usuario });
        assertEquals(resultado?.isError, true);
        assertStringIncludes(resultado?.content[0].text ?? "", "sin preguntar");
        assertEquals(m.escrituras, []);
        assertEquals(m.llamadas.filter((l) => l.ruta === "meal/profile"), []);
    }
    const m = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
    const { resultado } = await llamarTool(m, "apuntar_preferencia", { persona_id: 1, campo: "no_le_gusta", valor: "x" });
    assertEquals(resultado?.isError, true);
    assertEquals(m.escrituras, []);
});

Deno.test("no_le_gusta añade a dislikes (C1) y le_encanta a favorites (C2) reenviando la lista completa", async () => {
    const m = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
    await llamarTool(m, "apuntar_preferencia", base);
    assertEquals(m.escrituras[0].cuerpo, { home_member_id: 1, dislikes: ["Cebolla", "Coliflor"] });
    assertEquals([m.escrituras[0].metodo, m.escrituras[0].ruta, m.escrituras[0].hogar], ["PATCH", "meal/profile/member", "7"]);
    const f = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
    await llamarTool(f, "apuntar_preferencia", { ...base, campo: "le_encanta", valor: "Lentejas" });
    assertEquals(f.escrituras[0].cuerpo, { home_member_id: 1, favorites: ["Lentejas"] });
});

Deno.test("ya apuntado (sin acentos ni mayúsculas) no escribe; picante 0-3 va a spice; fuera de rango es error", async () => {
    const m = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
    const { datos } = await llamarTool(m, "apuntar_preferencia", { ...base, valor: "cebolla" });
    assertEquals((datos as { hecho: string }).hecho, "Ya estaba apuntado.");
    assertEquals(m.escrituras, []);
    const p = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
    await llamarTool(p, "apuntar_preferencia", { ...base, campo: "picante", valor: "3" });
    assertEquals(p.escrituras[0].cuerpo, { home_member_id: 1, spice: 3 });
    for (const valor of ["4", "-1", "mucho", "1.5"]) {
        const x = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
        assertEquals((await llamarTool(x, "apuntar_preferencia", { ...base, campo: "picante", valor })).resultado?.isError, true, valor);
        assertEquals(x.escrituras, []);
    }
});

Deno.test("solo C1, C2 y C4: campo no permitido (manías) o persona sin ficha da error sin escribir", async () => {
    for (const args of [{ ...base, campo: "manias" }, { ...base, campo: "quirks" }, { ...base, persona_id: 99 }]) {
        const m = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
        assertEquals((await llamarTool(m, "apuntar_preferencia", args)).resultado?.isError, true, JSON.stringify(args));
        assertEquals(m.escrituras, []);
    }
});

Deno.test("topes: 50 apuntados no admiten más; valor de más de 200 caracteres se recorta; 403 del servidor", async () => {
    const lleno = Array.from({ length: 50 }, (_, i) => `a${i}`);
    const m = crearMundo({ "meal/profile": perfil({ dislikes: lleno }) }, {}, {}, OK);
    assertEquals((await llamarTool(m, "apuntar_preferencia", base)).resultado?.isError, true);
    assertEquals(m.escrituras, []);
    const l = crearMundo({ "meal/profile": perfil() }, {}, {}, OK);
    await llamarTool(l, "apuntar_preferencia", { ...base, valor: "x".repeat(300) });
    assertEquals((l.escrituras[0].cuerpo.dislikes as string[])[1].length, 200);
    const p = crearMundo({ "meal/profile": perfil() }, {}, {}, { "PATCH meal/profile/member": { ok: false, status: 403, data: null } });
    assertStringIncludes((await llamarTool(p, "apuntar_preferencia", base)).resultado?.content[0].text ?? "", "No tienes permiso");
});
