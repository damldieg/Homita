// crear_evento, editar_evento, borrar_evento. La lógica es la de Kito (`_shared/homita/organizar/eventos.ts`). La alarma
// no se expone (queda fuera de alcance); editar conserva la alarma que tuviera el evento.
import { McpServer, z } from "../../../deps.ts";
import { prepararBorrarEvento, prepararCrearEvento, prepararEditarEvento } from "../../../../_shared/homita/organizar/eventos.ts";
import type { Entorno } from "../../../entorno.ts";
import {
    ANOTACIONES_BORRADO, ANOTACIONES_ORGANIZAR, AVISO_ESCRITURA, borrar, campoConfirmado, campoHogar, campoZona, conHogar, ejecutar,
    orgCtx, preparar,
} from "../comun.ts";

const personas = (que: string) => z.array(z.number().int().positive()).optional().describe(que);

export const registrarEventos = (server: McpServer, env: Entorno): void => {
    server.registerTool("crear_evento", {
        title: "Crear un evento",
        description:
            `Crea un evento en un calendario. Indispensables: titulo e inicio (fecha y hora, hora local de la persona). El calendario: si no lo indicas y solo hay uno donde se pueda escribir se usa; si hay varios devuelve {falta:["calendario"], opciones} y debes preguntar cuál. Opcionales: fin (último día, solo si dura varios días) y personas. No tiene alarma ni descripción. NO es idempotente: si no sabes si se creó (un fallo o un tiempo de espera), compruébalo con ver_eventos antes de reintentar. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            titulo: z.string().describe("Título del evento."),
            inicio: z.string().describe("Inicio local, AAAA-MM-DD HH:MM."),
            calendario_id: z.number().int().positive().optional().describe("Id del calendario (ver_calendarios)."),
            fin: z.string().optional().describe("Último día, AAAA-MM-DD, solo si dura varios días."),
            persona_ids: personas("Ids de las personas asignadas (ver_personas)."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararCrearEvento(a, orgCtx(ctx))))));

    server.registerTool("editar_evento", {
        title: "Editar un evento",
        description:
            `Cambia un evento. Indispensables: id (ver_eventos) y al menos un cambio. Solo manda lo que cambia (título, inicio, fin, personas): el resto se conserva, incluida la alarma. Si solo cambia el día, manda inicio solo con la fecha y conserva la hora. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id del evento (ver_eventos)."),
            titulo: z.string().optional().describe("Nuevo título."),
            inicio: z.string().optional().describe("Nuevo inicio local, AAAA-MM-DD HH:MM (o solo AAAA-MM-DD para mover el día y conservar la hora)."),
            fin: z.string().optional().describe("Nuevo último día, AAAA-MM-DD."),
            persona_ids: personas("Ids de las personas asignadas (sustituye a las actuales)."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararEditarEvento(a, orgCtx(ctx))))));

    server.registerTool("borrar_evento", {
        title: "Borrar un evento",
        description:
            `BORRA un evento. Es irreversible. Primera llamada SIN confirmado: no borra y te dice qué se borraría; cuéntaselo a la persona, espera un sí explícito y solo entonces repite con confirmado: true. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id del evento (ver_eventos)."),
            confirmado: campoConfirmado,
        }),
        annotations: ANOTACIONES_BORRADO,
    }, conHogar(env, async (ctx, a) => {
        const p = await preparar(() => prepararBorrarEvento(a, orgCtx(ctx)));
        return borrar(ctx, p, a.confirmado, (extra, nombre) => `el evento «${nombre}»${typeof extra.cuando === "string" ? extra.cuando : ""}`);
    }));
};
