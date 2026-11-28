// Esqueleto de escritura: hogar resuelto antes de escribir, escritura dentro de runInHome con el JWT del usuario,
// hogar ajeno sin llegar a escribir, y errores del api traducidos.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { datosDe, escribirEnHogar } from "../tools/comun.ts";
import { RUTAS_MCP } from "../escritor.ts";
import { RUTAS_MENUS_COMUNES, RUTAS_ORGANIZAR } from "../../_shared/homita/escritor.ts";
import { crearMundo, TOKEN, UID } from "./util.ts";
import type { Entorno } from "../entorno.ts";

const entorno = (m: ReturnType<typeof crearMundo>): Entorno => ({ token: TOKEN, uid: UID, ...m.deps });

Deno.test("escribe con el JWT del usuario dentro de runInHome del hogar predeterminado", async () => {
    const m = crearMundo({}, {}, {}, { "POST recipe/create": { ok: true, status: 201, data: { id: 9 } } });
    const r = await escribirEnHogar(entorno(m), {}, async (ctx) => {
        assertEquals(ctx.homeId, "7");
        assertEquals(ctx.uid, UID);
        return datosDe(await ctx.escribir("POST", "recipe/create", { name: "x" }));
    });
    assertEquals(r.isError, undefined);
    assertEquals(JSON.parse(r.content[0].text), { id: 9 });
    assertEquals(m.escrituras.length, 1);
    assertEquals(m.escrituras[0].token, TOKEN);
    assertEquals(m.escrituras[0].uid, UID);
    assertEquals(m.escrituras[0].hogar, "7");
});

Deno.test("hogar ajeno: error claro y no se llama a escribir ni a leer datos", async () => {
    const m = crearMundo();
    let llamado = false;
    const r = await escribirEnHogar(entorno(m), { hogar: "99" }, () => {
        llamado = true;
        return Promise.resolve({});
    });
    assertEquals(r.isError, true);
    assertStringIncludes(r.content[0].text, "No tienes acceso a ese hogar");
    assertEquals(llamado, false);
    assertEquals(m.escrituras.length, 0);
    assertEquals(m.llamadas.length, 0);
});

Deno.test("hogar propio distinto del predeterminado: la escritura corre bajo ese hogar", async () => {
    const m = crearMundo({}, {}, {}, { "PATCH shopping/item/check": { ok: true, status: 200, data: {} } });
    await escribirEnHogar(entorno(m), { hogar: "8" }, async (ctx) => datosDe(await ctx.escribir("PATCH", "shopping/item/check", { id: 1, state: "checked" })));
    assertEquals(m.escrituras[0].hogar, "8");
});

Deno.test("zona no válida: error sin resolver hogar", async () => {
    const m = crearMundo();
    const r = await escribirEnHogar(entorno(m), { timezone: "Nope/Zona" }, () => Promise.resolve({}));
    assertEquals(r.isError, true);
    assertEquals(m.llamadas.length, 0);
});

Deno.test("errores del api: 403, 404, 409, 400 con motivo y 500 se traducen sin cuerpo crudo", async () => {
    for (
        const [status, error, texto] of [
            [403, undefined, "No tienes permiso"], [404, undefined, "ya no existe"], [409, undefined, "Ha cambiado"],
            [400, "Invalid recipe", "No se ha podido guardar: Invalid recipe."], [500, "boom secreto", "No he podido guardarlo"],
        ] as const
    ) {
        const m = crearMundo({}, {}, {}, { "POST recipe/create": { ok: false, status, data: { error: "interno" }, ...(error ? { error } : {}) } });
        const r = await escribirEnHogar(entorno(m), {}, async (ctx) => datosDe(await ctx.escribir("POST", "recipe/create", {})));
        assertEquals(r.isError, true, String(status));
        assertStringIncludes(r.content[0].text, texto);
        if (status === 500) assert(!r.content[0].text.includes("secreto"));
    }
});

Deno.test("la lista blanca del MCP: comunes de menús + organizar + accept, food/create y shopping/item/check (27)", () => {
    const claves = Object.keys(RUTAS_MCP).sort();
    assertEquals(claves.length, 27);
    for (const k of Object.keys(RUTAS_ORGANIZAR)) assert(k in RUTAS_MCP, k);
    for (const k of Object.keys(RUTAS_MENUS_COMUNES)) assert(k in RUTAS_MCP, k);
    for (const k of ["POST meal/plan/accept", "POST food/create", "PATCH shopping/item/check", "PATCH calendar/user"]) assert(k in RUTAS_MCP, k);
    // Nada de alarmas, administración, invitaciones ni archivar/copiar/horario.
    for (const k of claves) assert(!/alarm|invit|membership|home\/|archive|copy|schedule/.test(k), k);
});

Deno.test("appUser: ctx.appUserId solo se rellena con la opción", async () => {
    const m = crearMundo();
    const sin = await escribirEnHogar(entorno(m), {}, (ctx) => Promise.resolve({ appUserId: ctx.appUserId ?? null }));
    assertEquals(JSON.parse(sin.content[0].text), { appUserId: null });
    const con = await escribirEnHogar(entorno(m), {}, (ctx) => Promise.resolve({ appUserId: ctx.appUserId ?? null }), { appUser: true });
    assertEquals(JSON.parse(con.content[0].text), { appUserId: "5" });
});

Deno.test("appUser con hogar ajeno: no se consulta el usuario ni se escribe", async () => {
    let pedido = false;
    const m = crearMundo({}, { appUserId: () => { pedido = true; return Promise.resolve("5"); } });
    const r = await escribirEnHogar(entorno(m), { hogar: "99" }, () => Promise.resolve({}), { appUser: true });
    assertEquals(r.isError, true);
    assertEquals(pedido, false);
});
