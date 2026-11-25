// Skill `ayuda`: responde «¿cómo se hace…?» sobre la propia app con una guía curada (guia.ts). La guía llega
// como resultado de la herramienta `guia_app`, no en el system: se puede editar sin crecer el prefijo cacheado.
import type { Skill, Tool } from "../../core.ts";
import { buscar } from "./buscar.ts";

const guiaApp: Tool = {
    name: "guia_app",
    description:
        "Busca en la guía de Homita cómo se hace algo en la app (pantallas, botones y pasos). Devuelve hasta tres " +
        "secciones, o la lista de temas si la guía no cubre lo que se pide.",
    input_schema: {
        type: "object",
        properties: {
            tema: { type: "string", description: "Qué quiere hacer el usuario, con sus palabras (p. ej. «compartir una lista»)." },
        },
        required: ["tema"],
        additionalProperties: false,
    },
    run: (input) => {
        const tema = input.tema;
        if (typeof tema !== "string" || tema.trim() === "") return Promise.reject(new Error("tema obligatorio: texto con lo que se quiere hacer"));
        const r = buscar(tema);
        return Promise.resolve({
            secciones: r.secciones.map((s) => ({ titulo: s.titulo, texto: s.texto })),
            ...(r.temas ? { temas: r.temas, aviso: r.aviso } : {}),
        });
    },
};

export const ayuda: Skill = {
    id: "ayuda",
    nombre: "Ayuda",
    descripcion: "Explica cómo se hace algo en la app Homita (pantallas, botones y pasos) con una guía curada.",
    instrucciones: `Skill «ayuda»: contestas «¿cómo se hace…?» sobre la propia app Homita con la herramienta guia_app.

Para cualquier pregunta sobre cómo hacer algo en Homita (crear, editar o borrar, compartir, invitar, cambiar un color, dónde está algo) llama a guia_app con el tema, con las palabras del usuario, antes de responder. Responde solo con lo que diga la guía: los nombres de pantallas y botones, tal cual, y los pasos en orden, en pocas frases. No inventes pantallas, botones ni pasos que no estén en lo que devuelve.

Si guia_app no encuentra nada, di con naturalidad que eso no lo sabes y que, si es algo que echa en falta, puede enviar feedback desde Ajustes › Enviar feedback (Ajustes se abre con el engranaje de Inicio). No prometas que se vaya a añadir.`,
    herramientas: [guiaApp],
    tarjetas: [],
    disponible: () => true,
};
