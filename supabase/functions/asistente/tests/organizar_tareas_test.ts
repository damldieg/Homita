// Herramientas de tareas: lista obligatoria, idempotencia, completar y borrar.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { HERRAMIENTAS_TAREAS } from "../skills/organizar/tareas.ts";
import { ctxDe, escritorFalso, lectorFalso, ok, SECRETO } from "./organizar_util.ts";

const [crear, editar, completar, borrar] = HERRAMIENTAS_TAREAS;
const LISTA = (id: number, name: string, extra = {}) => ({ id, name, can_edit: true, ...extra });

const montar = (listas: unknown[], resp = {}) => {
    const e = escritorFalso({ "GET task/detail": ok({ id: 5, title: "Llamar", task_list_id: 1 }), ...resp });
    const ctx = ctxDe({ escribir: e.escribir, leer: lectorFalso({ "task-list": listas }), secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    return { ...e, ctx };
};
const valor = (r: unknown) => (r as { valor?: Record<string, unknown> }).valor ?? r as Record<string, unknown>;
const efectos = (r: unknown) => (r as Record<symbol, { tarjeta: Record<string, unknown> }>)[Object.getOwnPropertySymbols(r as object)[0]];

Deno.test("crear_tarea: varias listas y sin lista → falta con opciones, sin llamar", async () => {
    const { ctx, llamadas } = montar([LISTA(1, "Casa"), LISTA(2, "Compra")]);
    const r = await crear.run({ titulo: "Comprar pan" }, ctx, { toolUseId: "t1" }) as Record<string, unknown>;
    assertEquals(r.falta, ["lista"]);
    assertEquals(r.opciones, [{ id: 1, nombre: "Casa" }, { id: 2, nombre: "Compra" }]);
    assertEquals(llamadas.length, 0);
});

Deno.test("crear_tarea: sin título ni lista → una sola pregunta con las dos faltas", async () => {
    const { ctx } = montar([LISTA(1, "Casa"), LISTA(2, "Compra")]);
    assertEquals((await crear.run({}, ctx) as Record<string, unknown>).falta, ["titulo", "lista"]);
});

Deno.test("crear_tarea: una sola lista → crea con la llamada correcta", async () => {
    const { ctx, llamadas } = montar([LISTA(2, "Compra")], { "POST task/create": ok({ id: 8 }, 201) });
    const r = await crear.run({ titulo: " Comprar pan ", prioridad: "alta", persona_ids: [3, 3, 4] }, ctx, { toolUseId: "t1" });
    assertEquals(llamadas.length, 1);
    const c = llamadas[0];
    assertEquals([c.metodo, c.ruta], ["POST", "task/create"]);
    assertEquals({ ...c.cuerpo, client_request_id: undefined }, { task_list_id: 2, title: "Comprar pan", priority: "alta", person_ids: [3, 4], client_request_id: undefined });
    assertEquals(valor(r).lista, "Compra");
});

Deno.test("crear_tarea: con vence, crea y fija la fecha límite en UTC (hora local de Madrid)", async () => {
    const { ctx, llamadas } = montar([LISTA(1, "Casa")], { "POST task/create": ok({ id: 8 }, 201) });
    await crear.run({ titulo: "Llamar al dentista", lista_id: 1, vence: "2026-11-27" }, ctx, { toolUseId: "t1" });
    assertEquals(llamadas.map((l) => `${l.metodo} ${l.ruta}`), ["POST task/create", "PATCH task/update"]);
    assert(!("due_at" in llamadas[0].cuerpo));
    assertEquals(llamadas[1].cuerpo, { id: 8, title: "Llamar al dentista", due_at: "2026-11-27 22:59:00" });
});

Deno.test("crear_tarea: reintento con el mismo tool_use.id envía el mismo client_request_id", async () => {
    const { ctx, llamadas } = montar([LISTA(1, "Casa")]);
    await crear.run({ titulo: "A" }, ctx, { toolUseId: "toolu_X" });
    const ctx2 = ctxDe({ escribir: escritorFalso().escribir, leer: ctx.leer, secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    const otra = escritorFalso();
    ctx2.escribir = otra.escribir;
    await crear.run({ titulo: "A" }, ctx2, { toolUseId: "toolu_X" });
    await crear.run({ titulo: "A" }, ctxDe({ escribir: otra.escribir, leer: ctx.leer, turno: { escrituras: 1 } }), { toolUseId: "toolu_Y" });
    assertEquals(llamadas[0].cuerpo.client_request_id, otra.llamadas[0].cuerpo.client_request_id);
    assert(otra.llamadas[1].cuerpo.client_request_id !== otra.llamadas[0].cuerpo.client_request_id);
});

Deno.test("crear_tarea: prioridad y fecha inválidas son errores sin llamada", async () => {
    const { ctx, llamadas } = montar([LISTA(1, "Casa")]);
    assertEquals((await crear.run({ titulo: "A", prioridad: "urgente" }, ctx) as { ok: boolean }).ok, false);
    assertEquals((await crear.run({ titulo: "A", vence: "el viernes" }, ctx) as { ok: boolean }).ok, false);
    assertEquals(llamadas.length, 0);
});

Deno.test("completar_tarea: completa y descompleta", async () => {
    const { ctx, llamadas } = montar([]);
    await completar.run({ id: 5 }, ctx);
    assertEquals(llamadas.at(-1)!.cuerpo, { id: 5, completed: true });
    const m2 = montar([]);
    await completar.run({ id: 5, completada: false }, m2.ctx);
    assertEquals(m2.llamadas.at(-1)!.cuerpo, { id: 5, completed: false });
    assertEquals(m2.llamadas.at(-1)!.ruta, "task/complete");
});

Deno.test("editar_tarea: rellena el título y solo manda lo que cambia", async () => {
    const { ctx, llamadas } = montar([]);
    await editar.run({ id: 5, prioridad: "baja" }, ctx);
    assertEquals(llamadas.at(-1)!.cuerpo, { id: 5, title: "Llamar", priority: "baja" });
    assertEquals(await editar.run({ id: 5 }, ctx), { falta: ["qué cambiar"] });
});

Deno.test("borrar_tarea: tarjeta sin llamada de borrado; tarea inexistente → «Ya no existe.»", async () => {
    const { ctx, llamadas } = montar([]);
    const r = await borrar.run({ id: 5 }, ctx);
    assertEquals(llamadas.filter((l) => l.metodo === "DELETE").length, 0);
    assertEquals(efectos(r).tarjeta.texto, "¿Borro la tarea «Llamar»?");
    const m2 = montar([], { "GET task/detail": { ok: false, status: 500, data: { error: "Not Found" }, error: "Not Found" } });
    assertEquals(await borrar.run({ id: 5 }, m2.ctx), { ok: false, error: "Ya no existe." });
});
