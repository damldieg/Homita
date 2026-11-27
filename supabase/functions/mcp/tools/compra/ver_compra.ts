import { McpServer, z } from "../../deps.ts";
import { verCompra } from "../../../_shared/homita/compra.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_LECTURA, AVISO_DATOS, campoHogar, campoZona, leerEnHogar } from "../comun.ts";

export const registrarVerCompra = (server: McpServer, env: Entorno): void => {
    server.registerTool("ver_compra", {
        title: "Ver la compra",
        description:
            `La lista de la compra del hogar: artículo, cantidad, sección y estado (pendiente, comprado, ya lo tengo). Con \`plan_id\` (de leer_semana) devuelve en cambio lo que entraría en la compra desde ese menú, sin guardar nada. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            plan_id: z.number().int().positive().optional().describe("Id de un menú: previsualiza su compra."),
            solo_pendientes: z.boolean().optional().describe("true para ver solo lo pendiente de comprar."),
        }),
        annotations: ANOTACIONES_LECTURA,
    }, ({ hogar, timezone, plan_id, solo_pendientes }) =>
        leerEnHogar(env, { hogar, timezone }, (ctx) => verCompra({ plan_id, solo_pendientes }, ctx)));
};
