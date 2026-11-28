// cambiar_casillas (criterios 4-5): solo libres o rejected; locked y ocupadas rechazadas con motivo; aceptado = error;
// revisión del cliente; 409 devuelve el plan vigente.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { llamarTool } from "./util.ts";
import { casilla, mundoMenus, perfilBase, SEMANA } from "./util_menus.ts";
import { crearMundo as mundoKito } from "../../asistente/tests/menus_util.ts";

type Obj = Record<string, unknown>;
const perfil = () => perfilBase({ schedule: [] });
const PLAN = (over: Obj = {}) => ({
    id: 5, week_start: SEMANA, status: "draft", revision: 3, origin: "kito", unchecked_item_ids: [1, 2, 3, 4],
    items: [
        casilla(1, "2030-01-08", "lunch", "Sopa"), // normal
        casilla(2, "2030-01-08", "dinner", "Pizza", { state: "rejected" }), // rechazada
        casilla(3, "2030-01-09", "dinner", "Paella", { state: "locked" }), // bloqueada
        casilla(4, "2030-01-10", "dinner", "Rechazada 2", { state: "rejected", position: 0 }),
    ],
    ...over,
});
const T = (fecha: string, franja: string, titulo: string, extra: Obj = {}) => ({ fecha, franja, tipo: "texto", titulo, ...extra });
const base = (cambios: Obj[], over: Obj = {}) => ({ plan_id: 5, expected_revision: 3, cambios, ...over });
const datosDe = (d: unknown) => d as Obj;

const preparar = (plan: Obj | null = PLAN()) => {
    const a = mundoKito({ perfil: perfil() });
    a.ponerPlan(plan);
    return { a, m: mundoMenus(a) };
};

Deno.test("cambia una casilla rechazada: reemplaza el plato en la misma casilla, state null, origin kito y revisión del cliente", async () => {
    const { a, m } = preparar();
    const { resultado, datos } = await llamarTool(m, "cambiar_casillas", base([T("2030-01-08", "dinner", "Tortilla")]));
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    const cuerpo = a.escrituras[0].cuerpo;
    assertEquals([cuerpo.week_start, cuerpo.expected_revision, cuerpo.origin, cuerpo.delete_ids], [SEMANA, 3, "kito", undefined]);
    const item = (cuerpo.items as Obj[])[0];
    assertEquals([item.id, item.title, item.kind, item.state, item.day, item.slot], [2, "Tortilla", "free_text", null, "2030-01-08", "dinner"]);
    assertEquals(m.escrituras[0].hogar, "7");
    const d = datosDe(datos);
    assertEquals([d.cambiadas, d.revision, d.rechazadas], [1, 4, []]);
    const final = a.plan()!.items as Obj[];
    assertEquals(final.find((i) => i.id === 2)!.title, "Tortilla");
    assertEquals(final.find((i) => i.id === 2)!.state, null);
});

Deno.test("casilla libre: se crea; bloqueada y ocupada con plato normal: rechazadas con motivo y no se tocan", async () => {
    const { a, m } = preparar();
    const { resultado, datos } = await llamarTool(m, "cambiar_casillas", base([
        T("2030-01-11", "lunch", "Libre"), // libre
        T("2030-01-09", "dinner", "Pisar bloqueada"), // locked
        T("2030-01-08", "lunch", "Pisar sopa"), // ocupada normal
    ]));
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    const items = a.escrituras[0].cuerpo.items as Obj[];
    assertEquals(items.length, 1);
    assertEquals(items[0].id, undefined);
    assertEquals(items[0].title, "Libre");
    const rech = datosDe(datos).rechazadas as { fecha: string; franja: string; motivo: string }[];
    assertEquals(rech.map((r) => `${r.fecha} ${r.franja}`), ["2030-01-09 dinner", "2030-01-08 lunch"]);
    assertStringIncludes(rech[0].motivo, "bloqueada");
    assertStringIncludes(rech[1].motivo, "ocupada");
    const final = a.plan()!.items as Obj[];
    assertEquals(final.find((i) => i.id === 3)!.title, "Paella");
    assertEquals(final.find((i) => i.id === 1)!.title, "Sopa");
});

Deno.test("si todas las casillas son rechazadas por estado: error, sin escribir y con las rechazadas", async () => {
    const { a, m } = preparar();
    const { resultado, datos } = await llamarTool(m, "cambiar_casillas", base([T("2030-01-09", "dinner", "x"), T("2030-01-08", "lunch", "y")]));
    assertEquals(resultado?.isError, true);
    assertEquals(a.escrituras, []);
    assertEquals((datosDe(datos).rechazadas as unknown[]).length, 2);
});

Deno.test("quitar vacía una casilla rechazada (delete_ids); quitar una libre u ocupada se rechaza", async () => {
    const { a, m } = preparar();
    const { datos } = await llamarTool(m, "cambiar_casillas", base([
        { fecha: "2030-01-10", franja: "dinner", quitar: true },
        { fecha: "2030-01-11", franja: "lunch", quitar: true },
        { fecha: "2030-01-08", franja: "lunch", quitar: true },
    ]));
    assertEquals(a.escrituras[0].cuerpo.delete_ids, [4]);
    assertEquals(a.escrituras[0].cuerpo.items, []);
    assertEquals(datosDe(datos).quitadas, 1);
    assertEquals((datosDe(datos).rechazadas as unknown[]).length, 2);
    assertEquals((a.plan()!.items as Obj[]).some((i) => i.id === 4), false);
});

Deno.test("plan aceptado: error y sin escribir", async () => {
    const { a, m } = preparar(PLAN({ status: "accepted" }));
    const { resultado } = await llamarTool(m, "cambiar_casillas", base([T("2030-01-08", "dinner", "x")]));
    assertEquals(resultado?.isError, true);
    assertEquals(a.escrituras, []);
});

Deno.test("revisión vieja del cliente: no escribe y devuelve el plan vigente (isError)", async () => {
    const { a, m } = preparar();
    const { resultado, datos } = await llamarTool(m, "cambiar_casillas", base([T("2030-01-08", "dinner", "x")], { expected_revision: 2 }));
    assertEquals(resultado?.isError, true);
    assertEquals(a.escrituras, []);
    const d = datosDe(datos);
    assertEquals(d.revision_vieja, true);
    assertEquals((d.plan_vigente as Obj).revision, 3);
    assertEquals(((d.plan_vigente as Obj).casillas as unknown[]).length, 4);
});

Deno.test("409 del servidor (cambió entre la lectura y la escritura): plan vigente releído y isError", async () => {
    const { a, m } = preparar();
    const m2 = mundoMenus(a, undefined, { escribir: { "PATCH meal/plan/items": () => ({ ok: false, status: 409, data: null, error: "Stale meal plan revision" }) } });
    const { resultado, datos } = await llamarTool(m2, "cambiar_casillas", base([T("2030-01-08", "dinner", "x")]));
    assertEquals(resultado?.isError, true);
    assertEquals(datosDe(datos).revision_vieja, true);
    assertEquals(typeof (datosDe(datos).plan_vigente as Obj).plan_id, "number");
    assert(m.escrituras.length === 0);
});

Deno.test("plan_id que no es el de esa semana o fechas de otra semana: error sin escribir", async () => {
    for (const args of [base([T("2030-01-08", "dinner", "x")], { plan_id: 99 }), base([T("2030-01-08", "dinner", "x"), T("2030-01-15", "lunch", "y")]), base([T("2030-01-15", "lunch", "y")])]) {
        const { a, m } = preparar();
        const { resultado } = await llamarTool(m, "cambiar_casillas", args);
        assertEquals(resultado?.isError, true, JSON.stringify(args).slice(0, 80));
        assertEquals(a.escrituras, []);
    }
});

Deno.test("sin plan en esa semana: error; sin cambios o con tipo inválido: error", async () => {
    const { a, m } = preparar(null);
    assertEquals((await llamarTool(m, "cambiar_casillas", base([T("2030-01-08", "dinner", "x")]))).resultado?.isError, true);
    for (const cambios of [[], [T("2030-01-08", "dinner", "x", { tipo: "plato" })], [{ fecha: "2030-01-08", franja: "dinner", tipo: "receta" }]]) {
        const p = preparar();
        assertEquals((await llamarTool(p.m, "cambiar_casillas", base(cambios))).resultado?.isError, true);
        assertEquals(p.a.escrituras, []);
    }
    assertEquals(a.escrituras, []);
});

Deno.test("tras cambiar comprueba el plan: una receta con gluten para Ana sale como conflicto", async () => {
    const { m } = preparar();
    const { datos } = await llamarTool(m, "cambiar_casillas", base([{ fecha: "2030-01-08", franja: "dinner", tipo: "receta", receta_id: 10 }]));
    const d = datosDe(datos);
    assertEquals(d.listo_para_aceptar, false);
    assertEquals((d.conflictos as Obj[])[0].tipo, "alergia");
});
