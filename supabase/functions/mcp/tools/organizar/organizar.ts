// Herramientas de lectura de organizar: ver_listas, ver_tareas, ver_eventos, ver_rutinas, ver_calendarios y
// ver_personas. La lógica es la de Kito (`_shared/homita/consulta.ts`).
import { McpServer, z } from "../../deps.ts";
import {
    verCalendarios, verEventos, verListas, verPersonas, verRutinas, verTareas,
} from "../../../_shared/homita/consulta.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_LECTURA, AVISO_DATOS, campoHogar, campoZona, leerEnHogar } from "../comun.ts";

const soloMias = (que: string) => z.boolean().optional().describe(`true para «${que}»: solo lo asignado a las personas del usuario.`);

export const registrarOrganizar = (server: McpServer, env: Entorno): void => {
    server.registerTool("ver_listas", {
        title: "Ver las listas de tareas",
        description: `Listas de tareas del hogar, con cuántas tareas pendientes tiene cada una. ${AVISO_DATOS}`,
        inputSchema: z.object({ hogar: campoHogar, timezone: campoZona }),
        annotations: ANOTACIONES_LECTURA,
    }, (args) => leerEnHogar(env, args, (ctx) => verListas({}, ctx)));

    server.registerTool("ver_tareas", {
        title: "Ver tareas",
        description:
            `Tareas del hogar. Por defecto solo las pendientes. Filtra por lista, estado, vencidas, prioridad y solo_mias. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            lista_id: z.number().int().positive().optional().describe("Id de la lista (ver_listas)."),
            estado: z.enum(["pendientes", "completadas", "todas"]).optional().describe("pendientes (por defecto), completadas o todas."),
            vencidas: z.boolean().optional().describe("true para solo las pendientes cuya fecha límite ya pasó."),
            prioridad: z.enum(["alta", "media", "baja"]).optional().describe("alta, media o baja."),
            solo_mias: soloMias("mis tareas"),
        }),
        annotations: ANOTACIONES_LECTURA,
    }, ({ hogar, timezone, ...resto }) =>
        leerEnHogar(env, { hogar, timezone }, (ctx) => verTareas(resto, ctx), { soloMias: resto.solo_mias === true }));

    server.registerTool("ver_eventos", {
        title: "Ver eventos",
        description:
            `Eventos sueltos del hogar (nunca rutinas: para eso está ver_rutinas). Filtra por rango de fechas, texto, calendario y solo_mias. Sin fechas, devuelve los de hoy en adelante. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            desde: z.string().optional().describe("Primer día del rango, AAAA-MM-DD (incluido). Por defecto, hoy."),
            hasta: z.string().optional().describe("Último día del rango, AAAA-MM-DD (incluido)."),
            buscar: z.string().optional().describe("Texto a buscar en el título."),
            calendario_id: z.number().int().positive().optional().describe("Id de un calendario (ver_calendarios)."),
            solo_mias: soloMias("mis eventos"),
        }),
        annotations: ANOTACIONES_LECTURA,
    }, ({ hogar, timezone, ...resto }) =>
        leerEnHogar(env, { hogar, timezone }, (ctx) => verEventos(resto, ctx), { soloMias: resto.solo_mias === true }));

    server.registerTool("ver_rutinas", {
        title: "Ver rutinas",
        description:
            `Rutinas del hogar (no son eventos). Sin fecha, lista cada rutina con su hora, días y a quién se asigna. Con \`dia\`, o con \`desde\` y \`hasta\`, devuelve las veces concretas que tocan en ese periodo (solo de hoy a 89 días; fuera de ahí avisa). ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            dia: z.string().optional().describe("Un día concreto, AAAA-MM-DD."),
            desde: z.string().optional().describe("Primer día del rango, AAAA-MM-DD."),
            hasta: z.string().optional().describe("Último día del rango, AAAA-MM-DD."),
            solo_mias: soloMias("mis rutinas"),
        }),
        annotations: ANOTACIONES_LECTURA,
    }, ({ hogar, timezone, ...resto }) =>
        leerEnHogar(env, { hogar, timezone }, (ctx) => verRutinas(resto, ctx), { soloMias: resto.solo_mias === true }));

    server.registerTool("ver_calendarios", {
        title: "Ver calendarios",
        description: `Calendarios del hogar, con las personas con las que se comparten y si el usuario puede editarlos. ${AVISO_DATOS}`,
        inputSchema: z.object({ hogar: campoHogar, timezone: campoZona }),
        annotations: ANOTACIONES_LECTURA,
    }, (args) => leerEnHogar(env, args, (ctx) => verCalendarios({}, ctx)));

    server.registerTool("ver_personas", {
        title: "Ver personas",
        description: `Personas del hogar (adultos, niños, mascotas) y si tienen cuenta de la app. ${AVISO_DATOS}`,
        inputSchema: z.object({ hogar: campoHogar, timezone: campoZona }),
        annotations: ANOTACIONES_LECTURA,
    }, (args) => leerEnHogar(env, args, (ctx) => verPersonas({}, ctx)));
};
