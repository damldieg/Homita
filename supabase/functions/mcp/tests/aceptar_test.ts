// aceptar_menu (criterios 6-7): orden plan -> check -> accept -> shopping -> check, revisión vieja y conflictos no aceptan,
// segunda comprobación con aviso, nunca accept sin check previo.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { llamarTool } from "./util.ts";
import { casilla, mundoMenus, perfilBase, SEMANA } from "./util_menus.ts";
import type { MundoKito } from "./util_menus.ts";
import { crearMundo as mundoKito } from "../../asistente/tests/menus_util.ts";

type Obj = Record<string, unknown>;
const perfil = (over: Obj = {}) => perfilBase({ schedule: [], ...over });
const PLAN = (over: Obj = {}) => ({
    id: 5, week_start: SEMANA, status: "draft", revision: 3, origin: "kito", unchecked_item_ids: [1, 2],
    items: [casilla(1, "2030-01-08", "lunch", "Sopa"), casilla(2, "2030-01-08", "dinner", "Pizza")],
    ...over,
});
const ARGS = { plan_id: 5, expected_revision: 3, fecha: "2030-01-09" };
const COMPRA = {
    revision: 7,
    items: [
        { id: 1, label: "Leche", quantity: 2, unit: "l", section: "lácteos", state: "pending", plan_id: 5 },
        { id: 2, label: "Pan suelto", quantity: 1, unit: "ud", section: "panadería", state: "pending", plan_id: null },
    ],
};
const datosDe = (d: unknown) => d as Obj;

/** Escritor de accept que actúa como el servidor: sube la revisión, pasa a accepted y devuelve el resumen de la Compra. */
const accept = (a: MundoKito) => (c: Obj) => {
    const p = a.plan()!;
    if (c.expected_revision !== p.revision) return { ok: false, status: 409, data: null, error: "Stale meal plan revision" };
    a.ponerPlan({ ...p, status: "accepted", revision: (p.revision as number) + 1 });
    return { ok: true, status: 200, data: { ...a.plan()!, shopping_sync: { added: 2, updated: 0, removed: 0 } } };
};

const preparar = (plan: Obj | null = PLAN(), opciones: { perfil?: Obj; escribir?: ReturnType<typeof accept> | ((c: Obj) => never); leerHook?: (ruta: string, params: Record<string, string | undefined>, n: number) => unknown } = {}) => {
    const a = mundoKito({ perfil: opciones.perfil ?? perfil() });
    a.ponerPlan(plan);
    const m = mundoMenus(a, undefined, {
        respuestas: { shopping: COMPRA },
        escribir: { "POST meal/plan/accept": (opciones.escribir ?? accept(a)) as never },
        leerHook: opciones.leerHook,
    });
    return { a, m };
};

Deno.test("revisión correcta: acepta con la revisión del cliente y devuelve el resumen de la Compra; orden plan -> check -> accept -> shopping -> plan -> check", async () => {
    const { a, m } = preparar();
    const { resultado, datos } = await llamarTool(m, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    const accepts = m.escrituras.filter((e) => e.ruta === "meal/plan/accept");
    assertEquals(accepts.length, 1);
    assertEquals(accepts[0].cuerpo, { plan_id: 5, expected_revision: 3 });
    assertEquals(accepts[0].hogar, "7");
    assertEquals(m.orden.filter((o) => o !== "GET home"), [
        "GET meal/profile", "GET meal/plan", "GET meal/plan/check", "POST meal/plan/accept", "GET shopping", "GET meal/plan", "GET meal/plan/check",
    ]);
    const d = datosDe(datos);
    assertEquals([d.aceptado, d.plan_id, d.semana, d.revision], [true, 5, SEMANA, 4]);
    const compra = d.compra as Obj;
    assertEquals(compra.sincronizacion, { añadidos: 2, actualizados: 0, quitados: 0 });
    assertEquals(compra.articulos_del_menu, 1);
    assertEquals(((compra.articulos as Obj[])[0]).articulo, "Leche");
    assertEquals(d.avisos, undefined);
    assertEquals(a.plan()!.status, "accepted");
});

Deno.test("revisión vieja: no escribe y devuelve el plan vigente (isError)", async () => {
    const { m } = preparar();
    const { resultado, datos } = await llamarTool(m, "aceptar_menu", { ...ARGS, expected_revision: 2 });
    assertEquals(resultado?.isError, true);
    assertEquals(m.escrituras, []);
    const d = datosDe(datos);
    assertEquals([d.aceptado, d.motivo], [false, "revision_vieja"]);
    assertEquals((d.plan_vigente as Obj).revision, 3);
});

Deno.test("409 en el accept (cambió entre la comprobación y el accept): no reintenta y devuelve el plan vigente", async () => {
    const { m } = preparar(PLAN(), { escribir: () => ({ ok: false, status: 409, data: null, error: "Stale meal plan revision" }) as never });
    const { resultado, datos } = await llamarTool(m, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, true);
    assertEquals(m.escrituras.filter((e) => e.ruta === "meal/plan/accept").length, 1, "un solo intento");
    assertEquals(datosDe(datos).motivo, "revision_vieja");
    assertEquals(typeof (datosDe(datos).plan_vigente as Obj).plan_id, "number");
});

Deno.test("conflictos abiertos (receta con gluten para Ana): no acepta y los devuelve", async () => {
    const plan = PLAN({ items: [casilla(1, "2030-01-08", "lunch", "Pasta con tomate", { kind: "recipe", recipe_id: 10 })], unchecked_item_ids: [] });
    const { m } = preparar(plan);
    const { resultado, datos } = await llamarTool(m, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, true);
    assertEquals(m.escrituras, []);
    const d = datosDe(datos);
    assertEquals([d.aceptado, d.motivo], [false, "conflictos"]);
    assertEquals((d.conflictos as Obj[])[0].tipo, "alergia");
});

Deno.test("receta sin comprobar + persona con dieta o alergia: no acepta (regla sin_comprobar compartida)", async () => {
    const plan = PLAN({
        items: [casilla(1, "2030-01-08", "lunch", "Guiso", { kind: "recipe", recipe_id: 12, members: [1, 2] })], unchecked_item_ids: [1],
    });
    const { m } = preparar(plan);
    const { resultado, datos } = await llamarTool(m, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, true);
    assertEquals(m.escrituras, []);
    assertEquals(datosDe(datos).motivo, "conflictos");
    assertEquals((datosDe(datos).sin_comprobar as unknown[]).length, 1);
});

Deno.test("texto libre sin comprobar no bloquea; sin check posible (no_comprobado) no acepta", async () => {
    const { a: _a, m } = preparar();
    assertEquals((await llamarTool(m, "aceptar_menu", ARGS)).resultado?.isError, undefined);
    const roto = mundoKito({ perfil: perfil(), checkFalla: true });
    roto.ponerPlan(PLAN());
    const m2 = mundoMenus(roto, undefined, { respuestas: { shopping: COMPRA }, escribir: { "POST meal/plan/accept": accept(roto) as never } });
    const { resultado, datos } = await llamarTool(m2, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, true);
    assertEquals(datosDe(datos).motivo, "no_comprobado");
    assertEquals(m2.escrituras, []);
});

Deno.test("conflicto que aparece tras aceptar: aceptado: true con aviso y conflictos_tras_aceptar", async () => {
    const plan = PLAN({ items: [casilla(1, "2030-01-08", "lunch", "Pasta", { kind: "recipe", recipe_id: 10 })], unchecked_item_ids: [] });
    let checks = 0;
    const conflicto = [{ item_id: 1, day: "2030-01-08", slot: "lunch", member_id: 1, code: "allergen", detail: { allergen: "gluten" } }];
    const { m } = preparar(plan, { leerHook: (ruta) => (ruta === "meal/plan/check" ? (++checks === 1 ? [] : conflicto) : undefined) });
    const { resultado, datos } = await llamarTool(m, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    const d = datosDe(datos);
    assertEquals(d.aceptado, true);
    assertStringIncludes((d.avisos as string[])[0], "apareció un conflicto");
    assertEquals((d.conflictos_tras_aceptar as Obj[]).length, 1);
    assertEquals(m.escrituras.filter((e) => e.ruta === "meal/plan/accept").length, 1);
});

Deno.test("nunca hay accept sin una comprobación previa en la misma invocación (varios escenarios)", async () => {
    const escenarios: Obj[] = [PLAN(), PLAN({ status: "accepted" }), PLAN({ revision: 9 }), PLAN({ items: [], unchecked_item_ids: [] })];
    for (const plan of escenarios) {
        const { m } = preparar(plan);
        await llamarTool(m, "aceptar_menu", ARGS);
        const i = m.orden.indexOf("POST meal/plan/accept");
        if (i >= 0) assert(m.orden.slice(0, i).includes("GET meal/plan/check"), JSON.stringify(m.orden));
    }
});

Deno.test("ya aceptado, sin casillas, plan inexistente o de otra semana: no acepta", async () => {
    const casos: [Obj | null, Obj, string | undefined][] = [
        [PLAN({ status: "accepted" }), ARGS, "ya_aceptado"],
        [PLAN({ items: [], unchecked_item_ids: [] }), ARGS, "sin_casillas"],
        [null, ARGS, undefined],
        [PLAN(), { ...ARGS, plan_id: 99 }, undefined],
        [PLAN(), { ...ARGS, fecha: "2030-01-20" }, undefined],
    ];
    for (const [plan, args, motivo] of casos) {
        const { m } = preparar(plan);
        const { resultado, datos } = await llamarTool(m, "aceptar_menu", args);
        assertEquals(resultado?.isError, true, JSON.stringify(args));
        assertEquals(m.escrituras, []);
        if (motivo) assertEquals(datosDe(datos).motivo, motivo);
    }
});

Deno.test("403 del servidor al aceptar: error sin cuerpo crudo", async () => {
    const { m } = preparar(PLAN(), { escribir: () => ({ ok: false, status: 403, data: null }) as never });
    const { resultado } = await llamarTool(m, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, true);
    assertStringIncludes(resultado?.content[0].text ?? "", "No tienes permiso");
});

Deno.test("si la Compra no se puede leer tras aceptar: sigue aceptado, con aviso en el resumen", async () => {
    const { m } = preparar(PLAN(), { leerHook: (ruta) => (ruta === "shopping" ? { error: "x" } : undefined) });
    const { resultado, datos } = await llamarTool(m, "aceptar_menu", ARGS);
    assertEquals(resultado?.isError, undefined);
    assertEquals(datosDe(datos).aceptado, true);
    assertStringIncludes(String((datosDe(datos).compra as Obj).aviso), "ver_compra");
});
