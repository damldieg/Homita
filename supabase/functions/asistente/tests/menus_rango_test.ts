// menus-kito-rango: `resolverRango` (lógica pura): rango simple, entre semanas, a media semana, franja desactivada.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { resolverRango } from "../skills/menus/util.ts";
import type { SemanaRango } from "../skills/menus/util.ts";

const ACTIVAS = ["lunch", "dinner"];
const ok = (r: ReturnType<typeof resolverRango>) => {
    assert(!("error" in r), "error" in r ? r.error : "");
    return r;
};
const claves = (s: SemanaRango) => s.casillas.map((c) => `${c.fecha} ${c.franja}`);

// 2030-01-07 es lunes
Deno.test("resolverRango: lunes noche → viernes mediodía en una semana, solo esas casillas", () => {
    const r = ok(resolverRango({ desde: { fecha: "2030-01-07", franja: "dinner" }, hasta: { fecha: "2030-01-11", franja: "lunch" } }, ACTIVAS));
    assertEquals(r.avisos, []);
    assertEquals(r.semanas.length, 1);
    assertEquals(r.semanas[0].semana, "2030-01-07");
    assertEquals(claves(r.semanas[0]), [
        "2030-01-07 dinner",
        "2030-01-08 lunch", "2030-01-08 dinner",
        "2030-01-09 lunch", "2030-01-09 dinner",
        "2030-01-10 lunch", "2030-01-10 dinner",
        "2030-01-11 lunch",
    ]);
});

Deno.test("resolverRango: un rango que cruza dos semanas da un grupo por semana", () => {
    const r = ok(resolverRango({ desde: { fecha: "2030-01-12", franja: "lunch" }, hasta: { fecha: "2030-01-15", franja: "lunch" } }, ACTIVAS));
    assertEquals(r.semanas.map((s) => s.semana), ["2030-01-07", "2030-01-14"]);
    assertEquals(claves(r.semanas[0]), ["2030-01-12 lunch", "2030-01-12 dinner", "2030-01-13 lunch", "2030-01-13 dinner"]);
    assertEquals(claves(r.semanas[1]), ["2030-01-14 lunch", "2030-01-14 dinner", "2030-01-15 lunch"]);
});

Deno.test("resolverRango: empieza a media semana (jueves) y la semana se calcula desde el lunes", () => {
    const r = ok(resolverRango({ desde: { fecha: "2030-01-10", franja: "dinner" }, hasta: { fecha: "2030-01-10", franja: "dinner" } }, ACTIVAS));
    assertEquals(r.semanas, [{ semana: "2030-01-07", casillas: [{ fecha: "2030-01-10", franja: "dinner" }] }]);
});

Deno.test("resolverRango: respeta week_start_day del perfil (semana que empieza el domingo)", () => {
    const r = ok(resolverRango({ desde: { fecha: "2030-01-12", franja: "lunch" }, hasta: { fecha: "2030-01-13", franja: "dinner" } }, ACTIVAS, 7));
    assertEquals(r.semanas.map((s) => s.semana), ["2030-01-06", "2030-01-13"]);
});

Deno.test("resolverRango: una franja desactivada no genera casilla y se avisa si es un extremo", () => {
    const r = ok(resolverRango({ desde: { fecha: "2030-01-07", franja: "snack" }, hasta: { fecha: "2030-01-08", franja: "lunch" } }, ACTIVAS));
    assertEquals(claves(r.semanas[0]), ["2030-01-07 dinner", "2030-01-08 lunch"]);
    assertEquals(r.avisos.length, 1);
    assert(r.avisos[0].includes("merienda"));
    // desayuno no activo en medio del rango: ni casilla ni aviso (no es extremo)
    const m = ok(resolverRango({ desde: { fecha: "2030-01-07", franja: "lunch" }, hasta: { fecha: "2030-01-09", franja: "dinner" } }, ACTIVAS));
    assert(m.semanas[0].casillas.every((c) => ACTIVAS.includes(c.franja)));
    assertEquals(m.avisos, []);
});

Deno.test("resolverRango: sin ninguna franja activa en el rango no hay casillas y se avisa", () => {
    const r = ok(resolverRango({ desde: { fecha: "2030-01-07", franja: "breakfast" }, hasta: { fecha: "2030-01-07", franja: "breakfast" } }, ACTIVAS));
    assertEquals(r.semanas, []);
    assert(r.avisos.length >= 2);
});

Deno.test("resolverRango: rango invertido, fechas o franjas no válidas y rango demasiado largo dan error", () => {
    const err = (rango: unknown) => {
        const r = resolverRango(rango, ACTIVAS);
        assert("error" in r);
        return r.error;
    };
    assert(err({ desde: { fecha: "2030-01-09", franja: "lunch" }, hasta: { fecha: "2030-01-08", franja: "dinner" } }).includes("invertido"));
    assert(err({ desde: { fecha: "2030-01-08", franja: "dinner" }, hasta: { fecha: "2030-01-08", franja: "lunch" } }).includes("invertido"));
    assert(err({ desde: { fecha: "2030-13-09", franja: "lunch" }, hasta: { fecha: "2030-01-10", franja: "lunch" } }).includes("desde.fecha"));
    assert(err({ desde: { fecha: "2030-01-09", franja: "lunch" }, hasta: { fecha: "2030-01-10", franja: "brunch" } }).includes("hasta.franja"));
    assert(err({ desde: { fecha: "2030-01-01", franja: "lunch" }, hasta: { fecha: "2030-02-01", franja: "lunch" } }).includes("largo"));
    assert(err(null).includes("desde"));
});
