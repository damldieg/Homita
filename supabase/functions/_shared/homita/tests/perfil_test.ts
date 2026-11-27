// Perfil de comidas compartido: sin `permisos` (el caso de Kito y del MCP en la fase 1) nunca sale salud.
import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { compactarPerfil, leerPerfilCompacto } from "../menus-lectura.ts";
import type { LecturaCtx } from "../tipos.ts";

const perfil = {
    home_id: 7, timezone: "Europe/Madrid", can_edit: true,
    profile: { week_start_day: 1, shopping_day: 6, cook_minutes_weekday: 30, equipment: ["horno"] },
    slots: [{ slot: "lunch", enabled: true, time: "14:00" }],
    members: [{
        home_member_id: 1, name: "Ana", kind: "adult", age_band: "adult", portion_size: "normal", allergies_answered: true,
        allergies: [], diet: null, diet_note: "secreto-salud", goals: "perder peso", dislikes: [], favorites: [],
    }],
    schedule: [],
};

const ctx = (extra: Partial<LecturaCtx> = {}): LecturaCtx => ({
    homeId: "7", timezone: "Europe/Madrid", now: new Date("2030-01-07T10:00:00Z"), ...extra,
});

Deno.test("compactarPerfil: con permisos indefinidos no hay objetivos ni nota_dieta", () => {
    const out = compactarPerfil(perfil, ctx());
    const texto = JSON.stringify(out);
    assertFalse(texto.includes("secreto-salud"));
    assertFalse(texto.includes("perder peso"));
    assertFalse(texto.includes("objetivos"));
    assertFalse(texto.includes("nota_dieta"));
    const comen = out.comen as Record<string, unknown>[];
    assertEquals(comen[0].nombre, "Ana");
});

Deno.test("compactarPerfil: permisos sin menu.health.view tampoco sacan salud", () => {
    const texto = JSON.stringify(compactarPerfil(perfil, ctx({ permisos: ["menu.view"] })));
    assertFalse(texto.includes("secreto-salud"));
});

Deno.test("compactarPerfil: la salud solo saldría con menu.health.view (hoy nadie lo rellena)", () => {
    const comen = compactarPerfil(perfil, ctx({ permisos: ["menu.health.view"] })).comen as Record<string, unknown>[];
    assertEquals(comen[0].objetivos, "perder peso");
});

Deno.test("leerPerfilCompacto: lee meal/profile con el lector del contexto y no devuelve salud", async () => {
    const rutas: string[] = [];
    const leer = (ruta: string) => {
        rutas.push(ruta);
        return Promise.resolve(perfil);
    };
    const out = await leerPerfilCompacto(ctx({ leer }));
    assertEquals(rutas, ["meal/profile"]);
    assert(!JSON.stringify(out).includes("secreto-salud"));
});

Deno.test("leerPerfilCompacto: sin lector falla y con error del api lanza", async () => {
    let fallo = false;
    try {
        await leerPerfilCompacto(ctx());
    } catch {
        fallo = true;
    }
    assert(fallo);
    let fallo2 = false;
    try {
        await leerPerfilCompacto(ctx({ leer: () => Promise.resolve({ error: 403, detalle: "x" }) }));
    } catch {
        fallo2 = true;
    }
    assert(fallo2);
});
