// Herramientas de listas de tareas: crear_lista, editar_lista, borrar_lista. La lógica (qué se rellena, qué falta,
// qué cuerpo recibe el api) vive en `_shared/homita/organizar/listas.ts`; aquí solo el esquema y el despacho.
import type { Tool } from "../../core.ts";
import { prepararBorrarLista, prepararCrearLista, prepararEditarLista } from "../../../_shared/homita/organizar/listas.ts";
import { claveDe, ejecutar, esquema, herramienta } from "./base.ts";

export { COLOR_DEFECTO, COLOR_RE, ERROR_COLOR } from "../../../_shared/homita/organizar/listas.ts";

const crearLista: Tool = herramienta({
    name: "crear_lista",
    description: "Crea una lista de tareas. Indispensable: nombre. Si no dan color, se usa el morado de Homita (#6923E2).",
    input_schema: esquema({
        nombre: { type: "string", description: "Nombre de la lista." },
        color: { type: "string", description: "Color #RRGGBB, solo si lo piden." },
    }, ["nombre"]),
    run: async (input, ctx, extra) => ejecutar(ctx, await prepararCrearLista(input, claveDe(ctx, extra))),
});

const editarLista: Tool = herramienta({
    name: "editar_lista",
    description:
        "Cambia el nombre o el color de una lista. Indispensable: id de la lista (viene en el contexto) y al menos un cambio. Solo manda lo que cambia: el resto se conserva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la lista." },
        nombre: { type: "string", description: "Nuevo nombre." },
        color: { type: "string", description: "Nuevo color #RRGGBB." },
    }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararEditarLista(input, ctx)),
});

const borrarLista: Tool = herramienta({
    name: "borrar_lista",
    description:
        "Pide borrar una lista con todas sus tareas. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id de la lista.",
    input_schema: esquema({ id: { type: "integer", description: "Id de la lista." } }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararBorrarLista(input, ctx)),
});

export const HERRAMIENTAS_LISTAS: Tool[] = [crearLista, editarLista, borrarLista];
