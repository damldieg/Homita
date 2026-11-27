import { McpServer, z } from "../../deps.ts";
import { ZONA_POR_DEFECTO } from "../../entorno.ts";
import type { Entorno } from "../../entorno.ts";
import { errorTool, resultadoJson } from "../../errores.ts";
import { leerHogares } from "../../hogar.ts";
import { ANOTACIONES_LECTURA, AVISO_DATOS, errorDe } from "../comun.ts";

export const registrarVerHogares = (server: McpServer, env: Entorno): void => {
    server.registerTool("ver_hogares", {
        title: "Ver mis hogares",
        description:
            `Lista los hogares de Homita del usuario con su id, su rol y cuál es el predeterminado. El resto de herramientas aceptan \`hogar\` con uno de estos ids; sin él usan el predeterminado. ${AVISO_DATOS}`,
        inputSchema: z.object({}),
        annotations: ANOTACIONES_LECTURA,
    }, async () => {
        try {
            const hogares = await leerHogares(env, ZONA_POR_DEFECTO);
            if (hogares.length === 0) return errorTool("No tienes ningún hogar en Homita.");
            return resultadoJson({
                hogares: hogares.map((h) => ({
                    id: h.id, nombre: h.nombre, rol: h.rol, predeterminado: h.predeterminado, personal: h.personal,
                })),
            });
        } catch (e) {
            return errorDe(e);
        }
    });
};
