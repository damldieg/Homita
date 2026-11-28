// Herramientas de rutinas: crear_rutina, editar_rutina, borrar_rutina. La lógica vive en
// `_shared/homita/organizar/rutinas.ts`; aquí solo el esquema y el despacho.
import type { Tool } from "../../core.ts";
import { prepararBorrarRutina, prepararCrearRutina, prepararEditarRutina } from "../../../_shared/homita/organizar/rutinas.ts";
import { ejecutar, esquema, herramienta } from "./base.ts";

const crearRutina: Tool = herramienta({
    name: "crear_rutina",
    description:
        "Crea una rutina (algo que se repite). Indispensables: título, calendario (si solo hay uno editable se usa), hora y frecuencia; si es semanal, también los días. Empieza hoy y queda activa salvo que el usuario diga otra fecha de inicio: dilo en la confirmación.",
    input_schema: esquema({
        titulo: { type: "string", description: "Título de la rutina." },
        calendario_id: { type: "integer", description: "Id del calendario (viene en el contexto)." },
        hora: { type: "string", description: "Hora local HH:MM." },
        frecuencia: { type: "string", enum: ["diaria", "semanal", "mensual"], description: "Con qué frecuencia se repite." },
        dias: { type: "array", items: { type: "integer" }, description: "Solo si es semanal: días de la semana del 1 (lunes) al 7 (domingo)." },
        intervalo: { type: "integer", description: "Cada cuántas veces (1 por defecto; 2 = cada dos semanas)." },
        desde: { type: "string", description: "Primer día, AAAA-MM-DD; por defecto hoy." },
        hasta: { type: "string", description: "Último día, AAAA-MM-DD, si termina." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas." },
        alarma_min: { type: "integer", description: "Minutos de antelación del aviso (0 o más)." },
    }, ["titulo", "hora", "frecuencia"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararCrearRutina(input, ctx)),
});

const editarRutina: Tool = herramienta({
    name: "editar_rutina",
    description:
        "Cambia una rutina. Indispensable: id de la rutina (ver_rutinas) y al menos un cambio. Solo manda lo que cambia: el resto (fechas de inicio y fin, activa, días) se conserva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la rutina." },
        titulo: { type: "string", description: "Nuevo título." },
        hora: { type: "string", description: "Nueva hora local HH:MM." },
        frecuencia: { type: "string", enum: ["diaria", "semanal", "mensual"], description: "Nueva frecuencia." },
        dias: { type: "array", items: { type: "integer" }, description: "Días de la semana del 1 (lunes) al 7 (domingo)." },
        intervalo: { type: "integer", description: "Cada cuántas veces." },
        desde: { type: "string", description: "Nuevo primer día, AAAA-MM-DD." },
        hasta: { type: "string", description: "Nuevo último día, AAAA-MM-DD; cadena vacía para que no termine." },
        activa: { type: "boolean", description: "false para pausarla, true para reactivarla." },
    }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararEditarRutina(input, ctx)),
});

const borrarRutina: Tool = herramienta({
    name: "borrar_rutina",
    description: "Pide borrar una rutina. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id de la rutina.",
    input_schema: esquema({ id: { type: "integer", description: "Id de la rutina." } }, ["id"]),
    run: async (input, ctx) => ejecutar(ctx, await prepararBorrarRutina(input, ctx)),
});

export const HERRAMIENTAS_RUTINAS: Tool[] = [crearRutina, editarRutina, borrarRutina];
