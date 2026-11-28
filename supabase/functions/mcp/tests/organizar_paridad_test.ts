// Paridad con Kito: el MCP envía al api exactamente los mismos cuerpos que Kito para los mismos casos. Se reutilizan
// los escenarios de caracterización de Kito (`asistente/tests/organizar_caracterizacion_*`): donde Kito ejecuta una
// escritura, el MCP debe hacer las mismas llamadas de escritura (salvo `client_request_id`, que en Kito sale del
// `tool_use.id` y en el MCP del contenido y el minuto).
import { assertEquals } from "jsr:@std/assert@1";
import { ESCENARIOS } from "../../asistente/tests/organizar_caracterizacion_escenarios.ts";
import type { Escenario } from "../../asistente/tests/organizar_caracterizacion_escenarios.ts";
import esperado from "../../asistente/tests/organizar_caracterizacion.json" with { type: "json" };
import { OPS } from "../../_shared/homita/organizar/acciones.ts";
import { crearMundo, llamarTool } from "./util.ts";
import type { EscrituraFalsa } from "./util.ts";

type Llamada = { metodo: string; ruta: string; cuerpo: Record<string, unknown> };
const kito = esperado.herramientas as Record<string, { llamadas: Llamada[] }>;

/** Claves del esquema del MCP: lo que el MCP no expone (alarma) o la fecha de hoy distinta quedan fuera de la paridad. */
const FUERA = (e: Escenario): boolean =>
    "alarma_min" in e.input || (e.herramienta === "crear_rutina" && !("desde" in e.input)) || e.sinLector === true || e.escrituras === 2;

const sinClave = (l: Llamada): Llamada => {
    const { client_request_id: _c, timezone: _t, ...cuerpo } = l.cuerpo;
    return { metodo: l.metodo, ruta: l.ruta, cuerpo };
};

for (const e of ESCENARIOS) {
    const escrituras = kito[e.nombre].llamadas.filter((l) => l.metodo !== "GET");
    if (escrituras.length === 0 || FUERA(e)) continue;
    Deno.test(`paridad con Kito: ${e.nombre}`, async () => {
        const falsas: Record<string, EscrituraFalsa> = {};
        for (const o of Object.values(OPS)) falsas[`${o.metodo} ${o.ruta}`] = { ok: true, status: 200, data: { id: 1 } };
        falsas["PATCH calendar/user"] = { ok: true, status: 200, data: {} };
        for (const [k, r] of Object.entries(e.resp ?? {})) falsas[k] = r as EscrituraFalsa;
        const lecturas: Record<string, unknown> = { ...(e.leer ?? {}) };
        const m = crearMundo(lecturas, { appUserId: () => Promise.resolve("501") }, {}, falsas);
        const { resultado } = await llamarTool(m, e.herramienta, e.input);
        const mcp = m.escrituras.filter((l) => l.metodo !== "GET").map((l) => sinClave({ metodo: l.metodo, ruta: l.ruta, cuerpo: l.cuerpo }));
        assertEquals(mcp, escrituras.map(sinClave), JSON.stringify(resultado));
    });
}
