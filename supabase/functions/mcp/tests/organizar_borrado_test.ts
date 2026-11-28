// Borrado en el MCP (D2, D5, D8): sin `confirmado: true` no se escribe y se describe lo que se borraría; con él se ejecuta.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { crearMundo } from "./util.ts";
import { escrituras, fallo, llamar, LISTAS, mundo } from "./util_organizar.ts";

const BORRADOS: Array<[herramienta: string, ruta: string, texto: string]> = [
    ["borrar_lista", "task-list/delete", "la lista «Casa»"],
    ["borrar_tarea", "task/delete", "la tarea «Llamar»"],
    ["borrar_evento", "event/delete", "el evento «Cena» del 01/02 a las 20:30"],
    ["borrar_rutina", "routine/delete", "la rutina «Regar»"],
    ["borrar_calendario", "calendar/delete", "el calendario «Familia» con todos sus eventos y rutinas"],
];
const ID: Record<string, number> = { borrar_lista: 1, borrar_tarea: 5, borrar_evento: 6, borrar_rutina: 7, borrar_calendario: 10 };

Deno.test("borrar_*: sin confirmado y con confirmado:false no escriben y describen lo que se borraría", async () => {
    for (const [nombre, , texto] of BORRADOS) {
        for (const extra of [{}, { confirmado: false }]) {
            const m = mundo();
            const r = await llamar(m, nombre, { id: ID[nombre], ...extra });
            assertEquals(r.isError, false, nombre);
            assertEquals([r.datos.ejecutado, r.datos.requiere_confirmacion], [false, true], nombre);
            assertStringIncludes(String(r.datos.se_borraria), texto);
            assertEquals(escrituras(m), [], `${nombre} no debe escribir`);
            assertEquals(m.escrituras.filter((e) => e.metodo === "DELETE"), [], nombre);
        }
    }
});

Deno.test("borrar_*: con confirmado:true ejecuta el DELETE con el JWT del usuario", async () => {
    for (const [nombre, ruta] of BORRADOS) {
        const m = mundo();
        const r = await llamar(m, nombre, { id: ID[nombre], confirmado: true });
        assertEquals([r.isError, r.datos.ok, r.datos.id], [false, true, ID[nombre]], nombre);
        const [e] = escrituras(m);
        assertEquals([e.metodo, e.ruta, e.cuerpo.id, e.hogar], ["DELETE", ruta, ID[nombre], "7"], nombre);
        assertEquals(escrituras(m).length, 1);
    }
});

Deno.test("borrar_*: algo que ya no existe es éxito con ya_estaba, con o sin confirmado", async () => {
    for (const [nombre] of BORRADOS) {
        for (const extra of [{}, { confirmado: true }]) {
            const m = mundo({ "task-list": [], calendar: [] }, {
                "GET task/detail": fallo(500, "Not Found"), "GET event/detail": fallo(404, "x"), "GET routine/detail": fallo(500, "Not Found"),
            });
            const r = await llamar(m, nombre, { id: 99, ...extra });
            assertEquals([r.isError, r.datos.ok, r.datos.ya_estaba], [false, true, true], nombre);
            assertEquals(escrituras(m), []);
        }
    }
});

Deno.test("borrar_*: si el DELETE responde «Not Found» (se borró entre la lectura y el borrado) también es éxito", async () => {
    const m = mundo({}, { "DELETE task/delete": fallo(500, "Not Found") });
    const r = await llamar(m, "borrar_tarea", { id: 5, confirmado: true });
    assertEquals([r.isError, r.datos.ya_estaba], [false, true]);
});

Deno.test("borrar_lista: cuenta las tareas totales (pendientes + hechas) y cae a «todas sus tareas» si la lectura falla", async () => {
    const tareas = [{ id: 1, completed_at: null }, { id: 2, completed_at: null }, { id: 3, completed_at: "2030-01-01 10:00:00" }];
    const m = mundo({ task: tareas });
    const r = await llamar(m, "borrar_lista", { id: 1 });
    assertStringIncludes(String(r.datos.se_borraria), "la lista «Casa» y todas sus tareas: 3 (2 pendientes, 1 hechas)");
    assertEquals(m.llamadas.find((l) => l.ruta === "task")?.params, { task_list_id: "1" });
    // La lectura de tareas falla: no se inventa una cifra.
    const f = crearMundo({ "task-list": LISTAS }, {}, { task: 500 });
    const r2 = await llamar(f, "borrar_lista", { id: 1 });
    assertEquals(r2.isError, false);
    assertStringIncludes(String(r2.datos.se_borraria), "la lista «Casa» y todas sus tareas (al menos 3 pendientes)");
    assert(!/\d+ \(/.test(String(r2.datos.se_borraria)));
    // Forma inesperada: tampoco.
    const g = mundo({ task: { raro: true } });
    assertStringIncludes(String((await llamar(g, "borrar_lista", { id: 2 })).datos.se_borraria), "la lista «Compra» y todas sus tareas");
});

Deno.test("borrar_*: hogar ajeno no lee ni escribe", async () => {
    const m = mundo();
    m.miembroDe.delete("8");
    const r = await llamar(m, "borrar_lista", { id: 1, confirmado: true, hogar: "8" });
    assertEquals(r.isError, true);
    assertEquals(m.escrituras, []);
});
