// crear_rutina, editar_rutina, borrar_rutina. La lógica es la de Kito (`_shared/homita/organizar/rutinas.ts`). La alarma
// no se expone. Editar reenvía la rutina completa: el api valida la rutina entera y conserva las personas asignadas.
import { McpServer, z } from "../../../deps.ts";
import { prepararBorrarRutina, prepararCrearRutina, prepararEditarRutina } from "../../../../_shared/homita/organizar/rutinas.ts";
import type { Entorno } from "../../../entorno.ts";
import {
    ANOTACIONES_BORRADO, ANOTACIONES_ORGANIZAR, AVISO_ESCRITURA, borrar, campoConfirmado, campoHogar, campoZona, conHogar, ejecutar,
    orgCtx, preparar,
} from "../comun.ts";

const dias = z.array(z.number().int().min(1).max(7)).optional().describe("Días de la semana del 1 (lunes) al 7 (domingo).");

export const registrarRutinas = (server: McpServer, env: Entorno): void => {
    server.registerTool("crear_rutina", {
        title: "Crear una rutina",
        description:
            `Crea una rutina (algo que se repite). Indispensables: titulo, hora (HH:MM) y frecuencia (diaria, semanal o mensual); si es semanal, también dias. El calendario: si no lo indicas y solo hay uno donde se pueda escribir se usa; si hay varios devuelve {falta:["calendario"], opciones} y debes preguntar cuál. Empieza hoy y queda activa salvo que indiques desde: díselo a la persona (viene en la respuesta). NO es idempotente: si no sabes si se creó, compruébalo con ver_rutinas antes de reintentar. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            titulo: z.string().describe("Título de la rutina."),
            hora: z.string().describe("Hora local HH:MM."),
            frecuencia: z.enum(["diaria", "semanal", "mensual"]).describe("Con qué frecuencia se repite."),
            calendario_id: z.number().int().positive().optional().describe("Id del calendario (ver_calendarios)."),
            dias,
            intervalo: z.number().int().positive().optional().describe("Cada cuántas veces (1 por defecto; 2 = cada dos semanas)."),
            desde: z.string().optional().describe("Primer día, AAAA-MM-DD; por defecto hoy."),
            hasta: z.string().optional().describe("Último día, AAAA-MM-DD, si termina."),
            persona_ids: z.array(z.number().int().positive()).optional().describe("Ids de las personas asignadas (ver_personas)."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararCrearRutina(a, orgCtx(ctx))))));

    server.registerTool("editar_rutina", {
        title: "Editar una rutina",
        description:
            `Cambia una rutina. Indispensables: id (ver_rutinas) y al menos un cambio. Solo manda lo que cambia: el resto (fechas, activa, días, personas) se conserva. hasta vacío ("") hace que no termine; activa false la pausa. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id de la rutina (ver_rutinas)."),
            titulo: z.string().optional().describe("Nuevo título."),
            hora: z.string().optional().describe("Nueva hora local HH:MM."),
            frecuencia: z.enum(["diaria", "semanal", "mensual"]).optional().describe("Nueva frecuencia."),
            dias,
            intervalo: z.number().int().positive().optional().describe("Cada cuántas veces."),
            desde: z.string().optional().describe("Nuevo primer día, AAAA-MM-DD."),
            hasta: z.string().optional().describe("Nuevo último día, AAAA-MM-DD; cadena vacía para que no termine."),
            activa: z.boolean().optional().describe("false para pausarla, true para reactivarla."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararEditarRutina(a, orgCtx(ctx))))));

    server.registerTool("borrar_rutina", {
        title: "Borrar una rutina",
        description:
            `BORRA una rutina. Es irreversible. Primera llamada SIN confirmado: no borra y te dice qué se borraría; cuéntaselo a la persona, espera un sí explícito y solo entonces repite con confirmado: true. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id de la rutina (ver_rutinas)."),
            confirmado: campoConfirmado,
        }),
        annotations: ANOTACIONES_BORRADO,
    }, conHogar(env, async (ctx, a) => {
        const p = await preparar(() => prepararBorrarRutina(a, orgCtx(ctx)));
        return borrar(ctx, p, a.confirmado, (_extra, nombre) => `la rutina «${nombre}»`);
    }));
};
