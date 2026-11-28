// Herramientas de tareas: crear_tarea, editar_tarea, completar_tarea, borrar_tarea. La lógica vive en
// `_shared/homita/organizar/tareas.ts`; aquí solo el esquema y el despacho (el `client_request_id` lo calcula Kito).
import type { Tool } from "../../core.ts";
import {
    PRIORIDADES, prepararBorrarTarea, prepararCompletarTarea, prepararCrearTarea, prepararEditarTarea,
} from "../../../_shared/homita/organizar/tareas.ts";
import { claveDe, ejecutar, esquema, herramienta } from "./base.ts";

const crearTarea: Tool = herramienta({
    name: "crear_tarea",
    description:
        "Crea una tarea en una lista. Indispensables: título y lista (si solo hay una lista editable se usa; si hay varias y no la dicen, devuelve las opciones para preguntar). Opcionales: personas, prioridad y fecha límite.",
    input_schema: esquema({
        titulo: { type: "string", description: "Qué hay que hacer." },
        lista_id: { type: "integer", description: "Id de la lista (viene en el contexto)." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas." },
        prioridad: { type: "string", enum: PRIORIDADES, description: "alta, media o baja." },
        vence: { type: "string", description: "Fecha límite local: AAAA-MM-DD (hasta el final del día) o AAAA-MM-DD HH:MM." },
    }, ["titulo"]),
    run: async (input, ctx, extra) => ejecutar(ctx, await prepararCrearTarea(input, ctx, claveDe(ctx, extra))),
});

const editarTarea: Tool = herramienta({
    name: "editar_tarea",
    description:
        "Cambia una tarea. Indispensable: id de la tarea (ver_tareas) y al menos un cambio. Solo manda lo que cambia: título, personas, prioridad o fecha límite (vence vacío la quita).",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la tarea." },
        titulo: { type: "string", description: "Nuevo título." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas (sustituye a las actuales)." },
        prioridad: { type: "string", enum: PRIORIDADES, description: "alta, media o baja." },
        vence: { type: "string", description: "Fecha límite local AAAA-MM-DD o AAAA-MM-DD HH:MM; cadena vacía para quitarla." },
    }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararEditarTarea(input, ctx)),
});

const completarTarea: Tool = herramienta({
    name: "completar_tarea",
    description: "Marca una tarea como hecha (o como pendiente si completada es false). Indispensable: id de la tarea.",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la tarea." },
        completada: { type: "boolean", description: "true (por defecto) para completarla, false para volver a ponerla pendiente." },
    }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararCompletarTarea(input, ctx)),
});

const borrarTarea: Tool = herramienta({
    name: "borrar_tarea",
    description: "Pide borrar una tarea. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id de la tarea.",
    input_schema: esquema({ id: { type: "integer", description: "Id de la tarea." } }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararBorrarTarea(input, ctx)),
});

export const HERRAMIENTAS_TAREAS: Tool[] = [crearTarea, editarTarea, completarTarea, borrarTarea];
