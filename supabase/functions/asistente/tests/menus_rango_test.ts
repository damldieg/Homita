// menus-kito-rango: `resolverRango` (lógica pura): rango simple, entre semanas, a media semana, franja desactivada.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { resolverRango } from "../skills/menus/util.ts";
import type { SemanaRango } from "../skills/menus/util.ts";
import { proponerMenuTool } from "../skills/menus/menu.ts";
import { abrir, casilla, crearMundo, ctxDe, perfilBase, SEMANA } from "./menus_util.ts";

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

Deno.test("proponer_menu: el esquema declara `rango` opcional, sin propiedades extra y sin `semana` obligatoria", async () => {
    const { proponerMenuTool } = await import("../skills/menus/menu.ts");
    const e = proponerMenuTool.input_schema as unknown as { properties: Record<string, Record<string, unknown>>; required: string[] };
    assertEquals(e.required, ["platos"]);
    const rango = e.properties.rango as { properties: Record<string, Record<string, unknown>>; required: string[]; additionalProperties: boolean };
    assertEquals(rango.required, ["desde", "hasta"]);
    assertEquals(rango.additionalProperties, false);
    for (const k of ["desde", "hasta"]) {
        assertEquals(rango.properties[k].required, ["fecha", "franja"]);
        assertEquals(rango.properties[k].additionalProperties, false);
    }
    assert(proponerMenuTool.description.includes("esta noche"));
    assert(proponerMenuTool.description.includes("a mediodía"));
});

// ---- proponer_menu con `rango` (un mundo falso por semana) ----

type Obj = Record<string, unknown>;
const proponer = (input: Obj, ctx: unknown) => proponerMenuTool.run(input, ctx as never, { toolUseId: "toolu_1", orden: 0 } as never);
const P = (dia: string, franja: string, titulo = "Plato") => ({ dia, franja, titulo: `${titulo} ${dia} ${franja}` });
// SEMANA = lunes 2030-01-07; lunes noche → viernes mediodía
const RANGO = { desde: { fecha: "2030-01-07", franja: "dinner" }, hasta: { fecha: "2030-01-11", franja: "lunch" } };
const CASILLAS_RANGO = [
    ["2030-01-07", "dinner"], ["2030-01-08", "lunch"], ["2030-01-08", "dinner"], ["2030-01-09", "lunch"], ["2030-01-09", "dinner"],
    ["2030-01-10", "lunch"], ["2030-01-10", "dinner"], ["2030-01-11", "lunch"],
];
const platosRango = () => CASILLAS_RANGO.map(([d, f]) => P(d, f));
const par = (e: Obj) => `${e.day} ${e.slot}`;

Deno.test("proponer_menu con rango: escribe solo las casillas del rango, sin borrar, y emite la tarjeta", async () => {
    const m = crearMundo({ perfil: perfilBase({ schedule: [] }) });
    const { valor, tarjetas, cambios } = abrir(await proponer({ rango: RANGO, platos: platosRango() }, ctxDe(m)));
    const tarjeta = tarjetas?.[0];
    assertEquals(valor.ok, true, JSON.stringify(valor));
    assertEquals(m.escrituras.length, 1);
    const cuerpo = m.escrituras[0].cuerpo;
    assertEquals(cuerpo.week_start, SEMANA);
    assertEquals(cuerpo.origin, "kito");
    assertEquals(cuerpo.delete_ids, undefined, "en modo rango no se borra nada");
    assertEquals((cuerpo.items as Obj[]).map(par), CASILLAS_RANGO.map(([d, f]) => `${d} ${f}`));
    assertEquals((m.plan()!.items as Obj[]).length, 8);
    assertEquals(tarjeta?.tipo, "menu");
    assertEquals(cambios, [{ tipo: "menu", id: m.plan()!.id, op: "crear" }]);
});

Deno.test("proponer_menu con rango: un plato fuera del rango o en franja desactivada se rechaza sin escribir", async () => {
    const m = crearMundo({ perfil: perfilBase({ schedule: [] }) });
    const r1 = abrir(await proponer({ rango: RANGO, platos: [P("2030-01-07", "lunch")] }, ctxDe(m))).valor; // el lunes a mediodía queda antes del rango
    assertEquals(r1.ok, false);
    assert(String((r1.errores as string[])[0]).includes("fuera del rango"));
    const r2 = abrir(await proponer({ rango: RANGO, platos: [P("2030-01-12", "lunch")] }, ctxDe(m))).valor;
    assertEquals(r2.ok, false);
    const r3 = abrir(await proponer({ rango: RANGO, platos: [P("2030-01-08", "snack")] }, ctxDe(m))).valor; // merienda desactivada
    assertEquals(r3.ok, false);
    assertEquals(m.escrituras.length, 0);
});

Deno.test("proponer_menu con rango: rango invertido o demasiado largo da error claro", async () => {
    const m = crearMundo();
    const inv = abrir(await proponer({ rango: { desde: RANGO.hasta, hasta: RANGO.desde }, platos: platosRango() }, ctxDe(m))).valor;
    assertEquals(inv.ok, false);
    assert(String(inv.error).includes("invertido"));
    assertEquals(m.escrituras.length, 0);
});

Deno.test("proponer_menu con rango: solo rellena huecos; casillas con comida o bloqueadas no se tocan ni se borran", async () => {
    const m = crearMundo({ perfil: perfilBase({ schedule: [] }) });
    m.ponerPlan({
        id: 5, week_start: SEMANA, status: "draft", revision: 3, origin: "kito", unchecked_item_ids: [1, 2, 3],
        items: [
            casilla(1, "2030-01-08", "lunch", "Sopa"), // dentro del rango, ya con comida
            casilla(2, "2030-01-09", "dinner", "Pizza", { state: "locked" }), // dentro del rango, bloqueada
            casilla(3, "2030-01-07", "lunch", "Fuera del rango"), // fuera del rango
        ],
    });
    const { valor } = abrir(await proponer({ rango: RANGO, platos: platosRango() }, ctxDe(m)));
    assertEquals(valor.ok, true, JSON.stringify(valor));
    const cuerpo = m.escrituras[0].cuerpo;
    assertEquals(cuerpo.delete_ids, undefined);
    assertEquals(cuerpo.expected_revision, 3);
    assertEquals((cuerpo.items as Obj[]).length, 6);
    assert(!(cuerpo.items as Obj[]).some((i) => ["2030-01-08 lunch", "2030-01-09 dinner"].includes(par(i))));
    const final = m.plan()!.items as Obj[];
    assertEquals(final.length, 9);
    assert(final.find((i) => i.id === 1) && final.find((i) => i.id === 2 && i.state === "locked") && final.find((i) => i.id === 3));
    assert(((valor.avisos as string[]) ?? []).some((a) => a.includes("2 casilla")));
});

Deno.test("proponer_menu con rango: una semana aceptada se salta con aviso y no se escribe", async () => {
    const m = crearMundo({ perfil: perfilBase({ schedule: [] }) });
    m.ponerPlan({ id: 5, week_start: SEMANA, status: "accepted", revision: 4, origin: "kito", unchecked_item_ids: [], items: [casilla(1, "2030-01-07", "lunch", "Sopa")] });
    const { valor } = abrir(await proponer({ rango: RANGO, platos: platosRango() }, ctxDe(m)));
    assertEquals(valor.ok, false);
    assertEquals(m.escrituras.length, 0);
    assert((valor.avisos as string[]).some((a) => a.includes("aceptada")));
    assertEquals(m.plan()!.status, "accepted");
});

Deno.test("proponer_menu con rango: un reintento no duplica y vuelve a mostrar la tarjeta", async () => {
    const m = crearMundo({ perfil: perfilBase({ schedule: [] }) });
    await proponer({ rango: RANGO, platos: platosRango() }, ctxDe(m));
    const { valor, tarjetas } = abrir(await proponer({ rango: RANGO, platos: platosRango() }, ctxDe(m)));
    const tarjeta = tarjetas?.[0];
    assertEquals(valor.ok, true);
    assertEquals(m.escrituras.length, 1, "sin segunda escritura");
    assertEquals(tarjeta?.tipo, "menu");
});

Deno.test("proponer_menu con rango: una receta con alérgeno para quien come ahí no muestra la tarjeta", async () => {
    const m = crearMundo({ perfil: perfilBase({ schedule: [] }) });
    const { valor, tarjetas: tarj } = abrir(await proponer({ rango: RANGO, platos: [{ dia: "2030-01-08", franja: "lunch", receta_id: 10 }] }, ctxDe(m)));
    assertEquals(valor.ok, false); // el servidor falso detecta gluten en la receta 10 (Ana, alergia al gluten)
    assertEquals(tarj, undefined);
});

// ---- rango que cruza dos semanas: un mundo por semana; el enrutador traduce la semana 2 a la del mundo B ----
const SEMANA2 = "2030-01-14";
const enrutar = (a: ReturnType<typeof crearMundo>, b: ReturnType<typeof crearMundo>) => {
    const esB = (semana: unknown) => semana === SEMANA2;
    const aB = <T extends Obj>(o: T): T => ({ ...o, week_start: SEMANA });
    return ctxDe(a, {
        leer: (ruta, params = {}) => {
            if (ruta === "meal/plan") return esB(params.week_start) ? b.leer(ruta, aB(params)) : a.leer(ruta, params);
            if (ruta === "meal/plan/check") return String(params.plan_id).startsWith("5") ? b.leer(ruta, params) : a.leer(ruta, params);
            return a.leer(ruta, params);
        },
        escribir: (metodo, ruta, cuerpo = {}) => esB(cuerpo.week_start) ? b.escribir(metodo, ruta, aB(cuerpo)) : a.escribir(metodo, ruta, cuerpo),
    });
};
const RANGO2 = { desde: { fecha: "2030-01-11", franja: "dinner" }, hasta: { fecha: "2030-01-15", franja: "lunch" } };
const PLATOS2 = [
    P("2030-01-11", "dinner"), P("2030-01-12", "lunch"), P("2030-01-13", "dinner"), P("2030-01-14", "lunch"), P("2030-01-14", "dinner"), P("2030-01-15", "lunch"),
];

Deno.test("proponer_menu con rango entre dos semanas: un lote por semana, dos planes, dos tarjetas y casillas solo del rango", async () => {
    const perfil = perfilBase({ schedule: [] });
    const a = crearMundo({ perfil });
    const b = crearMundo({ perfil, idInicial: 500 });
    const { valor, tarjetas, cambios } = abrir(await proponer({ rango: RANGO2, platos: PLATOS2 }, enrutar(a, b)));
    assertEquals(valor.ok, true, JSON.stringify(valor));
    assertEquals(a.escrituras.length, 1);
    assertEquals(b.escrituras.length, 1);
    assertEquals(a.escrituras[0].cuerpo.week_start, SEMANA);
    assertEquals(b.escrituras[0].cuerpo.week_start, SEMANA, "el enrutador la traduce desde 2030-01-14");
    assertEquals((a.escrituras[0].cuerpo.items as Obj[]).map(par), ["2030-01-11 dinner", "2030-01-12 lunch", "2030-01-13 dinner"]);
    assertEquals((b.escrituras[0].cuerpo.items as Obj[]).map(par), ["2030-01-14 lunch", "2030-01-14 dinner", "2030-01-15 lunch"]);
    assertEquals(tarjetas?.length, 2);
    assertEquals(new Set(tarjetas?.map((t) => t.id)).size, 2, "ids de tarjeta distintos");
    assertEquals(tarjetas?.map((t) => t.id), ["menu-2030-01-07", "menu-2030-01-14"]);
    assertEquals(cambios?.length, 2);
    assertEquals((valor.semanas as Obj[]).map((s) => s.semana), ["2030-01-07", SEMANA2]);
});

Deno.test("proponer_menu con rango entre dos semanas: si una está aceptada, se salta con aviso y la otra se escribe", async () => {
    const perfil = perfilBase({ schedule: [] });
    const a = crearMundo({ perfil });
    const b = crearMundo({ perfil, idInicial: 500 });
    a.ponerPlan({ id: 5, week_start: SEMANA, status: "accepted", revision: 2, origin: "kito", unchecked_item_ids: [], items: [casilla(1, "2030-01-08", "lunch", "Sopa")] });
    const { valor, tarjetas } = abrir(await proponer({ rango: RANGO2, platos: PLATOS2 }, enrutar(a, b)));
    assertEquals(valor.ok, true);
    assertEquals(a.escrituras.length, 0);
    assertEquals(b.escrituras.length, 1);
    assertEquals(tarjetas?.length, 1);
    assert((valor.avisos as string[]).some((x) => x.includes("2030-01-07") && x.includes("aceptada")));
    assertEquals((valor.semanas as Obj[])[0].saltada, true);
});

Deno.test("proponer_menu con rango entre dos semanas: aviso de franja desactivada en un extremo y no se crea esa casilla", async () => {
    const perfil = perfilBase({ schedule: [] });
    const a = crearMundo({ perfil });
    const b = crearMundo({ perfil, idInicial: 500 });
    const rango = { desde: { fecha: "2030-01-11", franja: "dinner" }, hasta: { fecha: "2030-01-14", franja: "snack" } }; // merienda desactivada
    const { valor } = abrir(await proponer({ rango, platos: [P("2030-01-11", "dinner"), P("2030-01-14", "lunch")] }, enrutar(a, b)));
    assertEquals(valor.ok, true, JSON.stringify(valor));
    assert((valor.avisos as string[]).some((x) => x.includes("merienda")));
    assertEquals((b.escrituras[0].cuerpo.items as Obj[]).map(par), ["2030-01-14 lunch"]);
});
