// Caracterización de la skill `organizar` (change mcp-organizar, T3). Fija, contra `organizar_caracterizacion.json`,
// los cuerpos y las salidas de Kito. Deben pasar igual antes y después de mover la lógica a `_shared/homita/organizar/`.
import { assertEquals } from "jsr:@std/assert@1";
import { createHandler } from "../handler.ts";
import type { HandlerDeps } from "../handler.ts";
import { firmar } from "../skills/organizar/confirmacion.ts";
import type { Accion } from "../skills/organizar/confirmacion.ts";
import { correr, correrAcciones, correrErrores, ESCENARIOS } from "./organizar_caracterizacion_escenarios.ts";
import { escritorFalso, SECRETO } from "./organizar_util.ts";
import esperado from "./organizar_caracterizacion.json" with { type: "json" };

const herramientas = esperado.herramientas as Record<string, unknown>;

for (const e of ESCENARIOS) {
    Deno.test(`caracterización Kito: ${e.nombre}`, async () => {
        assertEquals(await correr(e), herramientas[e.nombre]);
    });
}

Deno.test("caracterización Kito: ejecutarAccion de las 16 operaciones (ok, 403, no existe, 400) y altas compuestas", async () => {
    assertEquals(await correrAcciones(), esperado.acciones);
});

Deno.test("caracterización Kito: traducir y esNoExiste", () => {
    assertEquals(correrErrores(), esperado.errores);
});

Deno.test("caracterización Kito: todos los escenarios están en el JSON y viceversa", () => {
    assertEquals(Object.keys(herramientas).sort(), ESCENARIOS.map((e) => e.nombre).sort());
});

// ── Confirmaciones por /asistente/confirmar que no cubría ningún test (editar_* y completar_tarea) ──
const TOKEN = "jwt-de-prueba";
const HOME = "42";
const AHORA = new Date("2026-11-25T10:00:00Z");

const confirmarCon = async (acciones: Accion[]) => {
    const e = escritorFalso();
    const d: HandlerDeps = {
        verifyUser: (t) => Promise.resolve(t === TOKEN ? { uid: "uid-1" } : null),
        appUserId: () => Promise.resolve("501"),
        checkHomeMember: () => Promise.resolve(true),
        runInHome: (_h, fn) => fn(),
        usage: { consume: () => Promise.resolve({ allowed: true, used: 1, limit: 50, day: "2026-11-25" }), record: () => Promise.resolve() },
        callModel: () => Promise.reject(new Error("no debe llamarse")),
        model: "m",
        skills: [],
        crearEscritor: () => e.escribir,
        env: (n) => (n === "KITO_CONFIRM_SECRET" ? SECRETO : n === "ANTHROPIC_API_KEY" ? "k" : undefined),
        now: () => AHORA,
        log: () => {},
    };
    const token = await firmar({ v: 1, uid: "uid-1", home_id: HOME, exp: Math.floor(AHORA.getTime() / 1000) + 600, acciones }, SECRETO);
    const res = await createHandler(d)(new Request("https://x.local/functions/v1/asistente/confirmar", {
        method: "POST",
        headers: { Authorization: `Bearer ${TOKEN}`, "X-Home-Id": HOME, "Content-Type": "application/json" },
        body: JSON.stringify({ token, timezone: "Europe/Madrid" }),
    }));
    return { status: res.status, body: await res.json(), llamadas: e.llamadas };
};

Deno.test("caracterización Kito: /asistente/confirmar ejecuta ediciones y completar_tarea con el cuerpo del token", async () => {
    const r = await confirmarCon([
        { op: "editar_tarea", args: { id: 5, title: "Llamar", priority: "baja" }, nombre: "Llamar" },
        { op: "completar_tarea", args: { id: 5, completed: true }, nombre: "Llamar" },
        { op: "completar_tarea", args: { id: 6, completed: false }, nombre: "Pan" },
        { op: "editar_evento", args: { id: 6, title: "Cena", date_at: "2026-12-01 20:30:00", alarm: 15 }, nombre: "Cena" },
        { op: "editar_rutina", args: { id: 7, title: "Regar", frequency: "daily", interval: 1, days: [], time: "08:00", start_date: "2026-11-25", end_date: null, active: false }, nombre: "Regar" },
        { op: "editar_calendario", args: { id: 10, name: "F", color: "#000000", widget: true, dashboard: false }, nombre: "F" },
    ]);
    assertEquals(r.status, 200);
    assertEquals(r.llamadas.map((l) => [l.metodo, l.ruta, l.cuerpo]), [
        ["PATCH", "task/update", { id: 5, title: "Llamar", priority: "baja" }],
        ["PATCH", "task/complete", { id: 5, completed: true }],
        ["PATCH", "task/complete", { id: 6, completed: false }],
        ["PATCH", "event/update", { id: 6, title: "Cena", date_at: "2026-12-01 20:30:00", alarm: 15 }],
        ["PATCH", "routine/update", { id: 7, title: "Regar", frequency: "daily", interval: 1, days: [], time: "08:00", start_date: "2026-11-25", end_date: null, active: false }],
        ["PATCH", "calendar/update", { id: 10, name: "F", color: "#000000", widget: true, dashboard: false }],
    ]);
    assertEquals(r.body, {
        texto: "Hecho:\n- Editada la tarea «Llamar».\n- Tarea «Llamar» completada.\n- Tarea «Pan» marcada como pendiente.\n- Editado el evento «Cena».\n- Editada la rutina «Regar».\n- Editado el calendario «F».",
        cambios: [
            { tipo: "tarea", id: 5, op: "editar" }, { tipo: "tarea", id: 5, op: "editar" }, { tipo: "tarea", id: 6, op: "editar" },
            { tipo: "evento", id: 6, op: "editar" }, { tipo: "rutina", id: 7, op: "editar" }, { tipo: "calendario", id: 10, op: "editar" },
        ],
    });
});
