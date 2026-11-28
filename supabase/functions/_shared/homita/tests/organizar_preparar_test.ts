// `preparar*` de «organizar»: la lógica que comparten Kito y el MCP (cuerpo, rellenado de ediciones, «falta»).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { prepararBorrarLista, prepararCrearLista, prepararEditarLista } from "../organizar/listas.ts";
import { prepararCompletarTarea, prepararCrearTarea, prepararEditarTarea } from "../organizar/tareas.ts";
import { prepararCrearEvento, prepararEditarEvento } from "../organizar/eventos.ts";
import { prepararCrearRutina, prepararEditarRutina } from "../organizar/rutinas.ts";
import { personaConCuenta, prepararCrearCalendario, prepararEditarCalendario } from "../organizar/calendarios.ts";
import type { OrgCtx, Preparacion } from "../organizar/tipos.ts";

const respuesta = (data: unknown) => ({ ok: true, status: 200, data });
const ctx = (leer: Record<string, unknown> = {}, detalles: Record<string, unknown> = {}, over: Partial<OrgCtx> = {}): OrgCtx => ({
    homeId: "7", timezone: "Europe/Madrid", now: new Date("2026-11-25T10:00:00Z"), appUserId: "501",
    leer: (ruta) => Promise.resolve(leer[ruta] ?? []),
    escribir: (_m, ruta) => Promise.resolve(respuesta(detalles[ruta] ?? {})),
    ...over,
});
const accion = (p: Preparacion) => {
    assert("accion" in p, `se esperaba una acción y llegó ${JSON.stringify(p)}`);
    return p.accion;
};
const valor = (p: Preparacion) => {
    assert("valor" in p, "se esperaba un resultado terminado");
    return p.valor;
};

Deno.test("listas: alta con color por defecto y clave calculada del cuerpo; falta sin nombre", async () => {
    let visto: unknown;
    const p = await prepararCrearLista({ nombre: " Viaje " }, (cuerpo) => {
        visto = cuerpo;
        return "clave-1";
    });
    assertEquals(accion(p), { op: "crear_lista", args: { name: "Viaje", color: "#6923E2", client_request_id: "clave-1" }, nombre: "Viaje" });
    assertEquals(visto, { name: "Viaje", color: "#6923E2" });
    assertEquals(valor(await prepararCrearLista({})), { falta: ["nombre"] });
    assertEquals((valor(await prepararCrearLista({ nombre: "A", color: "rojo" })) as { ok: boolean }).ok, false);
});

Deno.test("listas: editar rellena sort/widget/dashboard; borrar da nombre y pendientes", async () => {
    const c = ctx({ "task-list": [{ id: 1, name: "Casa", color: "#112233", sort: "title", widget: 0, dashboard: 1, pending_task_count: 3 }] });
    assertEquals(accion(await prepararEditarLista({ id: 1, nombre: "Casa 2" }, c)).args, {
        id: 1, name: "Casa 2", color: "#112233", sort: "title", widget: false, dashboard: true,
    });
    const b = await prepararBorrarLista({ id: 1 }, c);
    assertEquals(accion(b).args, { id: 1 });
    assertEquals((b as { extra: unknown }).extra, { nombre: "Casa", pendientes: 3 });
    assertEquals(valor(await prepararBorrarLista({ id: 9 }, c)), { ok: false, error: "Ya no existe." });
});

Deno.test("tareas: varias listas → falta con opciones; alta con vence en UTC; completar sin completada = true", async () => {
    const dos = ctx({ "task-list": [{ id: 1, name: "Casa" }, { id: 2, name: "Compra" }] }, { "task/detail": { id: 5, title: "Pan" } });
    assertEquals(valor(await prepararCrearTarea({ titulo: "Pan" }, dos)), { falta: ["lista"], opciones: [{ id: 1, nombre: "Casa" }, { id: 2, nombre: "Compra" }] });
    const p = await prepararCrearTarea({ titulo: "Pan", lista_id: 2, vence: "2026-11-27" }, dos);
    assertEquals(accion(p).args, { task_list_id: 2, title: "Pan", due_at: "2026-11-27 22:59:00" });
    assertEquals(accion(await prepararCompletarTarea({ id: 5 }, dos)).args, { id: 5, completed: true });
    assertEquals(accion(await prepararCompletarTarea({ id: 5, completada: false }, dos)).args, { id: 5, completed: false });
});

Deno.test("tareas: editar rellena el título y conserva lo demás", async () => {
    const c = ctx({}, { "task/detail": { id: 5, title: "Llamar", priority: "media" } });
    assertEquals(accion(await prepararEditarTarea({ id: 5, prioridad: "baja" }, c)).args, { id: 5, title: "Llamar", priority: "baja" });
    assertEquals(valor(await prepararEditarTarea({ id: 5 }, c)), { falta: ["qué cambiar"] });
});

Deno.test("eventos: editar conserva la alarma y la hora; alta con calendario único", async () => {
    const c = ctx({ calendar: [{ id: 10, name: "Familia" }] }, { "event/detail": { id: 6, title: "Cena", date_at: "2026-12-01 20:30:00", alarm: 15 } });
    assertEquals(accion(await prepararEditarEvento({ id: 6, inicio: "2026-12-03" }, c)).args, {
        id: 6, title: "Cena", date_at: "2026-12-03 20:30:00", alarm: 15,
    });
    assertEquals(accion(await prepararCrearEvento({ titulo: "Cena", inicio: "2026-12-01 20:30" }, c)).args, {
        calendar_id: 10, title: "Cena", date_at: "2026-12-01 20:30:00",
    });
    assertEquals(valor(await prepararCrearEvento({ titulo: "Cena", inicio: "2026-12-01" }, c)), { falta: ["inicio (fecha y hora)"] });
});

Deno.test("rutinas: semanal exige días; editar reconstruye el objeto completo y hasta vacío = no termina", async () => {
    const rutina = { id: 7, title: "Regar", frequency: "weekly", interval: 2, days: [1, 3], time: "08:30:00", start_date: "2026-11-01", end_date: "2027-01-01", active: true };
    const c = ctx({ calendar: [{ id: 10, name: "Familia" }] }, { "routine/detail": rutina });
    assertEquals(valor(await prepararCrearRutina({ titulo: "R", hora: "08:00", frecuencia: "semanal" }, c)), { falta: ["días"] });
    assertEquals(accion(await prepararEditarRutina({ id: 7, hasta: "" }, c)).args, {
        id: 7, title: "Regar", frequency: "weekly", interval: 2, days: [1, 3], time: "08:30", start_date: "2026-11-01", end_date: null, active: true,
    });
    assert(!("person_ids" in accion(await prepararEditarRutina({ id: 7, hora: "09:00" }, c)).args), "no se mandan personas: el api las conserva");
});

Deno.test("calendarios: sin con quién → falta; sin cuenta → error sin crear; la propia persona no se comparte", async () => {
    const personas = [
        { id: 20, name: "Lucía", app_user_id: 502, home_id: 7 }, { id: 21, name: "Pedro", app_user_id: null, home_id: 7 },
        { id: 22, name: "Yo", app_user_id: 501, home_id: 7 },
    ];
    const c = ctx({ person: personas, calendar: [{ id: 10, name: "Familia", color: "#aa0000", widget: 1, dashboard: 0 }] });
    assertEquals(valor(await prepararCrearCalendario({ nombre: "F" }, c)), { falta: ["con quién se comparte (o solo para ti)"] });
    const sin = valor(await prepararCrearCalendario({ nombre: "F", compartir_con: [{ persona_id: 21 }] }, c)) as { sin_cuenta: string[] };
    assertEquals(sin.sin_cuenta, ["Pedro"]);
    const ok = accion(await prepararCrearCalendario({ nombre: "F", compartir_con: [{ persona_id: 20, puede_editar: true }, { persona_id: 22 }] }, c));
    assertEquals(ok.args, { name: "F", color: "#6923E2", compartir: [{ user_id: 502, can_edit: true, nombre: "Lucía" }] });
    assertEquals(accion(await prepararEditarCalendario({ id: 10, color: "#FFFFFF" }, c)).args, {
        id: 10, name: "Familia", color: "#FFFFFF", widget: true, dashboard: false,
    });
    assertEquals(personaConCuenta(personas, "7", 22, "501"), { propia: true });
    assertEquals(personaConCuenta(personas, "7", 99, "501"), { error: "Esa persona ya no existe en el hogar." });
});
