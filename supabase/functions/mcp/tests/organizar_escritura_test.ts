// Herramientas de escritura de organizar (MCP): llamada correcta con el JWT del usuario dentro del hogar, «falta» sin
// llamar al api, ediciones que rellenan, errores traducidos. La paridad de cuerpos con Kito está en organizar_paridad_test.ts.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { crearMundo, TOKEN } from "./util.ts";
import { CALENDARIOS, escrituras, fallo, llamar, mundo, ok, UID } from "./util_organizar.ts";

Deno.test("crear_lista: POST con el JWT, el uid y el hogar activo; clave mcp estable en el mismo minuto", async () => {
    const m = mundo();
    const r = await llamar(m, "crear_lista", { nombre: " Viaje " });
    assertEquals(r.isError, false);
    assertEquals([r.datos.ok, r.datos.id, r.datos.color, r.datos.hecho], [true, 9, "#6923E2", "Creada la lista «Viaje»"]);
    const [e] = escrituras(m);
    assertEquals([e.metodo, e.ruta, e.token, e.uid, e.hogar], ["POST", "task-list/create", TOKEN, UID, "7"]);
    assertEquals({ ...e.cuerpo, client_request_id: undefined, timezone: undefined }, { name: "Viaje", color: "#6923E2", client_request_id: undefined, timezone: undefined });
    assert(typeof e.cuerpo.client_request_id === "string");
    const m2 = mundo();
    await llamar(m2, "crear_lista", { nombre: "Viaje" });
    assertEquals(escrituras(m2)[0].cuerpo.client_request_id, e.cuerpo.client_request_id);
    const m3 = mundo({}, {}, { now: () => new Date("2030-01-07T10:01:30Z") });
    await llamar(m3, "crear_lista", { nombre: "Viaje" });
    assert(escrituras(m3)[0].cuerpo.client_request_id !== e.cuerpo.client_request_id, "otro minuto, otra clave");
});

Deno.test("crear_lista: sin nombre → falta sin llamar; color malo → error; error del api traducido", async () => {
    const m = mundo();
    const r = await llamar(m, "crear_lista", { nombre: "" });
    assertEquals([r.isError, r.datos], [false, { falta: ["nombre"] }]);
    const c = await llamar(m, "crear_lista", { nombre: "A", color: "rojo" });
    assertEquals(c.isError, true);
    assertEquals(escrituras(m), []);
    const m2 = mundo({}, { "POST task-list/create": fallo(403, "Not Allowed") });
    assertEquals((await llamar(m2, "crear_lista", { nombre: "Casa" })).texto, JSON.stringify({ ok: false, error: "No tienes permiso de edición en «Casa»." }));
});

Deno.test("idempotencia: replay con «Not Found» tras borrar → «Ya no existe.» como error", async () => {
    const m = mundo({}, { "POST task-list/create": fallo(500, "Not Found") });
    const r = await llamar(m, "crear_lista", { nombre: "A" });
    assertEquals([r.isError, r.datos.error], [true, "Ya no existe."]);
});

Deno.test("editar_lista: rellena sort, widget y dashboard; sin cambios → falta; inexistente → error", async () => {
    const m = mundo();
    await llamar(m, "editar_lista", { id: 1, nombre: "Casa 2" });
    assertEquals(escrituras(m)[0].cuerpo.sort, "title");
    assertEquals([escrituras(m)[0].cuerpo.widget, escrituras(m)[0].cuerpo.dashboard, escrituras(m)[0].cuerpo.color], [false, true, "#112233"]);
    assertEquals((await llamar(m, "editar_lista", { id: 1 })).datos, { falta: ["qué cambiar"] });
    const r = await llamar(m, "editar_lista", { id: 99, nombre: "X" });
    assertEquals([r.isError, r.datos.error], [true, "Ya no existe."]);
    assertEquals(escrituras(m).length, 1);
});

Deno.test("crear_tarea: varias listas → falta con opciones (no es error) y sin llamar", async () => {
    const m = mundo();
    const r = await llamar(m, "crear_tarea", { titulo: "Pan" });
    assertEquals(r.isError, false);
    assertEquals(r.datos, { falta: ["lista"], opciones: [{ id: 1, nombre: "Casa" }, { id: 2, nombre: "Compra" }] });
    assertEquals(escrituras(m), []);
});

Deno.test("crear_tarea: vence en dos pasos; si el PATCH falla la tarea queda creada y sale un aviso", async () => {
    const m = mundo({}, { "PATCH task/update": fallo(403, "Not Allowed") });
    const r = await llamar(m, "crear_tarea", { titulo: "Dentista", lista_id: 1, vence: "2030-02-01" });
    assertEquals(r.isError, false);
    assertEquals(escrituras(m).map((e) => `${e.metodo} ${e.ruta}`), ["POST task/create", "PATCH task/update"]);
    assert(!("due_at" in escrituras(m)[0].cuerpo));
    assertEquals(escrituras(m)[1].cuerpo.due_at, "2030-02-01 22:59:00");
    assertEquals((r.datos.avisos as string[]).length, 1);
    assertStringIncludes((r.datos.avisos as string[])[0], "no he podido ponerle la fecha límite");
});

Deno.test("crear_tarea: misma llamada en el mismo minuto → misma clave; otra tarea u otra lista → otra", async () => {
    const claves: string[] = [];
    for (const args of [{ titulo: "Pan", lista_id: 1 }, { titulo: "Pan", lista_id: 1 }, { titulo: "Leche", lista_id: 1 }, { titulo: "Pan", lista_id: 2 }]) {
        const m = mundo();
        await llamar(m, "crear_tarea", args);
        claves.push(String(escrituras(m)[0].cuerpo.client_request_id));
    }
    assertEquals(claves[0], claves[1]);
    assertEquals(new Set(claves).size, 3);
});

Deno.test("completar_tarea: true por defecto y desmarcar; editar_tarea rellena el título", async () => {
    const m = mundo();
    await llamar(m, "completar_tarea", { id: 5 });
    await llamar(m, "completar_tarea", { id: 5, completada: false });
    await llamar(m, "editar_tarea", { id: 5, prioridad: "baja" });
    assertEquals(escrituras(m).map((e) => e.cuerpo), [
        { id: 5, completed: true }, { id: 5, completed: false }, { id: 5, title: "Llamar", priority: "baja" },
    ]);
    assert(!escrituras(m).some((e) => "client_request_id" in e.cuerpo), "completar no manda clave");
});

Deno.test("eventos: editar conserva la alarma; varios calendarios → opciones; eventos sin clave de idempotencia", async () => {
    const m = mundo();
    await llamar(m, "editar_evento", { id: 6, titulo: "Cena fuera" });
    assertEquals(escrituras(m)[0].cuerpo, { id: 6, title: "Cena fuera", date_at: "2030-02-01 20:30:00", alarm: 15 });
    const r = await llamar(m, "crear_evento", { titulo: "Cena", inicio: "2030-02-02 20:30" });
    assertEquals(r.datos, { falta: ["calendario"], opciones: [{ id: 10, nombre: "Familia" }, { id: 11, nombre: "Fútbol" }] });
    await llamar(m, "crear_evento", { titulo: "Cena", inicio: "2030-02-02 20:30", calendario_id: 11 });
    const alta = escrituras(m).at(-1)!;
    assertEquals([alta.ruta, alta.cuerpo.calendar_id, alta.cuerpo.date_at, "client_request_id" in alta.cuerpo, "alarm" in alta.cuerpo], ["event/create", 11, "2030-02-02 20:30:00", false, false]);
});

Deno.test("rutinas: semanal sin días → falta; editar reenvía el objeto completo; hasta vacío = no termina", async () => {
    const m = mundo({ calendar: [CALENDARIOS[0]] });
    assertEquals((await llamar(m, "crear_rutina", { titulo: "R", hora: "08:00", frecuencia: "semanal" })).datos, { falta: ["días"] });
    assertEquals(escrituras(m), []);
    const r = await llamar(m, "crear_rutina", { titulo: "R", hora: "08:00", frecuencia: "diaria" });
    assertEquals([r.datos.empieza, r.datos.activa], ["2030-01-07", true]);
    await llamar(m, "editar_rutina", { id: 7, hasta: "" });
    assertEquals(escrituras(m).at(-1)!.cuerpo, {
        id: 7, title: "Regar", frequency: "weekly", interval: 2, days: [1, 3], time: "08:30", start_date: "2030-01-01", end_date: null, active: true,
    });
});

Deno.test("calendarios: sin con quién → falta; sin cuenta → error y no se crea nada; fallo del PATCH → aviso", async () => {
    const m = mundo();
    assertEquals((await llamar(m, "crear_calendario", { nombre: "F" })).datos, { falta: ["con quién se comparte (o solo para ti)"] });
    const sin = await llamar(m, "crear_calendario", { nombre: "F", compartir_con: [{ persona_id: 21 }] });
    assertEquals([sin.isError, sin.datos.sin_cuenta], [true, ["Pedro"]]);
    assertEquals(escrituras(m), []);
    const ajena = await llamar(m, "crear_calendario", { nombre: "F", compartir_con: [{ persona_id: 30 }] });
    assertEquals([ajena.isError, ajena.datos.error], [true, "Esa persona ya no existe en el hogar."]);
    assertEquals(escrituras(m), []);
    const p = mundo({}, { "PATCH calendar/user": fallo(403, "Not Allowed") });
    const r = await llamar(p, "crear_calendario", { nombre: "F", compartir_con: [{ persona_id: 20 }] });
    assertEquals([r.isError, r.datos.id], [false, 40]);
    assertStringIncludes((r.datos.avisos as string[])[0], "solo el propietario puede compartir");
    assert(!("client_request_id" in escrituras(p)[0].cuerpo));
});

Deno.test("compartir_calendario: solo lectura por defecto; puede_editar; sin cuenta, ajena, uno mismo, inexistente y 403", async () => {
    const m = mundo();
    const r = await llamar(m, "compartir_calendario", { calendario_id: 10, persona_id: 20 });
    assertEquals([r.isError, r.datos.ok, r.datos.id], [false, true, 10]);
    assertStringIncludes(String(r.datos.hecho), "Lucía (solo lectura)");
    assertEquals(escrituras(m)[0].cuerpo, { calendar_id: 10, user_id: 502, can_edit: false });
    await llamar(m, "compartir_calendario", { calendario_id: 10, persona_id: 20, puede_editar: true });
    assertEquals(escrituras(m)[1].cuerpo.can_edit, true);
    const antes = escrituras(m).length;
    const sin = await llamar(m, "compartir_calendario", { calendario_id: 10, persona_id: 21 });
    assertEquals([sin.isError, sin.datos.sin_cuenta], [true, ["Pedro"]]);
    assertEquals((await llamar(m, "compartir_calendario", { calendario_id: 10, persona_id: 30 })).datos.error, "Esa persona ya no existe en el hogar.");
    assertStringIncludes(String((await llamar(m, "compartir_calendario", { calendario_id: 10, persona_id: 22 })).datos.error), "eres tú");
    assertEquals((await llamar(m, "compartir_calendario", { calendario_id: 99, persona_id: 20 })).datos.error, "Ya no existe.");
    assertEquals(escrituras(m).length, antes, "ningún error llegó a escribir");
    const p = mundo({}, { "PATCH calendar/user": fallo(403, "Not Allowed") });
    const f = await llamar(p, "compartir_calendario", { calendario_id: 10, persona_id: 20 });
    assertEquals(f.isError, true);
    assertStringIncludes(String(f.datos.error), "solo el propietario puede compartir");
});

Deno.test("errores: 400 con motivo, 404 y genérico; nunca el cuerpo crudo", async () => {
    for (
        const [resp, texto] of [
            [fallo(400, "Name is required"), "No se ha podido hacer: Name is required."], [fallo(404, "x"), "Ya no existe."],
            [fallo(500, "boom secreto"), "No he podido hacerlo ahora mismo."],
        ] as const
    ) {
        const r = await llamar(mundo({}, { "PATCH calendar/update": resp }), "editar_calendario", { id: 10, nombre: "X" });
        assertEquals([r.isError, r.datos.error], [true, texto]);
        assert(!r.texto.includes("secreto"));
    }
});

Deno.test("lectura rota: el aviso del api no filtra el cuerpo y sale como error", async () => {
    const m = crearMundo({}, {}, { "task-list": 500 }, { "POST task/create": ok({ id: 1 }) });
    const r = await llamar(m, "crear_tarea", { titulo: "Pan" });
    assertEquals(r.isError, true);
    assert(!r.texto.includes("interno secreto"));
    assertEquals(m.escrituras, []);
});
