// Herramientas de calendarios: crear_calendario, editar_calendario, borrar_calendario. La lógica vive en
// `_shared/homita/organizar/calendarios.ts`; aquí solo el esquema y el despacho.
//
// «De quién es» un calendario = con quién se comparte: crear_calendario pregunta con quién (o «solo yo»).
import type { Tool } from "../../core.ts";
import { prepararBorrarCalendario, prepararCrearCalendario, prepararEditarCalendario } from "../../../_shared/homita/organizar/calendarios.ts";
import { ejecutar, esquema, herramienta } from "./base.ts";

const crearCalendario: Tool = herramienta({
    name: "crear_calendario",
    description:
        "Crea un calendario. Indispensables: nombre y con quién se comparte (compartir_con con personas del hogar que tengan cuenta, o solo_yo = true si es solo para el usuario). Por defecto comparte en solo lectura; puede_editar da permiso de edición. Si falta con quién, pregúntalo.",
    input_schema: esquema({
        nombre: { type: "string", description: "Nombre del calendario." },
        solo_yo: { type: "boolean", description: "true si el calendario es solo para el usuario." },
        compartir_con: {
            type: "array",
            description: "Personas con las que se comparte (ids del contexto).",
            items: {
                type: "object",
                properties: {
                    persona_id: { type: "integer", description: "Id de la persona." },
                    puede_editar: { type: "boolean", description: "true para permiso de edición; por defecto solo lectura." },
                },
                required: ["persona_id"],
            },
        },
        color: { type: "string", description: "Color #RRGGBB, solo si lo piden." },
    }, ["nombre"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararCrearCalendario(input, ctx)),
});

const editarCalendario: Tool = herramienta({
    name: "editar_calendario",
    description:
        "Cambia el nombre o el color de un calendario. Indispensable: id del calendario (viene en el contexto) y al menos un cambio. Solo manda lo que cambia: el resto se conserva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id del calendario." },
        nombre: { type: "string", description: "Nuevo nombre." },
        color: { type: "string", description: "Nuevo color #RRGGBB." },
    }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararEditarCalendario(input, ctx)),
});

const borrarCalendario: Tool = herramienta({
    name: "borrar_calendario",
    description:
        "Pide borrar un calendario con sus eventos y rutinas. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id del calendario.",
    input_schema: esquema({ id: { type: "integer", description: "Id del calendario." } }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararBorrarCalendario(input, ctx)),
});

export const HERRAMIENTAS_CALENDARIOS: Tool[] = [crearCalendario, editarCalendario, borrarCalendario];
