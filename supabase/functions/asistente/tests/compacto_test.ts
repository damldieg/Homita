// Tests de los compactadores de salida de `consulta`: forma exacta, tope 50 y errores del api.
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
    comoLista, compactarCalendario, compactarEvento, compactarLista, compactarOcurrencia, compactarPersona,
    compactarRutina, compactarTarea, errorCompacto, MAX_ITEMS, nombre, paquete,
} from "../skills/consulta/compacto.ts";
import { resultadoTexto } from "../core.ts";

const TZ = "Europe/Madrid";

Deno.test("evento compacto: forma exacta con ISO local", () => {
    const e = {
        id: 5, calendar_id: 1, routine_id: null, title: "Dentista", date_at: "2026-11-24 18:30:00", end_date: null,
        calendar_name: "Familia", calendar_color: "#fff", alarm: null, persons: [{ id: 3, user_id: 9, name: "Ana", color: "x" }],
        created_at: "x", updated_at: "y",
    };
    assertEquals(compactarEvento(e, TZ), {
        tipo: "evento", id: 5, titulo: "Dentista", inicio: "2026-11-24T18:30:00+01:00", fin: null, calendario: "Familia", personas: ["Ana"],
    });
});

Deno.test("ocurrencia de rutina: tipo rutina, rutina_id y sin asignar", () => {
    const o = { id: 77, routine_id: 4, title: "Sacar al perro", date_at: "2026-11-25 08:00:00", persons: [] };
    assertEquals(compactarOcurrencia(o, TZ), {
        tipo: "rutina", rutina_id: 4, titulo: "Sacar al perro", inicio: "2026-11-25T08:00:00+01:00", asignada_a: "sin asignar",
    });
});

Deno.test("definición de rutina compacta", () => {
    const r = {
        id: 4, title: "Perro", days: [1, "3"], time: "08:00:00", frequency: "weekly", interval: 2, active: true,
        calendar_name: "Casa", persons: [{ id: 1, name: "Leo" }],
    };
    assertEquals(compactarRutina(r), {
        tipo: "rutina", id: 4, titulo: "Perro", hora: "08:00", frecuencia: "semanal (cada 2)", dias: ["lunes", "miércoles"],
        calendario: "Casa", asignada_a: ["Leo"], activa: true,
    });
});

Deno.test("tarea compacta: vence desde due_at UTC y completada", () => {
    const t = { id: 1, title: "Leche", task_list_name: "Compra", priority: "alta", due_at: "2026-11-23 23:00:00", completed_at: null, persons: [] };
    assertEquals(compactarTarea(t, TZ), {
        id: 1, titulo: "Leche", lista: "Compra", completada: false, prioridad: "alta", vence: "2026-11-24T00:00:00+01:00", personas: [],
    });
    assertEquals(compactarTarea({ ...t, completed_at: "2026-11-20 10:00:00" }, TZ).completada, true);
});

Deno.test("listas, personas y calendarios compactos", () => {
    assertEquals(compactarLista({ id: 2, name: "Compra", pending_task_count: 3, token: "x" }), { id: 2, nombre: "Compra", pendientes: 3 });
    assertEquals(compactarPersona({ id: 1, name: "Ana", kind: "adult", app_user_id: 8 }), { id: 1, nombre: "Ana", tipo: "adult", tiene_cuenta: true });
    assertEquals(compactarPersona({ id: 2, name: "Urki", kind: "pet", app_user_id: null }).tiene_cuenta, false);
    assertEquals(compactarCalendario({ id: 1, name: "Trabajo", can_edit: true }, ["Ana"]), {
        id: 1, nombre: "Trabajo", compartido_con: ["Ana"], puedo_editar: true,
    });
});

Deno.test("nombres truncados a 80 caracteres", () => {
    assertEquals(nombre("a".repeat(200)).length, 80);
    assertEquals(nombre("  hola  "), "hola");
});

Deno.test("paquete: tope 50 con hay_mas", () => {
    const p = paquete(Array.from({ length: 51 }, (_, i) => i));
    assertEquals((p.elementos as number[]).length, MAX_ITEMS);
    assertEquals(p.hay_mas, true);
    assertEquals(paquete([1, 2]).hay_mas, false);
    assertEquals(paquete([1], {}, true).hay_mas, true);
});

Deno.test("error HTTP del api → objeto de error compacto, sin detalle interno", () => {
    assertEquals(comoLista({ error: 500, detalle: "SQL secreto" }), null);
    const e = errorCompacto({ error: 500, detalle: "SQL secreto" });
    assertEquals(e.codigo, 500);
    assert(!JSON.stringify(e).includes("SQL"));
});

Deno.test("resultadoTexto nunca devuelve JSON cortado", () => {
    const grande = { elementos: Array.from({ length: 50 }, () => ({ t: "x".repeat(1000) })), hay_mas: false };
    const s = resultadoTexto(grande);
    const j = JSON.parse(s);
    assert(s.length <= 20000);
    assertEquals(j.hay_mas, true);
    const raro = JSON.parse(resultadoTexto({ x: "y".repeat(30000) }));
    assertEquals(raro.error, "resultado demasiado grande");
});
