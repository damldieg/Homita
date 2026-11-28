// guardar_borrador (criterios 1-3): un plan por semana, solo casillas libres, conflictos por semana, 409 con plan vigente,
// reintento idempotente, y paridad con el modo rango de Kito.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { proponerMenuTool } from "../../asistente/skills/menus/menu.ts";
import { ctxDe, crearMundo as mundoKito } from "../../asistente/tests/menus_util.ts";
import { llamarTool } from "./util.ts";
import { casilla, mundoMenus, perfilBase, SEMANA, SEMANA2 } from "./util_menus.ts";

type Obj = Record<string, unknown>;
const perfil = () => perfilBase({ schedule: [] });
const C = (fecha: string, franja: string, titulo = "Plato", extra: Obj = {}) => ({ fecha, franja, tipo: "texto", titulo: `${titulo} ${fecha} ${franja}`, ...extra });
// lunes noche -> viernes mediodía (una semana)
const RANGO = { desde: { fecha: "2030-01-07", franja: "dinner" }, hasta: { fecha: "2030-01-11", franja: "lunch" } };
const PUNTOS: [string, string][] = [
    ["2030-01-07", "dinner"], ["2030-01-08", "lunch"], ["2030-01-08", "dinner"], ["2030-01-09", "lunch"], ["2030-01-09", "dinner"],
    ["2030-01-10", "lunch"], ["2030-01-10", "dinner"], ["2030-01-11", "lunch"],
];
const casillas = () => PUNTOS.map(([d, f]) => C(d, f));
// viernes noche -> martes mediodía (cruza dos semanas)
const RANGO2 = { desde: { fecha: "2030-01-11", franja: "dinner" }, hasta: { fecha: "2030-01-15", franja: "lunch" } };
const CASILLAS2 = [C("2030-01-11", "dinner"), C("2030-01-12", "lunch"), C("2030-01-13", "dinner"), C("2030-01-14", "lunch"), C("2030-01-14", "dinner"), C("2030-01-15", "lunch")];
const par = (e: Obj) => `${e.day} ${e.slot}`;
const datosDe = (d: unknown) => d as Obj;

Deno.test("una semana: PATCH meal/plan/items con origin kito, revisión 0, sin delete_ids, hogar y JWT; devuelve plan_id, revision y casillas", async () => {
    const a = mundoKito({ perfil: perfil() });
    const m = mundoMenus(a);
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO, casillas: casillas() });
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    assertEquals(a.escrituras.length, 1);
    const cuerpo = a.escrituras[0].cuerpo;
    assertEquals([cuerpo.week_start, cuerpo.expected_revision, cuerpo.origin, cuerpo.delete_ids], [SEMANA, 0, "kito", undefined]);
    assertEquals((cuerpo.items as Obj[]).map(par), PUNTOS.map(([d, f]) => `${d} ${f}`));
    assertEquals(m.escrituras[0].hogar, "7");
    const s = (datosDe(datos).semanas as Obj[])[0];
    assertEquals([s.semana, s.estado, s.revision, s.escritas, s.listo_para_aceptar], [SEMANA, "escrito", 1, 8, true]);
    assertEquals((s.casillas as Obj[]).length, 8);
    assertEquals((s.casillas as Obj[])[0], {
        id: (s.casillas as Obj[])[0].id, fecha: "2030-01-07", franja: "dinner", tipo: "texto", titulo: "Plato 2030-01-07 dinner",
        receta_id: null, estado: null, personas: [1, 2], comprobada: false, // texto libre: el servidor no lo comprueba
    });
    assertEquals(s.conflictos, []);
});

Deno.test("rango que cruza semanas: un plan por semana (2 PATCH) con las casillas de cada una", async () => {
    const p = perfil();
    const a = mundoKito({ perfil: p });
    const b = mundoKito({ perfil: p, idInicial: 500 });
    const m = mundoMenus(a, b);
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO2, casillas: CASILLAS2 });
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    assertEquals(m.escrituras.filter((e) => e.ruta === "meal/plan/items").length, 2);
    assertEquals((a.escrituras[0].cuerpo.items as Obj[]).map(par), ["2030-01-11 dinner", "2030-01-12 lunch", "2030-01-13 dinner"]);
    assertEquals((b.escrituras[0].cuerpo.items as Obj[]).map(par), ["2030-01-14 lunch", "2030-01-14 dinner", "2030-01-15 lunch"]);
    assertEquals((datosDe(datos).semanas as Obj[]).map((s) => [s.semana, s.estado]), [[SEMANA, "escrito"], [SEMANA2, "escrito"]]);
});

Deno.test("reintento idempotente: la segunda llamada no escribe (ya_estaba) y devuelve lo mismo", async () => {
    const a = mundoKito({ perfil: perfil() });
    const m = mundoMenus(a);
    await llamarTool(m, "guardar_borrador", { rango: RANGO, casillas: casillas() });
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO, casillas: casillas() });
    assertEquals(resultado?.isError, undefined);
    assertEquals(a.escrituras.length, 1, "sin segunda escritura");
    const s = (datosDe(datos).semanas as Obj[])[0];
    assertEquals([s.estado, s.escritas, s.revision, s.listo_para_aceptar], ["ya_estaba", 0, 1, true]);
});

Deno.test("reintento tras perder la respuesta: mismo client_request_id (misma revisión y contenido)", async () => {
    const a = mundoKito({ perfil: perfil() });
    let n = 0;
    const m = mundoMenus(a, undefined, {
        escribir: { "PATCH meal/plan/items": (c) => {
            n++;
            return n === 1 ? { ok: false, status: 500, data: null } : { ok: true, status: 200, data: a.plan() ?? {} };
        } },
    });
    const args = { rango: RANGO, casillas: casillas() };
    const r1 = await llamarTool(m, "guardar_borrador", args);
    assertEquals(r1.resultado?.isError, true, "fallo único: no se guardó nada");
    // el api falso de Kito ignora el override al aplicar: lo que importa es la clave enviada en cada intento
    await llamarTool(m, "guardar_borrador", args);
    const ids = m.escrituras.filter((e) => e.ruta === "meal/plan/items").map((e) => e.cuerpo.client_request_id);
    assertEquals(ids.length, 2);
    assertEquals(ids[0], ids[1]);
    assert(/^[0-9a-f-]{36}$/.test(String(ids[0])));
});

Deno.test("no pisa: casillas ocupadas y bloqueadas se respetan (sin delete_ids) y se avisa", async () => {
    const a = mundoKito({ perfil: perfil() });
    a.ponerPlan({
        id: 5, week_start: SEMANA, status: "draft", revision: 3, origin: "kito", unchecked_item_ids: [1, 2, 3],
        items: [
            casilla(1, "2030-01-08", "lunch", "Sopa"),
            casilla(2, "2030-01-09", "dinner", "Pizza", { state: "locked" }),
            casilla(3, "2030-01-07", "lunch", "Fuera del rango"),
        ],
    });
    const m = mundoMenus(a);
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO, casillas: casillas() });
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    const cuerpo = a.escrituras[0].cuerpo;
    assertEquals([cuerpo.delete_ids, cuerpo.expected_revision, (cuerpo.items as Obj[]).length], [undefined, 3, 6]);
    assert(!(cuerpo.items as Obj[]).some((i) => ["2030-01-08 lunch", "2030-01-09 dinner"].includes(par(i))));
    const final = a.plan()!.items as Obj[];
    assert(final.find((i) => i.id === 1) && final.find((i) => i.id === 2 && i.state === "locked") && final.find((i) => i.id === 3));
    assert((datosDe(datos).avisos as string[]).some((x) => x.includes("2 casilla")));
});

Deno.test("semana aceptada o hecha por la persona: se salta con aviso y no se escribe", async () => {
    for (const plan of [
        { status: "accepted", origin: "kito" },
        { status: "draft", origin: "user" },
    ]) {
        const a = mundoKito({ perfil: perfil() });
        a.ponerPlan({ id: 5, week_start: SEMANA, revision: 4, unchecked_item_ids: [], items: [casilla(1, "2030-01-07", "lunch", "Sopa")], ...plan });
        const m = mundoMenus(a);
        const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO, casillas: casillas() });
        assertEquals(resultado?.isError, true, JSON.stringify(plan));
        assertEquals(a.escrituras.length, 0);
        const d = datosDe(datos);
        assertEquals((d.semanas as Obj[])[0].estado, "saltada");
        assertEquals((d.avisos as string[]).length, 1);
    }
});

Deno.test("una semana de la persona se salta y la otra se escribe", async () => {
    const p = perfil();
    const a = mundoKito({ perfil: p });
    const b = mundoKito({ perfil: p, idInicial: 500 });
    a.ponerPlan({ id: 5, week_start: SEMANA, status: "draft", revision: 2, origin: "user", unchecked_item_ids: [], items: [casilla(1, "2030-01-08", "lunch", "Sopa")] });
    const m = mundoMenus(a, b);
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO2, casillas: CASILLAS2 });
    assertEquals(resultado?.isError, undefined);
    assertEquals(a.escrituras.length, 0);
    assertEquals(b.escrituras.length, 1);
    assertEquals((datosDe(datos).semanas as Obj[]).map((s) => s.estado), ["saltada", "escrito"]);
});

Deno.test("conflictos por semana: la receta con gluten para Ana se guarda y sale como conflicto sin listo_para_aceptar", async () => {
    const a = mundoKito({ perfil: perfil() });
    const m = mundoMenus(a);
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", {
        rango: RANGO, casillas: [{ fecha: "2030-01-08", franja: "lunch", tipo: "receta", receta_id: 10 }],
    });
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    const s = (datosDe(datos).semanas as Obj[])[0];
    assertEquals(s.estado, "escrito");
    assertEquals(s.listo_para_aceptar, false);
    const c = s.conflictos as Obj[];
    assertEquals(c.length, 1);
    assertEquals([c[0].persona, c[0].tipo, c[0].plato], ["Ana", "alergia", "Pasta con tomate"]);
});

Deno.test("si falla una semana (403), las demás siguen y el resultado no es error", async () => {
    const p = perfil();
    const a = mundoKito({ perfil: p });
    const b = mundoKito({ perfil: p, idInicial: 500 });
    const m = mundoMenus(a, b, {
        escribir: { "PATCH meal/plan/items": (c) => c.week_start === SEMANA2 ? { ok: false, status: 403, data: null } : { ok: true, status: 200, data: a.plan() ?? {} } },
    });
    // la semana A escribe de verdad vía el override: se aplica en el mundo A
    const original = m.deps.crearEscritor;
    m.deps.crearEscritor = (t, u, z) => {
        const e = original(t, u, z);
        return async (metodo, ruta, cuerpo = {}) => cuerpo.week_start === SEMANA2 ? e(metodo, ruta, cuerpo) : await a.escribir(metodo, ruta, cuerpo);
    };
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO2, casillas: CASILLAS2 });
    assertEquals(resultado?.isError, undefined, JSON.stringify(datos));
    const s = datosDe(datos).semanas as Obj[];
    assertEquals(s.map((x) => x.estado), ["escrito", "fallo"]);
    assertStringIncludes(String(s[1].error), "No tienes permiso");
    assertEquals(datosDe(datos).ok, true);
});

Deno.test("409 por revisión: la semana sale como fallo con el plan vigente releído", async () => {
    const a = mundoKito({ perfil: perfil() });
    a.ponerPlan({ id: 5, week_start: SEMANA, status: "draft", revision: 3, origin: "kito", unchecked_item_ids: [], items: [casilla(1, "2030-01-07", "lunch", "Sopa")] });
    const m = mundoMenus(a, undefined, { escribir: { "PATCH meal/plan/items": () => ({ ok: false, status: 409, data: null, error: "Stale meal plan revision" }) } });
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", { rango: RANGO, casillas: casillas() });
    assertEquals(resultado?.isError, true);
    const s = (datosDe(datos).semanas as Obj[])[0];
    assertEquals(s.estado, "fallo");
    assertEquals(s.revision_vieja, true);
    assertEquals((s.plan_vigente as Obj).revision, 3);
    assertEquals((s.plan_vigente as Obj).plan_id, 5);
});

Deno.test("validaciones sin escribir: tipo inválido, fuera del rango, receta sin receta_id, texto sin título, doble casilla, vacío", async () => {
    const casos: Obj[][] = [
        [C("2030-01-08", "lunch", "x", { tipo: "plato" })],
        [C("2030-01-07", "lunch")], // antes del rango
        [{ fecha: "2030-01-08", franja: "lunch", tipo: "receta" }],
        [{ fecha: "2030-01-08", franja: "lunch", tipo: "texto" }],
        [C("2030-01-08", "lunch"), C("2030-01-08", "lunch", "otro")],
        [],
        [C("2030-01-08", "snack")], // franja desactivada
        [C("2030-01-08", "lunch", "x", { personas: [99] })],
    ];
    for (const lista of casos) {
        const a = mundoKito({ perfil: perfil() });
        const m = mundoMenus(a);
        const { resultado } = await llamarTool(m, "guardar_borrador", { rango: RANGO, casillas: lista });
        assertEquals(resultado?.isError, true, JSON.stringify(lista));
        assertEquals(a.escrituras, []);
    }
});

Deno.test("tipos en español se traducen al api: sobras, fuera y raciones -> servings", async () => {
    const a = mundoKito({ perfil: perfil() });
    const m = mundoMenus(a);
    await llamarTool(m, "guardar_borrador", {
        rango: RANGO,
        casillas: [
            { fecha: "2030-01-08", franja: "lunch", tipo: "sobras", titulo: "Sobras de ayer" },
            { fecha: "2030-01-08", franja: "dinner", tipo: "fuera", titulo: "Restaurante" },
            { fecha: "2030-01-09", franja: "lunch", tipo: "texto", titulo: "Bocadillo", raciones: 2 },
            { fecha: "2030-01-09", franja: "dinner", tipo: "receta", receta_id: 11, raciones: 3 },
        ],
    });
    const items = a.escrituras[0].cuerpo.items as Obj[];
    assertEquals(items.map((i) => i.kind), ["leftovers", "eat_out", "free_text", "recipe"]);
    assertEquals(items.map((i) => i.servings), [undefined, undefined, 2, 3]);
});

Deno.test("receta sin comprobar + persona con dieta: no se guarda nada", async () => {
    const p = perfilBase({ schedule: [] });
    (p.members as Obj[])[1].diet = "vegetarian";
    const a = mundoKito({ perfil: p, ingredientes: { 12: [{ label: "sin enlazar" }] } });
    const m = mundoMenus(a);
    const { resultado, datos } = await llamarTool(m, "guardar_borrador", {
        rango: RANGO, casillas: [{ fecha: "2030-01-08", franja: "dinner", tipo: "receta", receta_id: 12 }],
    });
    assertEquals(resultado?.isError, true);
    assertStringIncludes(JSON.stringify(datos), "sin catálogo");
    assertEquals(a.escrituras, []);
});

Deno.test("paridad con Kito: mismos fixtures producen las mismas casillas a escribir en ambos", async () => {
    const fixtures: { nombre: string; plan?: Obj; rango: Obj; platos: Obj[] }[] = [
        { nombre: "semana limpia", rango: RANGO, platos: PUNTOS.map(([d, f]) => ({ dia: d, franja: f, titulo: `Plato ${d} ${f}` })) },
        {
            nombre: "huecos con ocupadas y bloqueadas", rango: RANGO,
            plan: { id: 5, week_start: SEMANA, status: "draft", revision: 3, origin: "kito", unchecked_item_ids: [1, 2], items: [casilla(1, "2030-01-08", "lunch", "Sopa"), casilla(2, "2030-01-09", "dinner", "Pizza", { state: "locked" })] },
            platos: PUNTOS.map(([d, f]) => ({ dia: d, franja: f, titulo: `Plato ${d} ${f}` })),
        },
        {
            nombre: "recetas y personas", rango: RANGO,
            platos: [{ dia: "2030-01-08", franja: "dinner", receta_id: 11, personas: [2] }, { dia: "2030-01-09", franja: "lunch", titulo: "Pan", personas: [1] }],
        },
    ];
    for (const f of fixtures) {
        const k = mundoKito({ perfil: perfil() });
        const a = mundoKito({ perfil: perfil() });
        if (f.plan) {
            k.ponerPlan(f.plan);
            a.ponerPlan(f.plan);
        }
        await proponerMenuTool.run({ rango: f.rango, platos: f.platos }, ctxDe(k), { toolUseId: "t", orden: 0 } as never);
        const m = mundoMenus(a);
        const { resultado } = await llamarTool(m, "guardar_borrador", {
            rango: f.rango,
            casillas: f.platos.map((p) => ({
                fecha: p.dia, franja: p.franja, ...(p.receta_id ? { tipo: "receta", receta_id: p.receta_id } : { tipo: "texto", titulo: p.titulo }),
                ...(p.personas ? { personas: p.personas } : {}),
            })),
        });
        assertEquals(resultado?.isError, undefined, f.nombre);
        const pick = (e: Obj) => ({ ...e, client_request_id: undefined });
        assertEquals(a.escrituras.length, k.escrituras.length, f.nombre);
        assertEquals(pick(a.escrituras[0].cuerpo), pick(k.escrituras[0].cuerpo), f.nombre);
        assertEquals(a.plan()!.items, k.plan()!.items, f.nombre);
    }
    // las claves de idempotencia son distintas a propósito (prefijo propio del MCP)
    const k = mundoKito({ perfil: perfil() });
    const a = mundoKito({ perfil: perfil() });
    await proponerMenuTool.run({ rango: RANGO, platos: [{ dia: "2030-01-08", franja: "lunch", titulo: "x" }] }, ctxDe(k), { toolUseId: "t", orden: 0 } as never);
    await llamarTool(mundoMenus(a), "guardar_borrador", { rango: RANGO, casillas: [{ fecha: "2030-01-08", franja: "lunch", tipo: "texto", titulo: "x" }] });
    assertNotEquals(a.escrituras[0].cuerpo.client_request_id, k.escrituras[0].cuerpo.client_request_id);
});
