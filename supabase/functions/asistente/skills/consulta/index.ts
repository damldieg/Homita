// Skill `consulta` (solo lectura): responde sobre eventos, rutinas, listas, tareas, calendarios y personas
// del hogar activo. Las herramientas leen el `api` con el lector que inyecta el handler (`ctx.leer`), que
// hereda RLS, ACL y el filtro del hogar. Salida compacta (ver compacto.ts); fechas ISO con desfase local.
// La lógica de cada herramienta vive en `_shared/homita/consulta.ts` (la comparte el MCP); aquí quedan los nombres,
// las descripciones y los esquemas de Kito.
import type { Skill, Tool } from "../../core.ts";
import { verCalendarios, verEventos, verListas, verPersonas, verRutinas, verTareas } from "../../../_shared/homita/consulta.ts";

// Esquemas compatibles con `strict` (doc de Anthropic, structured outputs): `additionalProperties: false` y
// parámetros opcionales sin listar en `required`. No se usan tipos unión con null: la API limita a 16 los
// parámetros con unión en todas las herramientas strict y a 24 los opcionales (aquí hay 14 opcionales).
const nulo = (type: string, description: string) => ({ type, description });
const esquema = (properties: Record<string, unknown>): Tool["input_schema"] => ({
    type: "object",
    properties,
    required: [],
    additionalProperties: false,
});

const verEventosTool: Tool = {
    name: "ver_eventos",
    description:
        "Lista los eventos sueltos del hogar activo (nunca rutinas: para eso está ver_rutinas). Filtra por rango de fechas, texto, calendario y, con solo_mias, por las personas del usuario. Sin fechas, devuelve los de hoy en adelante.",
    input_schema: esquema({
        desde: nulo("string", "Primer día del rango, AAAA-MM-DD (incluido). Por defecto, hoy."),
        hasta: nulo("string", "Último día del rango, AAAA-MM-DD (incluido)."),
        buscar: nulo("string", "Texto a buscar en el título."),
        calendario_id: nulo("integer", "Id de un calendario (ver_calendarios)."),
        solo_mias: nulo("boolean", "true para «mis eventos»: solo los asignados a las personas del usuario."),
    }),
    run: (input, ctx) => verEventos(input, ctx),
};

const verRutinasTool: Tool = {
    name: "ver_rutinas",
    description:
        "Rutinas del hogar activo (no son eventos). Sin fecha, lista las rutinas con su hora, días y a quién se asignan. Con dia, o con desde y hasta, devuelve las veces concretas que tocan en ese periodo (solo de hoy a 89 días; fuera de ahí avisa). solo_mias filtra por las personas del usuario.",
    input_schema: esquema({
        dia: nulo("string", "Un día concreto, AAAA-MM-DD."),
        desde: nulo("string", "Primer día del rango, AAAA-MM-DD."),
        hasta: nulo("string", "Último día del rango, AAAA-MM-DD."),
        solo_mias: nulo("boolean", "true para «mis rutinas»."),
    }),
    run: (input, ctx) => verRutinas(input, ctx),
};

const verTareasTool: Tool = {
    name: "ver_tareas",
    description:
        "Lista las tareas del hogar activo. Por defecto solo las pendientes. Filtra por lista, estado (pendientes, completadas o todas), vencidas, prioridad (alta, media o baja) y solo_mias.",
    input_schema: esquema({
        lista_id: nulo("integer", "Id de la lista (ver_listas)."),
        estado: nulo("string", "pendientes (por defecto), completadas o todas."),
        vencidas: nulo("boolean", "true para solo las pendientes cuya fecha límite ya pasó."),
        prioridad: nulo("string", "alta, media o baja."),
        solo_mias: nulo("boolean", "true para «mis tareas»."),
    }),
    run: (input, ctx) => verTareas(input, ctx),
};

const verCalendariosTool: Tool = {
    name: "ver_calendarios",
    description: "Lista los calendarios del hogar activo, con las personas con las que se comparten y si el usuario puede editarlos.",
    input_schema: esquema({}),
    run: (input, ctx) => verCalendarios(input, ctx),
};

const verListasTool: Tool = {
    name: "ver_listas",
    description: "Lista las listas de tareas del hogar activo, con cuántas tareas pendientes tiene cada una.",
    input_schema: esquema({}),
    run: (input, ctx) => verListas(input, ctx),
};

const verPersonasTool: Tool = {
    name: "ver_personas",
    description: "Lista las personas del hogar activo (adultos, niños, mascotas) y si tienen cuenta de la app.",
    input_schema: esquema({}),
    run: (input, ctx) => verPersonas(input, ctx),
};

export const consulta: Skill = {
    id: "consulta",
    nombre: "Consulta",
    descripcion: "Responde preguntas sobre eventos, rutinas, tareas, listas, calendarios y personas del hogar (solo lectura).",
    instrucciones: `Skill «consulta» (solo lectura): contestas preguntas sobre el hogar con las herramientas ver_eventos, ver_rutinas, ver_tareas, ver_calendarios, ver_listas y ver_personas.

Eventos y rutinas son cosas distintas y la gente las distingue: un evento ocurre en una fecha concreta (una cita, una cena) y una rutina es algo que se repite (sacar al perro cada mañana). Para eventos usa ver_eventos, para rutinas ver_rutinas, y nunca llames «evento» a una rutina ni al revés. Para «mañana» o «esta semana» calcula el día con la fecha del <contexto> y pásalo a la herramienta (ver_rutinas admite un día concreto o un rango y devuelve las veces que toca en ese periodo; sin fecha devuelve cómo está definida cada rutina).

Cuando el usuario diga «mis…», «lo mío» o «lo que tengo yo», usa solo_mias=true. Si la herramienta avisa de que su cuenta no está vinculada a ninguna persona del hogar, díselo tal cual y ofrécele ver lo de todo el hogar si quiere; no enseñes datos de otras personas como si fueran suyos. Si algo no tiene a nadie asignado, dilo («sin asignar»).

Si dos listas o calendarios encajan con lo que pide, pregunta cuál quiere nombrando las opciones. Si no hay resultados, dilo y sugiere otra búsqueda (otro día, otro calendario, otra lista). Si la herramienta indica que hay más resultados (hay_mas), cuenta los que has visto y ofrécete a acotar. Las tareas se piden pendientes por defecto; usa estado, vencidas o prioridad cuando la pregunta lo pida.

Crear, cambiar o borrar cosas lo hace la skill «organizar» con sus herramientas, no esta. Si te preguntan cómo se hace algo en la app (pantalla y botón), llama a guia_app con el tema y responde con lo que devuelva, sin inventar pasos.`,
    herramientas: [verEventosTool, verRutinasTool, verTareasTool, verCalendariosTool, verListasTool, verPersonasTool],
    tarjetas: [],
    disponible: () => true,
};
