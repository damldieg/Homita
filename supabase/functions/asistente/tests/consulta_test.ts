// Tests de la skill consulta con un lector falso del api: parámetros que se mandan, solo_mias, filtros de
// tareas, calendarios y salida compacta. Sin red ni BD.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { consulta } from "../skills/consulta/index.ts";
import type { Leer, Tool, ToolCtx } from "../core.ts";

type Llamada = { ruta: string; params: Record<string, string | undefined> };
type Datos = Record<string, unknown | ((p: Record<string, string | undefined>) => unknown)>;

const PERSONAS = [
    { id: 1, name: "Damián", kind: "adult", app_user_id: 501, home_id: 7 },
    { id: 2, name: "Ana", kind: "adult", app_user_id: 502, home_id: 7 },
    { id: 3, name: "Damián (otra casa)", kind: "adult", app_user_id: 501, home_id: 9 },
    { id: 4, name: "Urki", kind: "pet", app_user_id: null, home_id: 7 },
];

const montar = (datos: Datos, over: Partial<ToolCtx> = {}) => {
    const llamadas: Llamada[] = [];
    const leer: Leer = (ruta, params = {}) => {
        llamadas.push({ ruta, params });
        const d = datos[ruta];
        return Promise.resolve(typeof d === "function" ? (d as (p: Record<string, string | undefined>) => unknown)(params) : d);
    };
    const ctx: ToolCtx = {
        token: "t", uid: "u", homeId: "7", timezone: "Europe/Madrid", now: new Date("2026-11-24T10:00:00Z"),
        appUserId: "501", nombreUsuario: "Damián", leer, ...over,
    };
    return { ctx, llamadas };
};
const tool = (n: string): Tool => consulta.herramientas.find((t) => t.name === n)!;
const pers = (...ids: number[]) => ids.map((id) => ({ id, user_id: 99, name: `P${id}` }));
type Out = { elementos: Record<string, unknown>[]; hay_mas: boolean; aviso?: string };
const run = async (n: string, input: Record<string, unknown>, ctx: ToolCtx) => await tool(n).run(input, ctx) as Out;

Deno.test("la skill consulta expone herramientas de lectura sin fecha_actual", () => {
    assertEquals(consulta.herramientas.map((t) => t.name).sort(), [
        "ver_calendarios", "ver_eventos", "ver_listas", "ver_personas", "ver_rutinas", "ver_tareas",
    ]);
    for (const t of consulta.herramientas) {
        assertEquals(t.input_schema.additionalProperties, false);
        assertEquals(t.input_schema.required, []);
    }
});

Deno.test("ver_eventos manda routine=false y el rango de pared (23:30 del último día dentro)", async () => {
    const { ctx, llamadas } = montar({ event: [] });
    await run("ver_eventos", { desde: "2026-11-24", hasta: "2026-11-25", buscar: null, calendario_id: 3, solo_mias: null }, ctx);
    const p = llamadas[0].params;
    assertEquals(llamadas[0].ruta, "event");
    assertEquals(p.routine, "false");
    assertEquals(p.calendar_id, "3");
    assertEquals(p.start_date, String(Date.UTC(2026, 10, 24) / 1000));
    assertEquals(p.end_date, String(Date.UTC(2026, 10, 26) / 1000 - 1));
    assertEquals(p.person_id, undefined);
});

Deno.test("ver_eventos sin fechas usa hoy local como inicio", async () => {
    const { ctx, llamadas } = montar({ event: [] }, { now: new Date("2026-11-24T23:30:00Z") }); // 00:30 del 25 en Madrid
    await run("ver_eventos", {}, ctx);
    assertEquals(llamadas[0].params.start_date, String(Date.UTC(2026, 10, 25) / 1000));
});

Deno.test("ver_eventos compacta y avisa hay_mas con 51 filas", async () => {
    const filas = Array.from({ length: 51 }, (_, i) => ({ id: i, title: `E${i}`, date_at: "2026-11-24 18:30:00", persons: [] }));
    const { ctx } = montar({ event: filas });
    const r = await run("ver_eventos", {}, ctx);
    assertEquals(r.elementos.length, 50);
    assertEquals(r.hay_mas, true);
    assertEquals(r.elementos[0].inicio, "2026-11-24T18:30:00+01:00");
    assertEquals(r.elementos[0].tipo, "evento");
});

Deno.test("solo_mias sin persona vinculada: lista vacía con aviso y sin pedir eventos", async () => {
    const { ctx, llamadas } = montar({ person: PERSONAS }, { appUserId: "999" });
    for (const n of ["ver_eventos", "ver_rutinas", "ver_tareas"]) {
        const r = await run(n, { solo_mias: true, dia: null }, ctx);
        assertEquals(r.elementos, []);
        assert(r.aviso!.includes("no está vinculada"));
    }
    assert(llamadas.every((l) => l.ruta === "person"));
});

Deno.test("solo_mias ignora la persona de otro hogar (home_id) y usa una consulta por persona propia", async () => {
    const { ctx, llamadas } = montar({
        person: PERSONAS,
        event: (p: Record<string, string | undefined>) => [{ id: 10, title: "Mío", date_at: "2026-11-24 10:00:00", persons: pers(Number(p.person_id)) }],
    });
    const r = await run("ver_eventos", { solo_mias: true }, ctx);
    const consultas = llamadas.filter((l) => l.ruta === "event");
    assertEquals(consultas.map((c) => c.params.person_id), ["1"]);
    assertEquals(r.elementos.length, 1);
});

Deno.test("solo_mias con dos personas propias: una consulta por persona y unión sin duplicados", async () => {
    const dos = [...PERSONAS, { id: 5, name: "Damián2", kind: "adult", app_user_id: 501, home_id: 7 }];
    const { ctx, llamadas } = montar({
        person: dos,
        event: (p: Record<string, string | undefined>) => p.person_id === "1"
            ? [{ id: 10, title: "A", date_at: "2026-11-24 10:00:00", persons: pers(1, 5) }, { id: 11, title: "B", date_at: "2026-11-24 12:00:00", persons: pers(1) }]
            : [{ id: 10, title: "A", date_at: "2026-11-24 10:00:00", persons: pers(1, 5) }, { id: 12, title: "C", date_at: "2026-11-24 11:00:00", persons: pers(5) }],
    });
    const r = await run("ver_eventos", { solo_mias: true }, ctx);
    assertEquals(llamadas.filter((l) => l.ruta === "event").map((c) => c.params.person_id).sort(), ["1", "5"]);
    assertEquals(r.elementos.map((e) => e.id), [10, 12, 11]);
});

Deno.test("solo_mias: si la consulta llega al límite avisa de acotar el rango", async () => {
    const filas = Array.from({ length: 200 }, (_, i) => ({ id: i, title: "x", date_at: "2026-11-24 10:00:00", persons: pers(1) }));
    const { ctx } = montar({ person: PERSONAS, event: filas });
    const r = await run("ver_eventos", { solo_mias: true }, ctx);
    assertEquals(r.elementos.length, 50);
    assertEquals(r.hay_mas, true);
    assert(r.aviso!.includes("acota"));
});

Deno.test("ver_rutinas sin fecha lista definiciones (GET /routine); solo_mias por persons[].id, no user_id", async () => {
    const rutinas = [
        { id: 1, title: "Perro", days: [1], time: "08:00:00", frequency: "daily", active: true, calendar_name: "Casa", persons: [{ id: 1, user_id: 2, name: "Damián" }] },
        { id: 2, title: "Ajena", days: [2], time: "09:00:00", frequency: "daily", active: true, calendar_name: "Casa", persons: [{ id: 2, user_id: 1, name: "Ana" }] },
        { id: 3, title: "Nadie", days: [3], time: "10:00:00", frequency: "daily", active: true, calendar_name: "Casa", persons: [] },
    ];
    const { ctx, llamadas } = montar({ person: PERSONAS, routine: rutinas });
    const todas = await run("ver_rutinas", {}, ctx);
    assertEquals(todas.elementos.map((e) => e.id), [1, 2, 3]);
    assertEquals(todas.elementos[2].asignada_a, "sin asignar");
    const mias = await run("ver_rutinas", { solo_mias: true }, ctx);
    assertEquals(mias.elementos.map((e) => e.id), [1]);
    assert(llamadas.some((l) => l.ruta === "routine"));
    assert(!llamadas.some((l) => l.ruta === "event"));
});

Deno.test("ver_rutinas con dia: GET /event routine=true con el rango de pared y salida tipo rutina", async () => {
    const { ctx, llamadas } = montar({
        event: [{ id: 50, routine_id: 4, title: "Perro", date_at: "2026-11-25 08:00:00", persons: [] }],
    });
    const r = await run("ver_rutinas", { dia: "2026-11-25" }, ctx);
    const p = llamadas[0].params;
    assertEquals(llamadas[0].ruta, "event");
    assertEquals(p.routine, "true");
    assertEquals(p.start_date, String(Date.UTC(2026, 10, 25) / 1000));
    assertEquals(p.end_date, String(Date.UTC(2026, 10, 26) / 1000 - 1));
    assertEquals(r.elementos[0], {
        tipo: "rutina", rutina_id: 4, titulo: "Perro", inicio: "2026-11-25T08:00:00+01:00", asignada_a: "sin asignar",
    });
    assert(!JSON.stringify(r).includes('"evento"'));
});

Deno.test("ver_rutinas fuera de la ventana hoy..hoy+89 avisa; dentro no", async () => {
    // now = 2026-11-24; ventana hasta 2027-02-21.
    const { ctx } = montar({ event: [] });
    const ayer = await run("ver_rutinas", { dia: "2026-11-23" }, ctx);
    assertEquals(ayer.elementos, []);
    assert(ayer.aviso?.includes("89 días"));
    assert((await run("ver_rutinas", { desde: "2026-12-01", hasta: "2027-02-22" }, ctx)).aviso !== undefined);
    assertEquals((await run("ver_rutinas", { desde: "2026-11-24", hasta: "2027-02-21" }, ctx)).aviso, undefined);
    assertEquals((await run("ver_rutinas", { dia: "2026-11-25" }, ctx)).aviso, undefined);
});

const TAREAS = [
    { id: 1, title: "Pendiente", task_list_name: "Compra", priority: "alta", due_at: "2026-11-23 23:00:00", completed_at: null, persons: pers(1) },
    { id: 2, title: "Hecha vencida", task_list_name: "Compra", priority: "baja", due_at: "2026-11-01 10:00:00", completed_at: "2026-11-02 10:00:00", persons: pers(1) },
    { id: 3, title: "Futura", task_list_name: "Casa", priority: "media", due_at: "2026-12-01 10:00:00", completed_at: null, persons: pers(2) },
    { id: 4, title: "Sin fecha", task_list_name: "Casa", priority: "media", due_at: null, completed_at: null, persons: [] },
];

Deno.test("ver_tareas: por defecto solo pendientes; estado completadas y todas", async () => {
    const { ctx } = montar({ task: TAREAS });
    assertEquals((await run("ver_tareas", {}, ctx)).elementos.map((t) => t.id), [1, 3, 4]);
    assertEquals((await run("ver_tareas", { estado: "completadas" }, ctx)).elementos.map((t) => t.id), [2]);
    assertEquals((await run("ver_tareas", { estado: "todas" }, ctx)).elementos.map((t) => t.id), [1, 2, 3, 4]);
});

Deno.test("ver_tareas vencidas: compara due_at UTC con ahora, excluye completadas y sin fecha", async () => {
    const { ctx } = montar({ task: TAREAS }); // ahora = 2026-11-24 10:00 UTC
    assertEquals((await run("ver_tareas", { vencidas: true }, ctx)).elementos.map((t) => t.id), [1]);
    assertEquals((await run("ver_tareas", { vencidas: true, estado: "todas" }, ctx)).elementos.map((t) => t.id), [1]);
    // due_at de ayer 23:00 UTC con now justo a las 22:59 UTC de ayer no está vencida
    const antes = montar({ task: TAREAS }, { now: new Date("2026-11-23T22:59:00Z") });
    assertEquals((await run("ver_tareas", { vencidas: true }, antes.ctx)).elementos, []);
});

Deno.test("ver_tareas pasa lista y prioridad al api; solo_mias filtra por persons[].id; combinaciones", async () => {
    const { ctx, llamadas } = montar({ person: PERSONAS, task: TAREAS });
    const r = await run("ver_tareas", { lista_id: 5, prioridad: "ALTA", solo_mias: true, vencidas: true }, ctx);
    const t = llamadas.find((l) => l.ruta === "task")!;
    assertEquals(t.params.task_list_id, "5");
    assertEquals(t.params.priority, "alta");
    assertEquals(r.elementos.map((e) => e.id), [1]);
    assertEquals(r.elementos[0].vence, "2026-11-24T00:00:00+01:00");
    const mias = await run("ver_tareas", { solo_mias: true }, montar({ person: PERSONAS, task: TAREAS }).ctx);
    assertEquals(mias.elementos.map((e) => e.id), [1]);
});

Deno.test("ver_tareas rechaza valores no válidos", async () => {
    const { ctx } = montar({ task: TAREAS });
    for (const input of [{ estado: "x" }, { prioridad: "urgente" }]) {
        let fallo = false;
        try {
            await tool("ver_tareas").run(input, ctx);
        } catch {
            fallo = true;
        }
        assert(fallo);
    }
});

Deno.test("ver_calendarios: compartido_con en paralelo, siempre con calendar_id, fallo parcial y tope 50", async () => {
    const cals = Array.from({ length: 52 }, (_, i) => ({ id: i + 1, name: `C${i + 1}`, can_edit: i === 0 }));
    const { ctx, llamadas } = montar({
        calendar: cals,
        "calendar/user": (p: Record<string, string | undefined>) => p.calendar_id === "2" ? { error: 500 } : [{ name: "Ana" }, { name: "Leo" }],
    });
    const r = await run("ver_calendarios", {}, ctx);
    const us = llamadas.filter((l) => l.ruta === "calendar/user");
    assertEquals(us.length, 50);
    assert(us.every((l) => /^\d+$/.test(l.params.calendar_id ?? "")));
    assertEquals(r.elementos.length, 50);
    assertEquals(r.hay_mas, true);
    assertEquals(r.elementos[0], { id: 1, nombre: "C1", compartido_con: ["Ana", "Leo"], puedo_editar: true });
    assertEquals(r.elementos[1].compartido_con, "no disponible");
});

Deno.test("ver_listas y ver_personas compactas; personas de otro hogar fuera", async () => {
    const { ctx } = montar({ "task-list": [{ id: 1, name: "Compra", pending_task_count: 2 }], person: PERSONAS });
    assertEquals((await run("ver_listas", {}, ctx)).elementos, [{ id: 1, nombre: "Compra", pendientes: 2 }]);
    const p = await run("ver_personas", {}, ctx);
    assertEquals(p.elementos.map((e) => e.id), [1, 2, 4]);
    assertEquals(p.elementos[2], { id: 4, nombre: "Urki", tipo: "pet", tiene_cuenta: false });
});

Deno.test("error del api → objeto de error compacto, sin datos del hogar", async () => {
    const { ctx } = montar({ "task-list": { error: 500, detalle: "boom" } });
    const r = await tool("ver_listas").run({}, ctx) as Record<string, unknown>;
    assertEquals(r.codigo, 500);
    assert(!JSON.stringify(r).includes("boom"));
});
