// Herramientas de lectura de menús: leer_perfil, leer_semana, buscar_recetas y buscar_alimento.
// La salud (objetivos, notas de dieta) no se devuelve en esta versión.
import { McpServer, z } from "../../deps.ts";
import { buscarRecetas, leerPerfilCompacto, leerSemana } from "../../../_shared/homita/menus-lectura.ts";
import { compactarAlimentos } from "../../../_shared/homita/alimentos.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_LECTURA, AVISO_DATOS, campoHogar, campoZona, leerEnHogar } from "../comun.ts";

export const registrarMenus = (server: McpServer, env: Entorno): void => {
    server.registerTool("leer_perfil", {
        title: "Leer el perfil de comidas",
        description:
            `Perfil de comidas del hogar: franjas que se planifican, tiempo para cocinar, países, y por persona alergias, dieta, lo que no le gusta, favoritos y picante. No incluye datos de salud. ${AVISO_DATOS}`,
        inputSchema: z.object({ hogar: campoHogar, timezone: campoZona }),
        annotations: ANOTACIONES_LECTURA,
    }, (args) => leerEnHogar(env, args, (ctx) => leerPerfilCompacto(ctx)));

    server.registerTool("leer_semana", {
        title: "Leer una semana de menú",
        description:
            `Una semana del hogar: eventos del calendario, quién no come en casa cada día y franja, y el menú que ya existe (casillas, estado, revisión, plan_id). Con \`fecha\` (AAAA-MM-DD, cualquier día de esa semana; por defecto hoy) elige la semana. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            fecha: z.string().optional().describe("Cualquier día de la semana, AAAA-MM-DD."),
        }),
        annotations: ANOTACIONES_LECTURA,
    }, (args) => leerEnHogar(env, args, (ctx) => leerSemana({ fecha: args.fecha }, ctx)));

    server.registerTool("buscar_recetas", {
        title: "Buscar recetas",
        description:
            `Busca en el recetario del hogar (por texto, franja o minutos máximos) y devuelve también \`ya_tomados\`: los platos de las últimas semanas. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            texto: z.string().optional().describe("Texto a buscar en el nombre."),
            franja: z.enum(["breakfast", "midmorning", "lunch", "snack", "dinner"]).optional()
                .describe("breakfast, midmorning, lunch, snack o dinner."),
            max_minutos: z.number().int().positive().optional().describe("Tiempo máximo de preparación."),
            semana: z.string().optional().describe("Inicio de la semana de referencia, AAAA-MM-DD."),
            semanas_historial: z.number().int().positive().optional().describe("Semanas anteriores a mirar (por defecto 3, máximo 8)."),
        }),
        annotations: ANOTACIONES_LECTURA,
    }, ({ hogar, timezone, ...resto }) => leerEnHogar(env, { hogar, timezone }, (ctx) => buscarRecetas(resto, ctx)));

    server.registerTool("buscar_alimento", {
        title: "Buscar un alimento",
        description:
            `Busca en el catálogo de alimentos (comunes y del hogar) por nombre: id, sección, alérgenos y unidad por defecto. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            texto: z.string().optional().describe("Texto a buscar en el nombre; sin él, los primeros del catálogo."),
            limite: z.number().int().min(1).max(50).optional().describe("Máximo de resultados (1-50, por defecto 20)."),
        }),
        annotations: ANOTACIONES_LECTURA,
    }, ({ hogar, timezone, texto, limite }) =>
        leerEnHogar(env, { hogar, timezone }, async (ctx) => {
            const crudo = await ctx.leer!("food", {
                q: texto?.trim() === "" ? undefined : texto?.trim().slice(0, 80),
                limit: limite === undefined ? undefined : String(limite),
            });
            return compactarAlimentos(crudo);
        }));
};
