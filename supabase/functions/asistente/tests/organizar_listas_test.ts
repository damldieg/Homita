// Herramientas de listas: llamada exacta al caso de uso, faltas, edición que rellena y borrado con tarjeta.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { HERRAMIENTAS_LISTAS } from "../skills/organizar/listas.ts";
import { ctxDe, escritorFalso, fallo, lectorFalso, ok, SECRETO } from "./organizar_util.ts";

const [crear, editar, borrar] = HERRAMIENTAS_LISTAS;
const LISTAS = [
    { id: 3, name: "Pruebas", color: "#112233", sort: "title", widget: 0, dashboard: 1, pending_task_count: 4, can_edit: true },
    { id: 4, name: "Compra", color: "#445566", sort: "updated_at", widget: 1, dashboard: 1, pending_task_count: 0, can_edit: true },
];
const montar = (resp = {}) => {
    const e = escritorFalso(resp);
    const ctx = ctxDe({ escribir: e.escribir, leer: lectorFalso({ "task-list": LISTAS }), secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    return { ...e, ctx };
};
const valor = (r: unknown) => (r as { valor: Record<string, unknown> }).valor ?? r as Record<string, unknown>;

Deno.test("crear_lista: llamada exacta, color por defecto y client_request_id derivado", async () => {
    const { ctx, llamadas } = montar({ "POST task-list/create": ok({ id: 9 }, 201) });
    const r = await crear.run({ nombre: "  Viaje " }, ctx, { toolUseId: "toolu_1" });
    assertEquals(llamadas.length, 1);
    const c = llamadas[0];
    assertEquals([c.metodo, c.ruta], ["POST", "task-list/create"]);
    assertEquals([c.cuerpo.name, c.cuerpo.color], ["Viaje", "#6923E2"]);
    assert(/^[0-9a-f-]{36}$/.test(String(c.cuerpo.client_request_id)));
    assertEquals(valor(r).id, 9);
});

Deno.test("crear_lista: sin nombre → falta sin llamar; color inválido → error", async () => {
    const { ctx, llamadas } = montar();
    assertEquals(await crear.run({}, ctx), { falta: ["nombre"] });
    assertEquals((await crear.run({ nombre: "X", color: "rojo" }, ctx) as { ok: boolean }).ok, false);
    assertEquals(llamadas.length, 0);
});

Deno.test("editar_lista: rellena color, orden, widget y dashboard con lo actual", async () => {
    const { ctx, llamadas } = montar();
    await editar.run({ id: 3, nombre: "Pruebas 2" }, ctx);
    assertEquals(llamadas[0].cuerpo, { id: 3, name: "Pruebas 2", color: "#112233", sort: "title", widget: false, dashboard: true });
    assertEquals(llamadas[0].ruta, "task-list/update");
});

Deno.test("editar_lista: sin cambios → falta; lista inexistente → «Ya no existe.»", async () => {
    const { ctx, llamadas } = montar();
    assertEquals(await editar.run({ id: 3 }, ctx), { falta: ["qué cambiar"] });
    assertEquals(await editar.run({ id: 99, nombre: "X" }, ctx), { ok: false, error: "Ya no existe." });
    assertEquals(llamadas.length, 0);
});

Deno.test("editar_lista: el 403 de un lector se traduce con el nombre", async () => {
    const { ctx } = montar({ "PATCH task-list/update": fallo(403, "Not Allowed") });
    assertEquals(await editar.run({ id: 3, color: "#ffffff" }, ctx), { ok: false, error: "No tienes permiso de edición en «Pruebas»." });
});

Deno.test("borrar_lista: no llama al api y deja tarjeta «¿Borro la lista…?»", async () => {
    const { ctx, llamadas } = montar();
    const r = await borrar.run({ id: 3 }, ctx) as { valor: Record<string, unknown> };
    assertEquals(llamadas.length, 0);
    assertEquals(r.valor.estado, "propuesta enviada al usuario para confirmar");
    const efectos = (r as unknown as Record<symbol, { tarjeta: Record<string, unknown> }>)[Object.getOwnPropertySymbols(r)[0]];
    assertEquals(efectos.tarjeta.texto, "¿Borro la lista «Pruebas» y sus tareas (4 pendientes)?");
    assertEquals(efectos.tarjeta.acciones, [{ op: "borrar_lista", args: { id: 3 }, nombre: "Pruebas" }]);
});

Deno.test("borrar_lista: lista vacía y lista que ya no existe", async () => {
    const { ctx } = montar();
    const r = await borrar.run({ id: 4 }, ctx);
    const efectos = (r as Record<symbol, { tarjeta: Record<string, unknown> }>)[Object.getOwnPropertySymbols(r as object)[0]];
    assertEquals(efectos.tarjeta.texto, "¿Borro la lista «Compra»?");
    assertEquals(await borrar.run({ id: 77 }, ctx), { ok: false, error: "Ya no existe." });
});
