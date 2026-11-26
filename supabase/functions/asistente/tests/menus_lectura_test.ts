// T5 kito-menus: leer_perfil, leer_semana y buscar_recetas con un mundo falso (sin BD ni red).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { indexTools } from "../core.ts";
import { menus } from "../skills/menus/index.ts";
import { buscarRecetasTool, leerPerfilTool, leerSemanaTool, paisesDe } from "../skills/menus/lectura.ts";
import { casilla, crearMundo, ctxDe, perfilBase, SEMANA } from "./menus_util.ts";

type Obj = Record<string, unknown>;
const correr = (t: { run: (i: Obj, c: never) => Promise<unknown> }, input: Obj, ctx: unknown) => t.run(input, ctx as never) as Promise<Obj>;

Deno.test("la skill expone las herramientas de lectura con esquemas sin propiedades extra y strict desactivado", () => {
    const tools = indexTools([menus]);
    for (const n of ["leer_perfil", "leer_semana", "buscar_recetas"]) {
        const t = tools.get(n)!;
        assert(t, n);
        assertEquals(t.strict, false, n);
        assertEquals(t.escritura === true, false, n);
        assertEquals(t.input_schema.additionalProperties, false, n);
    }
});

Deno.test("leer_perfil: personas, alergias y franjas; sin datos de salud sin menu.health.view", async () => {
    const m = crearMundo();
    const r = await correr(leerPerfilTool, {}, ctxDe(m));
    const texto = JSON.stringify(r);
    const comen = r.comen as Obj[];
    assertEquals(comen.map((c) => c.nombre), ["Ana", "Leo"]);
    assertEquals((comen[0].alergias as Obj[])[0].alergeno, "gluten");
    assertEquals((r.hogar as Obj).franjas, [{ franja: "lunch", hora: "14:00" }, { franja: "dinner", hora: "21:00" }]);
    assert(!texto.includes("secreto-salud") && !texto.includes("perder peso"), "salud filtrada");
    assertEquals(r.pendiente, undefined);
    // con el permiso, sí
    const con = await correr(leerPerfilTool, {}, ctxDe(m, { permisos: ["menu.view", "menu.health.view"] }));
    assert(JSON.stringify(con).includes("secreto-salud"));
});

Deno.test("leer_perfil tolera countries ausente (aviso) y lo usa cuando está (texto u objetos)", async () => {
    const sin = await correr(leerPerfilTool, {}, ctxDe(crearMundo()));
    assertEquals(sin.paises, []);
    assert(String(sin.aviso_paises).includes("no asumas ninguna cocina"));
    const con = await correr(leerPerfilTool, {}, ctxDe(crearMundo({ perfil: perfilBase({ countries: ["AR", { code: "ES", name: "España" }] }) })));
    assertEquals(con.paises, ["AR", "España"]);
    assertEquals(con.aviso_paises, undefined);
    assertEquals(paisesDe({ profile: { preferences: { countries: ["MX"] } } }), ["MX"]);
    assertEquals(paisesDe({}), []);
});

Deno.test("leer_perfil avisa de las alergias sin responder y falla con error claro si el api falla", async () => {
    const p = perfilBase();
    ((p.members as Obj[])[1]).allergies_answered = false;
    const r = await correr(leerPerfilTool, {}, ctxDe(crearMundo({ perfil: p })));
    assertEquals((r.pendiente as Obj).alergias_sin_responder, ["Leo"]);
    const ctx = ctxDe(crearMundo(), { leer: () => Promise.resolve({ error: 500 }) });
    let msg = "";
    try {
        await leerPerfilTool.run({}, ctx);
    } catch (e) {
        msg = (e as Error).message;
    }
    assert(msg.includes("No he podido leer"));
});

Deno.test("leer_semana: 7 días, días fuera señalados para confirmar, eventos del día y menú existente", async () => {
    const m = crearMundo({
        eventos: [{ id: 1, title: "Cumple", date_at: "2030-01-09 18:00:00", end_date: null, calendar_name: "Familia", persons: [] }],
    });
    m.ponerPlan({
        id: 5, week_start: SEMANA, status: "draft", revision: 2, origin: "kito", unchecked_item_ids: [9],
        items: [casilla(9, "2030-01-07", "lunch", "Lentejas", { state: "rejected" })],
    });
    const r = await correr(leerSemanaTool, { fecha: "2030-01-10" }, ctxDe(m));
    assertEquals(r.semana, { inicio: SEMANA, fin: "2030-01-13" });
    const dias = r.dias as Obj[];
    assertEquals(dias.length, 7);
    assertEquals(dias[2].dia, "miércoles");
    assertEquals((dias[2].fuera as Obj[]), [{ persona: "Leo", franja: "comida", estado: "out" }]);
    assertEquals((dias[0].fuera as Obj[]).length, 0);
    assert(String(r.confirmar).includes("personas fuera"));
    assertEquals(((dias[2].eventos as Obj[])[0]).titulo, "Cumple");
    const menu = r.menu as Obj;
    assertEquals([menu.plan_id, menu.revision, menu.estado, menu.origen], [5, 2, "draft", "kito"]);
    assertEquals((menu.casillas as Obj[])[0].estado, "rejected");
    assertEquals((menu.casillas as Obj[])[0].comprobada, false);
    assertEquals((await correr(leerSemanaTool, { fecha: "mañana" }, ctxDe(m))).error, "La fecha debe tener formato AAAA-MM-DD.");
});

Deno.test("leer_semana sin fecha usa la semana de hoy en la zona del usuario; sin menú, menu es null", async () => {
    const m = crearMundo();
    const r = await correr(leerSemanaTool, {}, ctxDe(m)); // 2030-01-03 es jueves → semana del 2029-12-31
    assertEquals((r.semana as Obj).inicio, "2029-12-31");
    assertEquals(m.lecturas.filter((l) => l.ruta === "meal/plan")[0].params.week_start, "2029-12-31");
    const r2 = await correr(leerSemanaTool, { fecha: SEMANA }, ctxDe(m));
    assertEquals(r2.menu, null);
});

Deno.test("buscar_recetas: recetario filtrado e historial de semanas anteriores para no repetir", async () => {
    const m = crearMundo({
        historial: {
            "2029-12-31": { id: 1, week_start: "2029-12-31", items: [{ day: "2030-01-02", slot: "dinner", kind: "recipe", recipe_id: 12, title: "Tortilla de patatas" }] },
        },
    });
    const r = await correr(buscarRecetasTool, { texto: "pasta", semana: SEMANA }, ctxDe(m));
    assertEquals((r.recetas as Obj[]).map((x) => x.nombre), ["Pasta con tomate"]);
    assertEquals(r.hay_mas, false);
    assertEquals((r.ya_tomados as Obj[]).map((x) => x.titulo), ["Tortilla de patatas"]);
    assertEquals((r.ya_tomados as Obj[])[0].semana, "2029-12-31");
    // pide 3 semanas anteriores por defecto, y como máximo 8
    assertEquals(m.lecturas.filter((l) => l.ruta === "meal/plan").length, 3);
    const m2 = crearMundo();
    await correr(buscarRecetasTool, { semana: SEMANA, semanas_historial: 50 }, ctxDe(m2));
    assertEquals(m2.lecturas.filter((l) => l.ruta === "meal/plan").length, 8);
    assertEquals((await correr(buscarRecetasTool, { franja: "brunch" }, ctxDe(m))).error, "Franja no válida.");
});

Deno.test("buscar_recetas con recetario vacío sugiere guardar recetas con pasos", async () => {
    const r = await correr(buscarRecetasTool, { texto: "zzz" }, ctxDe(crearMundo()));
    assertEquals(r.recetas, []);
    assert(String(r.aviso).includes("guardar_receta"));
});

Deno.test("buscar_recetas: con dieta en el hogar excluye las recetas con ingredientes sin catálogo y lo avisa", async () => {
    const p = perfilBase();
    (p.members as Obj[]).forEach((m) => Object.assign(m, { allergies: [], diet: m.home_member_id === 1 ? "vegetarian" : null }));
    const m = crearMundo({
        perfil: p,
        recetas: [
            { id: 30, name: "Pad thai con cacahuetes", servings: 4, minutes: 30, slots: ["dinner"] },
            { id: 11, name: "Ensalada de lentejas", servings: 4, minutes: 20, slots: ["lunch"] },
        ],
        ingredientes: { 30: [{ food_id: null, label: "gambas" }], 11: [{ food_id: 5, label: "lentejas" }] },
    });
    const r = await correr(buscarRecetasTool, {}, ctxDe(m));
    assertEquals((r.recetas as Obj[]).map((x) => x.id), [11]);
    assertEquals((r.excluidas_sin_catalogo as Obj[]).map((x) => x.id), [30]);
    assert(String(r.aviso_excluidas).includes("catálogo"));
});

Deno.test("leer_perfil expone la zona horaria del hogar y la fecha y hora locales de hoy", async () => {
    // 2030-01-03 23:30 UTC = jueves 4 de enero 00:30 en Madrid (UTC+1)
    const m = crearMundo();
    const r = await leerPerfilTool.run({}, ctxDe(m, { now: new Date("2030-01-03T23:30:00Z") }), { toolUseId: "t", orden: 0 } as never) as Obj;
    assertEquals(r.hoy, { zona_horaria: "Europe/Madrid", fecha: "2030-01-04", dia: "viernes", hora: "00:30" });
    // sin zona en el perfil usa la del usuario; una zona no válida también
    const sin = crearMundo({ perfil: perfilBase({ timezone: undefined }) });
    const r2 = await leerPerfilTool.run({}, ctxDe(sin, { timezone: "America/Argentina/Buenos_Aires", now: new Date("2030-01-03T23:30:00Z") }), { toolUseId: "t", orden: 0 } as never) as Obj;
    assertEquals((r2.hoy as Obj).fecha, "2030-01-03");
    const mala = crearMundo({ perfil: perfilBase({ timezone: "Mars/Olympus" }) });
    const r3 = await leerPerfilTool.run({}, ctxDe(mala), { toolUseId: "t", orden: 0 } as never) as Obj;
    assertEquals((r3.hoy as Obj).zona_horaria, "Europe/Madrid");
});
