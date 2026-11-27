// Herramientas de lectura de la skill `menus`: leer_perfil, leer_semana y buscar_recetas. Solo leen con el lector
// del usuario (`ctx.leer`): RLS, permisos y hogar activo los pone el api. No escriben nada. La lógica vive en
// `_shared/homita/menus-lectura.ts` (la comparte el MCP); aquí quedan los nombres, descripciones y esquemas de Kito.
import type { Tool } from "../../core.ts";
import { buscarRecetas, compactarPerfil, leerPerfilCompacto, leerSemana, paisesDe } from "../../../_shared/homita/menus-lectura.ts";
import { esquema, FRANJAS } from "./util.ts";

export { compactarPerfil, paisesDe };

export const leerPerfilTool: Tool = {
    name: "leer_perfil",
    description:
        "Lee el perfil de comidas del hogar: franjas que se planifican, cuánto tiempo hay para cocinar, países del hogar, y por persona alergias, dieta, lo que no le gusta, favoritos y picante. Ejecútala siempre antes de proponer un menú. Si hay alergias sin responder, pregúntalas antes de proponer.",
    input_schema: esquema({}),
    strict: false,
    run: (_input, ctx) => leerPerfilCompacto(ctx),
};

export const leerSemanaTool: Tool = {
    name: "leer_semana",
    description:
        "Lee una semana: eventos del calendario, quién no come en casa cada día y franja (meal_schedule), y el menú que ya existe (casillas, estado, revisión). Con `fecha` (AAAA-MM-DD, cualquier día de esa semana; por defecto hoy) elige la semana. Devuelve `semana.inicio` (el día de inicio que hay que pasar a proponer_menu). Los días fuera hay que confirmarlos con la persona antes de proponer.",
    input_schema: esquema({ fecha: { type: "string", description: "Cualquier día de la semana, AAAA-MM-DD." } }),
    strict: false,
    run: (input, ctx) => leerSemana(input, ctx),
};

export const buscarRecetasTool: Tool = {
    name: "buscar_recetas",
    description:
        "Busca en el recetario del hogar (por texto, franja o minutos máximos) y devuelve también `ya_tomados`: los platos de las últimas semanas, para no repetirlos. Con `semana` (el inicio de la semana que vas a proponer) se miran las semanas anteriores a esa.",
    input_schema: esquema({
        texto: { type: "string", description: "Texto a buscar en el nombre." },
        franja: { type: "string", enum: [...FRANJAS], description: "breakfast, midmorning, lunch, snack o dinner." },
        max_minutos: { type: "integer", description: "Tiempo máximo de preparación." },
        semana: { type: "string", description: "Inicio de la semana que se va a proponer, AAAA-MM-DD." },
        semanas_historial: { type: "integer", description: "Cuántas semanas anteriores mirar (por defecto 3, máximo 8)." },
    }),
    strict: false,
    run: (input, ctx) => buscarRecetas(input, ctx),
};
