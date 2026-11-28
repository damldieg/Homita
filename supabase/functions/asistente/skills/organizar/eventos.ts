// Herramientas de eventos: crear_evento, editar_evento, borrar_evento. La lógica vive en
// `_shared/homita/organizar/eventos.ts`; aquí solo el esquema y el despacho.
import type { Tool } from "../../core.ts";
import { prepararBorrarEvento, prepararCrearEvento, prepararEditarEvento } from "../../../_shared/homita/organizar/eventos.ts";
import { ejecutar, esquema, herramienta } from "./base.ts";

const crearEvento: Tool = herramienta({
    name: "crear_evento",
    description:
        "Crea un evento en un calendario. Indispensables: título, inicio (fecha y hora) y calendario (si solo hay uno editable se usa; si hay varios y no lo dicen, devuelve las opciones para preguntar). Opcionales: fin (solo para eventos de varios días), personas y alarma. La descripción no se puede guardar.",
    input_schema: esquema({
        titulo: { type: "string", description: "Título del evento." },
        inicio: { type: "string", description: "Inicio local, AAAA-MM-DD HH:MM." },
        calendario_id: { type: "integer", description: "Id del calendario (viene en el contexto)." },
        fin: { type: "string", description: "Último día, AAAA-MM-DD, solo si dura varios días." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas." },
        alarma_min: { type: "integer", description: "Minutos de antelación del aviso (0 o más)." },
    }, ["titulo", "inicio"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararCrearEvento(input, ctx)),
});

const editarEvento: Tool = herramienta({
    name: "editar_evento",
    description:
        "Cambia un evento. Indispensable: id del evento (ver_eventos) y al menos un cambio. Solo manda lo que cambia (título, inicio, fin, personas, alarma): el resto se conserva, incluida la alarma. Si solo cambia la hora, manda inicio con la misma fecha y la hora nueva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id del evento." },
        titulo: { type: "string", description: "Nuevo título." },
        inicio: { type: "string", description: "Nuevo inicio local, AAAA-MM-DD HH:MM (o solo AAAA-MM-DD para mover el día y conservar la hora)." },
        fin: { type: "string", description: "Nuevo último día, AAAA-MM-DD." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas (sustituye a las actuales)." },
        alarma_min: { type: "integer", description: "Minutos de antelación del aviso (0 o más)." },
    }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararEditarEvento(input, ctx)),
});

const borrarEvento: Tool = herramienta({
    name: "borrar_evento",
    description: "Pide borrar un evento. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id del evento.",
    input_schema: esquema({ id: { type: "integer", description: "Id del evento." } }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararBorrarEvento(input, ctx)),
});

export const HERRAMIENTAS_EVENTOS: Tool[] = [crearEvento, editarEvento, borrarEvento];
