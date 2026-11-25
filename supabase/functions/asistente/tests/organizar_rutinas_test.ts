// Herramientas de rutinas: faltas, valores por defecto (hoy y activa) y ediciones que conservan lo no cambiado.
import { assertEquals } from "jsr:@std/assert@1";
import { HERRAMIENTAS_RUTINAS } from "../skills/organizar/rutinas.ts";
import { ctxDe, escritorFalso, lectorFalso, ok, SECRETO } from "./organizar_util.ts";

const [crear, editar, borrar] = HERRAMIENTAS_RUTINAS;
const RUTINA = {
    id: 30, calendar_id: 1, title: "Sacar al perro", days: [1, 3, 5], time: "08:00:00", start_date: "2026-10-01",
    end_date: "2026-12-31", active: true, frequency: "weekly", interval: 1,
};
const montar = (resp = {}) => {
    const e = escritorFalso({ "GET routine/detail": ok(RUTINA), ...resp });
    const ctx = ctxDe({
        escribir: e.escribir, leer: lectorFalso({ calendar: [{ id: 1, name: "Familia", can_edit: true }] }),
        secretoConfirmacion: SECRETO, turno: { escrituras: 1 },
    });
    return { ...e, ctx };
};
const efectos = (r: unknown) => (r as Record<symbol, { tarjeta: Record<string, unknown> }>)[Object.getOwnPropertySymbols(r as object)[0]];

Deno.test("crear_rutina semanal sin días → falta días y ninguna llamada", async () => {
    const { ctx, llamadas } = montar();
    assertEquals(await crear.run({ titulo: "Pasear", hora: "08:00", frecuencia: "semanal" }, ctx), { falta: ["días"] });
    assertEquals(llamadas.length, 0);
});

Deno.test("crear_rutina: start_date = hoy y active = true por defecto, y lo declara al modelo", async () => {
    const { ctx, llamadas } = montar({ "POST routine/create": ok({ id: 31 }) });
    const r = await crear.run({ titulo: "Pasear", hora: "08:00", frecuencia: "semanal", dias: [5, 1] }, ctx) as { valor: Record<string, unknown> };
    assertEquals(llamadas[0].ruta, "routine/create");
    assertEquals(llamadas[0].cuerpo, {
        calendar_id: 1, title: "Pasear", frequency: "weekly", interval: 1, days: [1, 5], time: "08:00", start_date: "2026-11-25", active: true,
    });
    assertEquals([r.valor.empieza, r.valor.activa], ["2026-11-25", true]);
});

Deno.test("crear_rutina diaria ignora los días; hora inválida o ausente → falta", async () => {
    const { ctx, llamadas } = montar();
    await crear.run({ titulo: "Vitamina", hora: "09:30", frecuencia: "diaria", dias: [1], desde: "2026-12-01" }, ctx);
    assertEquals([llamadas[0].cuerpo.days, llamadas[0].cuerpo.start_date], [[], "2026-12-01"]);
    assertEquals(await crear.run({ titulo: "X", hora: "25:00", frecuencia: "diaria" }, ctx), { falta: ["hora"] });
    assertEquals(await crear.run({ titulo: "X", hora: "08:00" }, ctx), { falta: ["frecuencia"] });
});

Deno.test("editar_rutina: conserva end_date, active, start_date y los días", async () => {
    const { ctx, llamadas } = montar();
    await editar.run({ id: 30, hora: "07:30" }, ctx);
    const patch = llamadas.find((l) => l.metodo === "PATCH")!;
    assertEquals(patch.cuerpo, {
        id: 30, title: "Sacar al perro", frequency: "weekly", interval: 1, days: [1, 3, 5], time: "07:30",
        start_date: "2026-10-01", end_date: "2026-12-31", active: true,
    });
});

Deno.test("editar_rutina: hasta vacío quita el fin; pausar; pasar a semanal sin días → falta", async () => {
    const { ctx, llamadas } = montar();
    await editar.run({ id: 30, hasta: "", activa: false }, ctx);
    assertEquals([llamadas.at(-1)!.cuerpo.end_date, llamadas.at(-1)!.cuerpo.active], [null, false]);
    const m = montar({ "GET routine/detail": ok({ ...RUTINA, frequency: "daily", days: [] }) });
    assertEquals(await editar.run({ id: 30, frecuencia: "semanal" }, m.ctx), { falta: ["días"] });
});

Deno.test("borrar_rutina: tarjeta sin llamada de borrado", async () => {
    const { ctx, llamadas } = montar();
    const r = await borrar.run({ id: 30 }, ctx);
    assertEquals(llamadas.filter((l) => l.metodo === "DELETE").length, 0);
    assertEquals(efectos(r).tarjeta.texto, "¿Borro la rutina «Sacar al perro»?");
});
