// Reglas compartidas de las casillas: validación, conversión a casillas del api y coincidencia con lo guardado.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { claveCasilla, itemDe, tipoApi, tipoMcp, TIPOS, TIPOS_MCP, validarPlatos, yaCoincide } from "../menus-escritura.ts";
import type { Plato } from "../menus-escritura.ts";

const PERFIL = {
    slots: [{ slot: "lunch", enabled: true }, { slot: "dinner", enabled: true }, { slot: "snack", enabled: false }],
    members: [{ home_member_id: 1, name: "Ana" }, { home_member_id: 2, name: "Leo" }],
    // Leo come fuera el martes (2) a mediodía; nadie en casa el miércoles (3) a mediodía
    schedule: [
        { weekday: 2, slot: "lunch", home_member_id: 2, status: "out" },
        { weekday: 3, slot: "lunch", home_member_id: 1, status: "out" },
        { weekday: 3, slot: "lunch", home_member_id: 2, status: "out" },
    ],
};
const SEMANA = "2030-01-07"; // lunes

Deno.test("tipos MCP <-> api: ida y vuelta", () => {
    for (const t of TIPOS) assertEquals(tipoApi(tipoMcp(t)!), t);
    assertEquals(Object.values(TIPOS_MCP).sort(), [...TIPOS].sort());
    assertEquals(tipoMcp("otro"), undefined);
});

Deno.test("validarPlatos: plato válido, receta sin receta_id, texto sin título", () => {
    const ok = validarPlatos([{ dia: "2030-01-08", franja: "dinner", receta_id: 3 }], SEMANA, PERFIL);
    assertEquals(ok, { platos: [{ dia: "2030-01-08", franja: "dinner", tipo: "recipe", receta_id: 3 }] });
    assert("errores" in validarPlatos([{ dia: "2030-01-08", franja: "dinner", tipo: "recipe" }], SEMANA, PERFIL));
    assert("errores" in validarPlatos([{ dia: "2030-01-08", franja: "dinner", tipo: "free_text" }], SEMANA, PERFIL));
});

Deno.test("validarPlatos: una casilla por día y franja, franja deshabilitada, fuera de la semana, vacío", () => {
    const dup = validarPlatos([{ dia: "2030-01-08", franja: "dinner", titulo: "a" }, { dia: "2030-01-08", franja: "dinner", titulo: "b" }], SEMANA, PERFIL);
    assertEquals("errores" in dup && dup.errores.length, 1);
    assert("errores" in validarPlatos([{ dia: "2030-01-08", franja: "snack", titulo: "a" }], SEMANA, PERFIL));
    assert("errores" in validarPlatos([{ dia: "2030-01-20", franja: "dinner", titulo: "a" }], SEMANA, PERFIL));
    assertEquals(validarPlatos([], SEMANA, PERFIL), { errores: ["platos está vacío"] });
});

Deno.test("validarPlatos: personas solo entre quienes comen; sin plato si nadie come", () => {
    assert("errores" in validarPlatos([{ dia: "2030-01-08", franja: "lunch", titulo: "a", personas: [2] }], SEMANA, PERFIL));
    assert("platos" in validarPlatos([{ dia: "2030-01-08", franja: "lunch", titulo: "a", personas: [1] }], SEMANA, PERFIL));
    assert("errores" in validarPlatos([{ dia: "2030-01-09", franja: "lunch", titulo: "a" }], SEMANA, PERFIL));
});

Deno.test("itemDe y claveCasilla/yaCoincide", () => {
    const p: Plato = { dia: "2030-01-08", franja: "dinner", tipo: "free_text", titulo: "Pizza", personas: [1] };
    assertEquals(itemDe(p), { day: "2030-01-08", slot: "dinner", position: 0, kind: "free_text", title: "Pizza", members: [1] });
    assertEquals(itemDe({ dia: "2030-01-08", franja: "dinner", tipo: "recipe", receta_id: 3 }).recipe_id, 3);
    assertEquals(claveCasilla("d", "f", "recipe", 3, "x"), "d|f|recipe|3|");
    const guardada = { day: "2030-01-08", slot: "dinner", kind: "free_text", title: "pizza" };
    assert(yaCoincide([guardada], [p]));
    assert(!yaCoincide([{ ...guardada, state: "rejected" }], [p]));
    assert(yaCoincide([guardada, { ...guardada, slot: "lunch", state: "locked" }], [p]));
    assert(!yaCoincide([], [p]));
});
