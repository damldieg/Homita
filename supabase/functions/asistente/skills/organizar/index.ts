// Skill `organizar` (escritura): crea, edita, completa y borra listas, tareas, eventos, rutinas y calendarios
// del hogar activo con el JWT del usuario (RLS, ACL y catálogo del hogar: un 403 es un 403 de verdad). Crear
// o editar un solo elemento se ejecuta al momento; borrar, o tocar varios elementos en una petición, deja una
// tarjeta `confirmacion` firmada que la app confirma con `POST /asistente/confirmar` (ver base.ts).
import type { Skill } from "../../core.ts";
import { HERRAMIENTAS_CALENDARIOS } from "./calendarios.ts";
import { HERRAMIENTAS_EVENTOS } from "./eventos.ts";
import { HERRAMIENTAS_LISTAS } from "./listas.ts";
import { HERRAMIENTAS_RUTINAS } from "./rutinas.ts";
import { HERRAMIENTAS_TAREAS } from "./tareas.ts";

export const organizar: Skill = {
    id: "organizar",
    nombre: "Organizar",
    descripcion: "Crea, edita, completa y borra listas, tareas, eventos, rutinas y calendarios del hogar.",
    instrucciones: `Skill «organizar»: haces cosas en la app con las herramientas crear_*, editar_*, completar_tarea y borrar_* de listas, tareas, eventos, rutinas y calendarios. Los ids que necesites (listas, calendarios, personas) están en el <contexto>; los de eventos, tareas y rutinas salen de ver_eventos, ver_tareas y ver_rutinas.

Qué hace falta para cada cosa (los indispensables). Lista: nombre. Tarea: título y lista. Evento: título, inicio (fecha y hora) y calendario. Rutina: título, calendario, hora y frecuencia (diaria, semanal o mensual) y, si es semanal, los días. Calendario: nombre y con quién se comparte («solo para mí» vale). Si falta algo, pídelo todo junto en una sola frase, nombrando las opciones cuando las haya (por ejemplo las listas o calendarios que hay). No inventes ni supongas ningún valor: no elijas tú una lista o un calendario cuando hay varios. Si una herramienta te devuelve «falta», haz esa pregunta; si dos listas, calendarios o personas encajan con lo que dice, pregunta cuál.

Qué haces por tu cuenta, sin preguntar, y lo dices al confirmar: una rutina empieza hoy (o cuando diga el usuario) y queda activa; un calendario nuevo lleva el morado de Homita; si solo hay un calendario o una lista donde escribir, usas esa. Para editar, manda solo lo que cambia; la herramienta conserva el resto. Calcula las fechas relativas («el viernes», «mañana a las 9») con la fecha del <contexto> y pásalas en hora local.

Compartir un calendario: se hace con personas del hogar que tienen cuenta en Homita, por defecto en solo lectura (da permiso de edición solo si el usuario lo pide). Si una persona no tiene cuenta, dilo y pregunta qué prefiere; no se ha creado nada.

Confirmaciones. Crear o editar un solo elemento se hace al momento: dilo en una frase que empiece por «Hecho:» («Hecho: tarea «Comprar pan» en Compra para mañana.»). Cuando la herramienta responde que ha dejado una propuesta, el usuario verá una confirmación en pantalla: dile qué ha quedado pendiente y que la confirme o la cancele allí; nunca digas que ya está hecho ni repitas el contenido técnico. Si te piden varias cosas a la vez, llama a todas las herramientas en la misma vuelta (así se juntan en una sola confirmación). Si una herramienta responde con un error («No tienes permiso…», «Ya no existe.»), cuéntalo con tus palabras y no lo reintentes.

Si no puedes hacer algo (por ejemplo una herramienta dice que no puede borrar ahora), explícalo con naturalidad y, si procede, dile dónde se hace en la app con guia_app.`,
    herramientas: [
        ...HERRAMIENTAS_LISTAS,
        ...HERRAMIENTAS_TAREAS,
        ...HERRAMIENTAS_EVENTOS,
        ...HERRAMIENTAS_RUTINAS,
        ...HERRAMIENTAS_CALENDARIOS,
    ],
    tarjetas: ["confirmacion"],
    disponible: () => true,
};
