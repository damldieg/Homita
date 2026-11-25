// Herramientas de calendarios: con quién se comparte, permisos y fallos de compartir por separado.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { HERRAMIENTAS_CALENDARIOS } from "../skills/organizar/calendarios.ts";
import { ctxDe, escritorFalso, fallo, lectorFalso, ok, SECRETO } from "./organizar_util.ts";

const [crear, editar, borrar] = HERRAMIENTAS_CALENDARIOS;
const PERSONAS = [
    { id: 10, name: "Damián", app_user_id: 501, home_id: 7 },
    { id: 11, name: "Lucía", app_user_id: 502, home_id: 7 },
    { id: 12, name: "Marcos", app_user_id: 503, home_id: 7 },
    { id: 13, name: "Urki", app_user_id: null, home_id: 7 },
    { id: 14, name: "De otro hogar", app_user_id: 504, home_id: 9 },
];
const CAL = { id: 5, name: "Familia", color: "#102030", widget: 1, dashboard: 0, can_edit: true, upcoming_event_count: 3 };

const montar = (resp = {}) => {
    const e = escritorFalso({ "POST calendar/create": ok({ id: 40 }, 201), ...resp });
    const ctx = ctxDe({ escribir: e.escribir, leer: lectorFalso({ person: PERSONAS, calendar: [CAL] }), secretoConfirmacion: SECRETO, turno: { escrituras: 1 } });
    return { ...e, ctx };
};
const valor = (r: unknown) => (r as { valor?: Record<string, unknown> }).valor ?? r as Record<string, unknown>;
const efectos = (r: unknown) => (r as Record<symbol, { tarjeta: Record<string, unknown> }>)[Object.getOwnPropertySymbols(r as object)[0]];

Deno.test("crear_calendario sin «con quién» → falta, sin llamar", async () => {
    const { ctx, llamadas } = montar();
    assertEquals(await crear.run({ nombre: "Fútbol" }, ctx), { falta: ["con quién se comparte (o solo para ti)"] });
    assertEquals(await crear.run({}, ctx), { falta: ["nombre", "con quién se comparte (o solo para ti)"] });
    assertEquals(llamadas.length, 0);
});

Deno.test("crear_calendario «solo conmigo»: crea con color por defecto y sin miembros", async () => {
    const { ctx, llamadas } = montar();
    const r = await crear.run({ nombre: "Fútbol", solo_yo: true }, ctx);
    assertEquals(llamadas.length, 1);
    assertEquals(llamadas[0].cuerpo, { name: "Fútbol", color: "#6923E2" });
    assertEquals(valor(r).compartido_con, "solo contigo");
});

Deno.test("crear_calendario compartido: lectura por defecto y PATCH con can_edit solo según lo pedido", async () => {
    const { ctx, llamadas } = montar();
    const r = await crear.run({ nombre: "Fútbol", compartir_con: [{ persona_id: 11 }, { persona_id: 12, puede_editar: true }, { persona_id: 10 }] }, ctx);
    assertEquals(llamadas.map((l) => `${l.metodo} ${l.ruta}`), ["POST calendar/create", "PATCH calendar/user", "PATCH calendar/user"]);
    assertEquals(llamadas[1].cuerpo, { calendar_id: 40, user_id: 502, can_edit: false });
    assertEquals(llamadas[2].cuerpo, { calendar_id: 40, user_id: 503, can_edit: true });
    assertEquals(valor(r).compartido_con, ["Lucía (solo lectura)", "Marcos (puede editar)"]);
});

Deno.test("crear_calendario: persona sin cuenta → no se crea nada y se explica", async () => {
    const { ctx, llamadas } = montar();
    const r = valor(await crear.run({ nombre: "Fútbol", compartir_con: [{ persona_id: 11 }, { persona_id: 13 }] }, ctx));
    assertEquals(llamadas.length, 0);
    assertEquals(r.sin_cuenta, ["Urki"]);
    assert(String(r.error).includes("no tiene cuenta en Homita"));
});

Deno.test("crear_calendario: persona de otro hogar o inexistente → error", async () => {
    const { ctx, llamadas } = montar();
    assertEquals(valor(await crear.run({ nombre: "X", compartir_con: [{ persona_id: 14 }] }, ctx)).ok, false);
    assertEquals(llamadas.length, 0);
});

Deno.test("crear_calendario: el calendario creado y el fallo de compartir se reportan por separado", async () => {
    const { ctx } = montar({ "PATCH calendar/user": fallo(403, "Not Allowed") });
    const r = valor(await crear.run({ nombre: "Fútbol", compartir_con: [{ persona_id: 11 }] }, ctx));
    assertEquals(r.ok, true);
    assertEquals(r.id, 40);
    assert((r.avisos as string[])[0].startsWith("No he podido compartirlo con Lucía"));
});

Deno.test("crear_calendario: 403 al crear se traduce con el nombre", async () => {
    const { ctx } = montar({ "POST calendar/create": fallo(403, "Not Allowed") });
    assertEquals(valor(await crear.run({ nombre: "Fútbol", solo_yo: true }, ctx)), { ok: false, error: "No tienes permiso de edición en «Fútbol»." });
});

Deno.test("editar_calendario: rellena color, widget y dashboard", async () => {
    const { ctx, llamadas } = montar();
    await editar.run({ id: 5, nombre: "Familia 2" }, ctx);
    assertEquals(llamadas[0].cuerpo, { id: 5, name: "Familia 2", color: "#102030", widget: true, dashboard: false });
    assertEquals(await editar.run({ id: 5 }, ctx), { falta: ["qué cambiar"] });
});

Deno.test("borrar_calendario: tarjeta sin llamada de borrado", async () => {
    const { ctx, llamadas } = montar();
    const r = await borrar.run({ id: 5 }, ctx);
    assertEquals(llamadas.length, 0);
    assertEquals(efectos(r).tarjeta.texto, "¿Borro el calendario «Familia» con todos sus eventos y rutinas?");
});
