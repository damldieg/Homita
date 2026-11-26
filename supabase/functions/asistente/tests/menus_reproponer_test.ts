// T7 kito-menus: reproponer solo cambia las casillas rejected; locked y aceptadas intactas; revisión vigente.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { reproponerTool } from "../skills/menus/menu.ts";
import { abrir, casilla, crearMundo, ctxDe, SEMANA } from "./menus_util.ts";

type Obj = Record<string, unknown>;
const repro = (input: Obj, ctx: unknown) => reproponerTool.run(input, ctx as never, { toolUseId: "toolu_2", orden: 0 } as never);

const plan = (over: Obj = {}, items?: Obj[]): Obj => ({
    id: 5, week_start: SEMANA, status: "draft", revision: 3, origin: "kito", unchecked_item_ids: [],
    items: items ?? [
        casilla(1, "2030-01-07", "lunch", "Ensalada de lentejas", { kind: "recipe", recipe_id: 11, state: "rejected" }),
        casilla(2, "2030-01-07", "dinner", "Tortilla de patatas", { kind: "recipe", recipe_id: 12 }),
        casilla(3, "2030-01-08", "dinner", "Fija", { state: "locked" }),
        casilla(4, "2030-01-09", "dinner", "Pollo", { state: "rejected" }),
    ],
    ...over,
});

Deno.test("reproponer cambia solo las rechazadas, con revisión vigente, y deja locked y el resto intactos", async () => {
    const m = crearMundo();
    m.ponerPlan(plan());
    const { valor, tarjeta, cambios } = abrir(await repro({
        semana: SEMANA,
        cambios: [{ casilla_id: 1, titulo: "Crema de calabaza", motivo: "no os gustan las lentejas" }, { casilla_id: 4, receta_id: 12 }],
    }, ctxDe(m)));
    assertEquals(valor.ok, true);
    assertEquals(valor.cambiadas, 2);
    assertEquals(m.escrituras.length, 1);
    assertEquals(m.escrituras[0].cuerpo.expected_revision, 3);
    assertEquals(m.escrituras[0].cuerpo.origin, "kito");
    assertEquals((m.escrituras[0].cuerpo.items as Obj[]).map((i) => i.id), [1, 4]);
    assertEquals(m.escrituras[0].cuerpo.delete_ids, undefined);
    const items = m.plan()!.items as Obj[];
    assertEquals(items.find((i) => i.id === 1)!.title, "Crema de calabaza");
    assertEquals(items.find((i) => i.id === 1)!.state, null);
    assertEquals(items.find((i) => i.id === 2)!.title, "Tortilla de patatas");
    assertEquals(items.find((i) => i.id === 3)!.state, "locked");
    assertEquals(tarjeta?.tipo, "menu");
    assertEquals(((tarjeta?.casillas as Obj[]).find((c) => c.id === 1) as Obj).motivo, "no os gustan las lentejas");
    assertEquals(cambios, [{ tipo: "menu", id: 5, op: "editar" }]);
});

Deno.test("reproponer rechaza casillas no rechazadas, locked, inexistentes o repetidas y no escribe", async () => {
    const m = crearMundo();
    m.ponerPlan(plan());
    const r = await repro({
        semana: SEMANA,
        cambios: [{ casilla_id: 2, titulo: "X" }, { casilla_id: 3, titulo: "Y" }, { casilla_id: 99, titulo: "Z" }, { casilla_id: 1 }],
    }, ctxDe(m)) as Obj;
    assertEquals(r.ok, false);
    assertEquals((r.errores as string[]).length, 4);
    assert((r.errores as string[])[1].includes("bloqueada"));
    assertEquals(m.escrituras.length, 0);
    const r2 = await repro({ semana: SEMANA, cambios: [{ casilla_id: 1, titulo: "A" }, { casilla_id: 1, titulo: "B" }] }, ctxDe(m)) as Obj;
    assert((r2.errores as string[])[0].includes("repetida"));
});

Deno.test("reproponer sin cambios lista las rechazadas pendientes; sin rechazadas lo dice", async () => {
    const m = crearMundo();
    m.ponerPlan(plan());
    const r = await repro({ semana: SEMANA, cambios: [] }, ctxDe(m)) as Obj;
    assertEquals((r.rechazadas as Obj[]).map((x) => x.casilla_id), [1, 4]);
    const m2 = crearMundo();
    m2.ponerPlan(plan({}, [casilla(2, "2030-01-07", "dinner", "T")]));
    assertEquals(((await repro({ semana: SEMANA, cambios: [] }, ctxDe(m2))) as Obj).ok, false);
});

Deno.test("reproponer no toca un menú aceptado ni una semana sin menú", async () => {
    const m = crearMundo();
    m.ponerPlan(plan({ status: "accepted" }));
    assert(String((await repro({ semana: SEMANA, cambios: [{ casilla_id: 1, titulo: "A" }] }, ctxDe(m)) as Obj).error).includes("aceptado"));
    const vacio = crearMundo();
    assert(String((await repro({ semana: SEMANA, cambios: [{ casilla_id: 1, titulo: "A" }] }, ctxDe(vacio)) as Obj).error).includes("proponer_menu"));
    assertEquals(m.escrituras.length + vacio.escrituras.length, 0);
});

Deno.test("reproponer con revisión vieja (la persona editó entre la lectura y la escritura) devuelve revision_vieja", async () => {
    const m = crearMundo();
    m.ponerPlan(plan());
    const ctx = ctxDe(m);
    const leer = ctx.leer!;
    let una = true;
    ctx.leer = (ruta, params) => {
        const r = leer(ruta, params);
        if (ruta === "meal/plan" && una) {
            una = false;
            return r.then((x) => {
                m.editarComoPersona(() => {});
                return x;
            });
        }
        return r;
    };
    const { valor, tarjeta } = abrir(await repro({ semana: SEMANA, cambios: [{ casilla_id: 1, titulo: "A" }] }, ctx));
    assertEquals(valor.revision_vieja, true);
    assertEquals(tarjeta, undefined);
});

Deno.test("reproponer con un plato que choca con una alergia no emite tarjeta", async () => {
    const m = crearMundo();
    m.ponerPlan(plan());
    const { valor, tarjeta } = abrir(await repro({ semana: SEMANA, cambios: [{ casilla_id: 1, receta_id: 10 }] }, ctxDe(m)));
    assertEquals(valor.ok, false);
    assertEquals(tarjeta, undefined);
    assertEquals((valor.conflictos as Obj[])[0].tipo, "alergia");
});
