// crear_tarea, editar_tarea, completar_tarea, borrar_tarea. La lógica es la de Kito (`_shared/homita/organizar/tareas.ts`).
import { McpServer, z } from "../../../deps.ts";
import {
    prepararBorrarTarea, prepararCompletarTarea, prepararCrearTarea, prepararEditarTarea,
} from "../../../../_shared/homita/organizar/tareas.ts";
import type { Entorno } from "../../../entorno.ts";
import {
    ANOTACIONES_BORRADO, ANOTACIONES_ORGANIZAR, AVISO_ESCRITURA, borrar, campoConfirmado, campoHogar, campoZona, claveOrganizar,
    conHogar, ejecutar, orgCtx, preparar,
} from "../comun.ts";

const prioridad = z.enum(["alta", "media", "baja"]).optional().describe("alta, media o baja.");
const personas = (que: string) => z.array(z.number().int().positive()).optional().describe(que);

export const registrarTareas = (server: McpServer, env: Entorno): void => {
    server.registerTool("crear_tarea", {
        title: "Crear una tarea",
        description:
            `Crea una tarea en una lista. Indispensable: titulo. La lista: si no la indicas y solo hay una donde se pueda escribir se usa; si hay varias devuelve {falta:["lista"], opciones} y debes preguntar a la persona cuál. Opcionales: personas asignadas, prioridad y fecha límite (vence, en la hora local de la persona; si falla guardar la fecha, la tarea queda creada y sale un aviso). Es idempotente: repetir la misma llamada en el mismo minuto no duplica la tarea (dos tareas idénticas e intencionadas con menos de un minuto de diferencia colapsan en una; un reintento que cruza el minuto duplica). ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            titulo: z.string().describe("Qué hay que hacer."),
            lista_id: z.number().int().positive().optional().describe("Id de la lista (ver_listas)."),
            persona_ids: personas("Ids de las personas asignadas (ver_personas)."),
            prioridad,
            vence: z.string().optional().describe("Fecha límite local: AAAA-MM-DD (hasta el final del día) o AAAA-MM-DD HH:MM."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararCrearTarea(a, orgCtx(ctx), claveOrganizar(ctx, "crear_tarea"))))));

    server.registerTool("editar_tarea", {
        title: "Editar una tarea",
        description:
            `Cambia una tarea. Indispensables: id (ver_tareas) y al menos un cambio. Solo manda lo que cambia: título, personas (sustituyen a las actuales), prioridad o fecha límite (vence vacío la quita). ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id de la tarea (ver_tareas)."),
            titulo: z.string().optional().describe("Nuevo título."),
            persona_ids: personas("Ids de las personas asignadas (sustituye a las actuales)."),
            prioridad,
            vence: z.string().optional().describe("Fecha límite local AAAA-MM-DD o AAAA-MM-DD HH:MM; cadena vacía para quitarla."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararEditarTarea(a, orgCtx(ctx))))));

    server.registerTool("completar_tarea", {
        title: "Completar una tarea",
        description:
            `Marca una tarea como hecha (o como pendiente si completada es false). Indispensable: id (ver_tareas). Repetirlo no cambia nada. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id de la tarea (ver_tareas)."),
            completada: z.boolean().optional().describe("true (por defecto) para completarla, false para volver a ponerla pendiente."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararCompletarTarea(a, orgCtx(ctx))))));

    server.registerTool("borrar_tarea", {
        title: "Borrar una tarea",
        description:
            `BORRA una tarea. Es irreversible. Primera llamada SIN confirmado: no borra y te dice qué se borraría; cuéntaselo a la persona, espera un sí explícito y solo entonces repite con confirmado: true. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id de la tarea (ver_tareas)."),
            confirmado: campoConfirmado,
        }),
        annotations: ANOTACIONES_BORRADO,
    }, conHogar(env, async (ctx, a) => {
        const p = await preparar(() => prepararBorrarTarea(a, orgCtx(ctx)));
        return borrar(ctx, p, a.confirmado, (_extra, nombre) => `la tarea «${nombre}»`);
    }));
};
