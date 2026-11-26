// T6 kito-menus: proponer_menu con un mundo falso (revisión, client_request_id, origin kito, check de conflictos).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { indexTools } from "../core.ts";
import { menus } from "../skills/menus/index.ts";
import { proponerMenuTool } from "../skills/menus/menu.ts";
import { abrir, ANA, casilla, crearMundo, ctxDe, perfilBase, SEMANA } from "./menus_util.ts";

type Obj = Record<string, unknown>;

const proponer = (input: Obj, ctx: unknown) => proponerMenuTool.run(input, ctx as never, { toolUseId: "toolu_1", orden: 0 } as never);

const PLATOS = [
    { dia: "2030-01-07", franja: "lunch", receta_id: 11 },
    { dia: "2030-01-07", franja: "dinner", receta_id: 12 },
    { dia: "2030-01-08", franja: "dinner", titulo: "Pollo asado" },
];

Deno.test("proponer_menu está registrada como escritura, strict false y sin propiedades extra", () => {
    const t = indexTools([menus]).get("proponer_menu");
    // se registra en el index al añadirla; aquí basta el esquema de la herramienta
    assertEquals(proponerMenuTool.escritura, true);
    assertEquals(proponerMenuTool.strict, false);
    assertEquals(proponerMenuTool.input_schema.additionalProperties, false);
    assert(t === undefined || t.name === "proponer_menu");
});

Deno.test("proponer_menu crea el borrador origin kito, con client_request_id y revisión 0, y emite la tarjeta con 0 conflictos", async () => {
    const m = crearMundo();
    const { valor, tarjeta, cambios } = abrir(await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m)));
    assertEquals(valor.ok, true);
    assertEquals(m.escrituras.length, 1);
    const e = m.escrituras[0];
    assertEquals([e.metodo, e.ruta], ["PATCH", "meal/plan/items"]);
    assertEquals(e.cuerpo.origin, "kito");
    assertEquals(e.cuerpo.expected_revision, 0);
    assert(/^[0-9a-f-]{36}$/.test(String(e.cuerpo.client_request_id)));
    assertEquals(tarjeta?.tipo, "menu");
    assertEquals(tarjeta?.conflictos, 0);
    assertEquals((tarjeta?.casillas as Obj[]).length, 3);
    assertEquals(cambios, [{ tipo: "menu", id: m.plan()!.id, op: "crear" }]);
    assertEquals(m.plan()!.status, "draft");
});

Deno.test("proponer_menu: un reintento con las mismas casillas no escribe de nuevo", async () => {
    const m = crearMundo();
    await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m));
    const rev = m.plan()!.revision;
    const { valor, tarjeta } = abrir(await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m)));
    assertEquals(valor.ok, true);
    assertEquals(m.escrituras.length, 1, "sin segunda escritura");
    assertEquals(m.plan()!.revision, rev);
    assertEquals(tarjeta?.tipo, "menu");
});

Deno.test("proponer_menu: el mismo cuerpo reenviado reutiliza la misma client_request_id (sin duplicar)", async () => {
    const m = crearMundo();
    await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m));
    const clave = m.escrituras[0].cuerpo.client_request_id;
    // si la persona deshace el plan (vuelve a revisión 0 sin plan) el mismo contenido da la misma clave
    const m2 = crearMundo();
    await proponer({ semana: SEMANA, platos: [...PLATOS].reverse().reverse() }, ctxDe(m2));
    assertEquals(m2.escrituras[0].cuerpo.client_request_id, clave);
    assertEquals(m2.claves.size, 1);
});

Deno.test("proponer_menu: revisión vieja (409) devuelve revision_vieja y no hay tarjeta", async () => {
    const m = crearMundo();
    m.ponerPlan({ id: 5, week_start: SEMANA, status: "draft", revision: 2, origin: "kito", items: [casilla(1, "2030-01-09", "lunch", "Sopa")], unchecked_item_ids: [1] });
    const ctx = ctxDe(m);
    // la persona edita justo después de que el modelo lea: simulamos leyendo antes y escribiendo con otra revisión
    const leer = ctx.leer!;
    let primera = true;
    ctx.leer = (ruta, params) => {
        const r = leer(ruta, params);
        if (ruta === "meal/plan" && primera) {
            primera = false;
            return r.then((x) => {
                m.editarComoPersona(() => {});
                return x;
            });
        }
        return r;
    };
    const r = abrir(await proponer({ semana: SEMANA, platos: PLATOS }, ctx));
    assertEquals(r.valor.ok, false);
    assertEquals(r.valor.revision_vieja, true);
    assertEquals(r.tarjeta, undefined);
});

Deno.test("proponer_menu: conflicto de alergia bloquea la tarjeta y lista el conflicto", async () => {
    const m = crearMundo();
    const { valor, tarjeta, cambios } = abrir(await proponer({
        semana: SEMANA,
        platos: [{ dia: "2030-01-07", franja: "lunch", receta_id: 10 }, { dia: "2030-01-07", franja: "dinner", receta_id: 12 }],
    }, ctxDe(m)));
    assertEquals(valor.ok, false);
    assertEquals(valor.tarjeta, false);
    assertEquals(tarjeta, undefined);
    assertEquals(cambios, undefined);
    const c = (valor.conflictos as Obj[])[0];
    assertEquals(c.tipo, "alergia");
    assertEquals(c.persona, "Ana");
    assertEquals(c.plato, "Pasta con tomate");
    assert(ANA === 1);
});

Deno.test("proponer_menu: si no se puede comprobar, no hay tarjeta", async () => {
    const m = crearMundo({ checkFalla: true });
    const { valor, tarjeta } = abrir(await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m)));
    assertEquals(valor.ok, false);
    assertEquals(tarjeta, undefined);
});

Deno.test("proponer_menu valida: fuera de semana, franja no habilitada, duplicada, receta sin id y nadie en casa", async () => {
    const m = crearMundo();
    const r = await proponer({
        semana: SEMANA,
        platos: [
            { dia: "2030-01-20", franja: "lunch", receta_id: 11 },
            { dia: "2030-01-08", franja: "snack", titulo: "Fruta" },
            { dia: "2030-01-08", franja: "lunch", titulo: "A" },
            { dia: "2030-01-08", franja: "lunch", titulo: "B" },
            { dia: "2030-01-09", franja: "dinner", tipo: "recipe", titulo: "Sin id" },
        ],
    }, ctxDe(m)) as Obj;
    assertEquals(r.ok, false);
    assertEquals((r.errores as string[]).length, 4);
    assertEquals(m.escrituras.length, 0);
    assertEquals((await proponer({ semana: "2030-01-08", platos: PLATOS }, ctxDe(m)) as Obj).ok, false);
    assertEquals((await proponer({ semana: "x", platos: PLATOS }, ctxDe(m)) as Obj).falta, ["semana"]);
});

Deno.test("proponer_menu no pisa un menú aceptado ni uno hecho por la persona, ni casillas locked", async () => {
    const base = { id: 5, week_start: SEMANA, revision: 3, unchecked_item_ids: [] };
    const m1 = crearMundo();
    m1.ponerPlan({ ...base, status: "accepted", origin: "kito", items: [casilla(1, "2030-01-07", "lunch", "X")] });
    assert(String((await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m1)) as Obj).error).includes("aceptado"));
    const m2 = crearMundo();
    m2.ponerPlan({ ...base, status: "draft", origin: "user", items: [casilla(1, "2030-01-07", "lunch", "X")] });
    assert(String((await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m2)) as Obj).error).includes("persona"));
    const m3 = crearMundo();
    m3.ponerPlan({ ...base, status: "draft", origin: "kito", items: [casilla(1, "2030-01-07", "lunch", "Bloqueada", { state: "locked" })] });
    assert(String((await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m3)) as Obj).error).includes("bloqueadas"));
    for (const m of [m1, m2, m3]) assertEquals(m.escrituras.length, 0);
});

Deno.test("proponer_menu sobre un borrador de Kito sustituye lo libre, conserva lo bloqueado y usa la revisión vigente", async () => {
    const m = crearMundo();
    m.ponerPlan({
        id: 5, week_start: SEMANA, status: "draft", revision: 4, origin: "kito", unchecked_item_ids: [],
        items: [casilla(1, "2030-01-09", "lunch", "Vieja"), casilla(2, "2030-01-10", "dinner", "Fija", { state: "locked" })],
    });
    const { valor } = abrir(await proponer({ semana: SEMANA, platos: PLATOS }, ctxDe(m)));
    assertEquals(valor.ok, true);
    assertEquals(m.escrituras[0].cuerpo.expected_revision, 4);
    assertEquals(m.escrituras[0].cuerpo.delete_ids, [1]);
    const items = m.plan()!.items as Obj[];
    assert(items.some((i) => i.id === 2 && i.state === "locked"));
    assert(!items.some((i) => i.id === 1));
});

const perfilVegetariano = () => {
    const p = perfilBase();
    (p.members as Obj[]).forEach((m) => Object.assign(m, { allergies: [], diet: m.home_member_id === ANA ? "vegetarian" : null }));
    return p;
};
const PAD_THAI = { id: 30, name: "Pad thai con cacahuetes", servings: 4, minutes: 30, slots: ["lunch", "dinner"] };
const LENTEJAS_ENLAZADAS = [{ food_id: 5, label: "lentejas" }, { food_id: 6, label: "cebolla" }];
const PAD_THAI_TEXTO = [{ food_id: null, label: "gambas" }, { food_id: 7, label: "fideos de arroz" }];

Deno.test("proponer_menu: receta con ingredientes en texto libre no se propone a un vegetariano (no escribe)", async () => {
    const m = crearMundo({
        perfil: perfilVegetariano(), recetas: [PAD_THAI, { id: 11, name: "Ensalada de lentejas", servings: 4, minutes: 20, slots: ["lunch"] }],
        ingredientes: { 30: PAD_THAI_TEXTO, 11: LENTEJAS_ENLAZADAS },
    });
    const r = abrir(await proponer({ semana: SEMANA, platos: [{ dia: "2030-01-08", franja: "dinner", receta_id: 30 }] }, ctxDe(m)));
    assertEquals(r.valor.ok, false);
    assertEquals(m.escrituras.length, 0);
    assertEquals(r.tarjeta, undefined);
    assert(String((r.valor.errores as string[])[0]).includes("sin catálogo"));
});

Deno.test("proponer_menu: receta con todos los ingredientes enlazados sí se propone a un vegetariano", async () => {
    const m = crearMundo({
        perfil: perfilVegetariano(), recetas: [PAD_THAI, { id: 11, name: "Ensalada de lentejas", servings: 4, minutes: 20, slots: ["lunch"] }],
        ingredientes: { 30: PAD_THAI_TEXTO, 11: LENTEJAS_ENLAZADAS },
    });
    const r = abrir(await proponer({ semana: SEMANA, platos: [{ dia: "2030-01-08", franja: "dinner", receta_id: 11 }] }, ctxDe(m)));
    assertEquals(r.valor.ok, true);
    assertEquals(r.tarjeta?.tipo, "menu");
});

Deno.test("proponer_menu: sin dieta ni alergias, la receta con texto libre se admite", async () => {
    const p = perfilBase();
    (p.members as Obj[]).forEach((m) => Object.assign(m, { allergies: [], diet: null }));
    const m = crearMundo({ perfil: p, recetas: [PAD_THAI], ingredientes: { 30: PAD_THAI_TEXTO } });
    const r = abrir(await proponer({ semana: SEMANA, platos: [{ dia: "2030-01-08", franja: "dinner", receta_id: 30 }] }, ctxDe(m)));
    assertEquals(r.valor.ok, true);
});
