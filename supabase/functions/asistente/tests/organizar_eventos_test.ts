// Herramientas de eventos: cuerpo exacto, alarma conservada y faltas.
import { assertEquals } from "jsr:@std/assert@1";
import { HERRAMIENTAS_EVENTOS } from "../skills/organizar/eventos.ts";
import { ctxDe, escritorFalso, lectorFalso, ok, SECRETO } from "./organizar_util.ts";

const [crear, editar, borrar] = HERRAMIENTAS_EVENTOS;
const CALS = [{ id: 1, name: "Familia", can_edit: true }, { id: 2, name: "Trabajo", can_edit: true }];
const CENA = { id: 20, calendar_id: 1, title: "Cena con los abuelos", date_at: "2026-11-26 20:30:00", end_date: null, alarm: 30 };

const montar = (cals: unknown[] = CALS, resp = {}) => {
    const e = escritorFalso({ "GET event/detail": ok(CENA), ...resp });
    const ctx = ctxDe({ escribir: e.escribir, leer: lectorFalso({ calendar: cals }), secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    return { ...e, ctx };
};
const efectos = (r: unknown) => (r as Record<symbol, { tarjeta: Record<string, unknown> }>)[Object.getOwnPropertySymbols(r as object)[0]];

Deno.test("crear_evento: cuerpo exacto al caso de uso", async () => {
    const { ctx, llamadas } = montar();
    await crear.run({ titulo: "Dentista", inicio: "2026-11-27 17:15", calendario_id: 2, alarma_min: 15, fin: "2026-11-28", persona_ids: [4] }, ctx);
    assertEquals(llamadas.length, 1);
    assertEquals([llamadas[0].metodo, llamadas[0].ruta], ["POST", "event/create"]);
    assertEquals(llamadas[0].cuerpo, {
        calendar_id: 2, title: "Dentista", date_at: "2026-11-27 17:15:00", alarm: 15, person_ids: [4], end_date: "2026-11-28",
    });
});

Deno.test("crear_evento: faltan título, hora y calendario → una sola lista y ninguna llamada", async () => {
    const { ctx, llamadas } = montar();
    const r = await crear.run({ inicio: "2026-11-27" }, ctx) as Record<string, unknown>;
    assertEquals(r.falta, ["titulo", "inicio (fecha y hora)", "calendario"]);
    assertEquals((r.opciones as unknown[]).length, 2);
    assertEquals(llamadas.length, 0);
});

Deno.test("crear_evento: con un solo calendario editable se usa", async () => {
    const { ctx, llamadas } = montar([CALS[0]]);
    await crear.run({ titulo: "Cine", inicio: "2026-11-28 21:00" }, ctx);
    assertEquals(llamadas[0].cuerpo.calendar_id, 1);
});

Deno.test("editar_evento: «cambia la cena del jueves a las 21:30» rellena el resto y conserva la alarma", async () => {
    const { ctx, llamadas } = montar();
    await editar.run({ id: 20, inicio: "2026-11-26 21:30" }, ctx);
    const patch = llamadas.find((l) => l.metodo === "PATCH")!;
    assertEquals(patch.ruta, "event/update");
    assertEquals(patch.cuerpo, { id: 20, title: "Cena con los abuelos", date_at: "2026-11-26 21:30:00", alarm: 30 });
});

Deno.test("editar_evento: solo fecha conserva la hora; sin cambios → falta; fin y alarma se envían", async () => {
    const { ctx, llamadas } = montar();
    await editar.run({ id: 20, inicio: "2026-11-27", alarma_min: 0, fin: "2026-11-28" }, ctx);
    assertEquals(llamadas.at(-1)!.cuerpo, { id: 20, title: "Cena con los abuelos", date_at: "2026-11-27 20:30:00", alarm: 0, end_date: "2026-11-28" });
    assertEquals(await editar.run({ id: 20 }, ctx), { falta: ["qué cambiar"] });
});

Deno.test("borrar_evento: tarjeta con el título y sin llamada de borrado", async () => {
    const { ctx, llamadas } = montar();
    const r = await borrar.run({ id: 20 }, ctx);
    assertEquals(llamadas.filter((l) => l.metodo === "DELETE").length, 0);
    assertEquals(efectos(r).tarjeta.texto, "¿Borro el evento «Cena con los abuelos» del 26/11 a las 20:30?");
});
