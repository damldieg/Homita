// Lógica de decisión de las escrituras: ejecutar al momento, dejar pendiente de confirmar, o negar.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { despachar, NO_PUEDO_BORRAR, NO_PUEDO_VARIOS, PROPUESTA } from "../skills/organizar/base.ts";
import { verificar } from "../skills/organizar/confirmacion.ts";
import { ctxDe, escritorFalso, fallo, ok, SECRETO } from "./organizar_util.ts";

// `conEfectos` marca el objeto con un Symbol: se lee con su descriptor público (valor).
const valorDe = (r: unknown) => (r as { valor: Record<string, unknown> }).valor;
const efectosDe = (r: unknown) => Object.getOwnPropertySymbols(r as object).map((s) => (r as Record<symbol, unknown>)[s])[0] as {
    tarjeta?: Record<string, unknown>;
    cambios?: unknown[];
};

const borrar = { op: "borrar_lista", args: { id: 3 }, nombre: "Pruebas" };
const crear = { op: "crear_tarea", args: { task_list_id: 1, title: "Pan" }, nombre: "Pan" };
const editar = { op: "editar_lista", args: { id: 3, name: "X" }, nombre: "X" };

Deno.test("una alta única se ejecuta al momento y devuelve cambios", async () => {
    const { escribir, llamadas } = escritorFalso({ "POST task/create": ok({ id: 9 }, 201) });
    const r = await despachar(ctxDe({ escribir, secretoConfirmacion: SECRETO, turno: { escrituras: 1 } }), crear);
    assertEquals(llamadas.length, 1);
    assertEquals(valorDe(r).ok, true);
    assertEquals(efectosDe(r).cambios, [{ tipo: "tarea", id: 9, op: "crear" }]);
});

Deno.test("borrar nunca se ejecuta: deja tarjeta con token verificable y sin llamada", async () => {
    const { escribir, llamadas } = escritorFalso();
    const ctx = ctxDe({ escribir, secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    const r = await despachar(ctx, borrar, { frase: "Borro la lista «Pruebas»" });
    assertEquals(llamadas.length, 0);
    assertEquals(valorDe(r).estado, PROPUESTA);
    const t = efectosDe(r).tarjeta!;
    assertEquals([t.tipo, t.id, t.texto], ["confirmacion", "confirmacion", "¿Borro la lista «Pruebas»?"]);
    assert(typeof t.caduca === "string");
    const v = await verificar(t.token, SECRETO, { uid: "uid-1", homeId: "7", ahora: ctx.now.getTime() });
    assert(v.ok);
    if (v.ok) assertEquals(v.payload.acciones, [borrar]);
});

Deno.test("sin secreto: borrar se niega sin llamar; las altas siguen", async () => {
    const { escribir, llamadas } = escritorFalso();
    const ctx = ctxDe({ escribir, turno: { escrituras: 1 } });
    assertEquals(await despachar(ctx, borrar), { ok: false, error: NO_PUEDO_BORRAR });
    assertEquals(llamadas.length, 0);
    const r = await despachar(ctx, crear);
    assertEquals(valorDe(r).ok, true);
    assertEquals(llamadas.length, 1);
});

Deno.test("dos escrituras en la vuelta: no se llama al api y queda una sola tarjeta con las dos", async () => {
    const { escribir, llamadas } = escritorFalso();
    const ctx = ctxDe({ escribir, secretoConfirmacion: SECRETO, turno: { escrituras: 2 } });
    const [a, b] = await Promise.all([despachar(ctx, crear), despachar(ctx, editar)]);
    assertEquals(llamadas.length, 0);
    assert(efectosDe(a).tarjeta === efectosDe(b).tarjeta, "misma tarjeta");
    const t = efectosDe(b).tarjeta!;
    assertEquals((t.acciones as unknown[]).length, 2);
    assert(String(t.texto).startsWith("Esto es lo que haría:"));
});

Deno.test("tras ejecutar una escritura, la siguiente de la petición queda pendiente", async () => {
    const { escribir, llamadas } = escritorFalso();
    const ctx = ctxDe({ escribir, secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    await despachar(ctx, crear);
    const r = await despachar(ctx, editar);
    assertEquals(llamadas.length, 1);
    assertEquals(valorDe(r).estado, PROPUESTA);
});

Deno.test("sin secreto y varias escrituras: las altas siguen, las ediciones se niegan", async () => {
    const { escribir, llamadas } = escritorFalso();
    const ctx = ctxDe({ escribir, turno: { escrituras: 2 } });
    assertEquals(valorDe(await despachar(ctx, crear)).ok, true);
    assertEquals(await despachar(ctx, editar), { ok: false, error: NO_PUEDO_VARIOS });
    assertEquals(llamadas.length, 1);
});

Deno.test("errores del api traducidos y sin cambios; no cuenta como ejecutada", async () => {
    const { escribir } = escritorFalso({ "PATCH task-list/update": fallo(403, "Not Allowed") });
    const ctx = ctxDe({ escribir, secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    assertEquals(await despachar(ctx, editar), { ok: false, error: "No tienes permiso de edición en «X»." });
    // Como no se ejecutó nada, la siguiente sigue siendo «única».
    assertEquals(valorDe(await despachar(ctx, crear)).ok, true);
});
