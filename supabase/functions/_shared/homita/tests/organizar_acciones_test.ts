// OPS, ejecutarAccion y compartirCalendario del módulo compartido de «organizar».
import { assert, assertEquals } from "jsr:@std/assert@1";
import { compartirCalendario, ejecutarAccion, hechoDe, OPS } from "../organizar/acciones.ts";
import type { EscribirFn } from "../escritor.ts";

const escritor = (resp: Record<string, { ok: boolean; status: number; data: unknown; error?: string }> = {}) => {
    const llamadas: Array<[string, string, Record<string, unknown> | undefined]> = [];
    const esc: EscribirFn = (m, r, c) => {
        llamadas.push([m, r, c]);
        return Promise.resolve(resp[`${m} ${r}`] ?? { ok: true, status: 200, data: { id: 1 } });
    };
    return { esc, llamadas };
};

Deno.test("OPS: 16 operaciones y la misma lista blanca que el token de Kito", async () => {
    const { OPS_PERMITIDAS } = await import("../../../asistente/skills/organizar/confirmacion.ts");
    assertEquals(Object.keys(OPS).length, 16);
    assertEquals([...OPS_PERMITIDAS].sort(), Object.keys(OPS).sort());
    assert(!("compartir_calendario" in OPS), "compartir no es una operación de OPS");
});

Deno.test("ejecutarAccion: éxito, id, cambios y texto", async () => {
    const { esc, llamadas } = escritor({ "POST task-list/create": { ok: true, status: 201, data: { id: 9 } } });
    const r = await ejecutarAccion(esc, { op: "crear_lista", args: { name: "Viaje", color: "#6923E2" } });
    assertEquals(r, { ok: true, id: 9, cambios: [{ tipo: "lista", id: 9, op: "crear" }], texto: "Creada la lista «Viaje»", avisos: [] });
    assertEquals(llamadas, [["POST", "task-list/create", { name: "Viaje", color: "#6923E2" }]]);
    assertEquals(hechoDe({ op: "completar_tarea", args: { id: 1, completed: false }, nombre: "Pan" }), "Tarea «Pan» marcada como pendiente");
});

Deno.test("ejecutarAccion: borrar algo que ya no existe es éxito (yaEstaba); otros errores no", async () => {
    const nf = escritor({ "DELETE task/delete": { ok: false, status: 500, data: null, error: "Not Found" } });
    const r = await ejecutarAccion(nf.esc, { op: "borrar_tarea", args: { id: 5 }, nombre: "Pan" });
    assertEquals([r.ok, r.yaEstaba, r.id, r.cambios], [true, true, 5, []]);
    assertEquals(r.texto, "Ya estaba hecho: la tarea «Pan» ya no existe");
    const f = escritor({ "DELETE task/delete": { ok: false, status: 403, data: null, error: "x" } });
    const r2 = await ejecutarAccion(f.esc, { op: "borrar_tarea", args: { id: 5 }, nombre: "Pan" });
    assertEquals([r2.ok, r2.texto], [false, "No tienes permiso de edición en «Pan»."]);
    assertEquals((await ejecutarAccion(f.esc, { op: "nada", args: {} })).texto, "Acción no permitida.");
});

Deno.test("ejecutarAccion: crear_tarea con due_at hace un segundo PATCH y su fallo es un aviso", async () => {
    const { esc, llamadas } = escritor({ "POST task/create": { ok: true, status: 201, data: { id: 8 } }, "PATCH task/update": { ok: false, status: 400, data: null, error: "mal" } });
    const r = await ejecutarAccion(esc, { op: "crear_tarea", args: { task_list_id: 1, title: "T", due_at: "2026-11-27 22:59:00" } });
    assertEquals(llamadas[0], ["POST", "task/create", { task_list_id: 1, title: "T" }]);
    assertEquals(llamadas[1], ["PATCH", "task/update", { id: 8, title: "T", due_at: "2026-11-27 22:59:00" }]);
    assertEquals([r.ok, r.avisos], [true, ["La tarea está creada, pero no he podido ponerle la fecha límite: No se ha podido hacer: mal."]]);
});

Deno.test("compartirCalendario: éxito, 403 con la frase del propietario y otro error traducido", async () => {
    const ok = escritor();
    assertEquals(await compartirCalendario(ok.esc, 4, 502, true, "Lucía"), { ok: true });
    assertEquals(ok.llamadas, [["PATCH", "calendar/user", { calendar_id: 4, user_id: 502, can_edit: true }]]);
    const f403 = escritor({ "PATCH calendar/user": { ok: false, status: 403, data: null, error: "Not Allowed" } });
    assertEquals(await compartirCalendario(f403.esc, 4, 502, false, "Lucía"), {
        ok: false, status: 403, texto: "No he podido compartirlo con Lucía: solo el propietario puede compartir, y esa persona debe ser del hogar.",
    });
    const f500 = escritor({ "PATCH calendar/user": { ok: false, status: 500, data: null, error: "Not Found" } });
    assertEquals((await compartirCalendario(f500.esc, 4, 502, false, "Lucía") as { texto: string }).texto, "No he podido compartirlo con Lucía: Ya no existe.");
});
