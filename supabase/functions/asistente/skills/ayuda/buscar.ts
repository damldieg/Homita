// Búsqueda en la guía de la app. Propia de `ayuda` (no depende de `consulta`): normaliza (minúsculas, sin
// acentos ni signos), parte en palabras, descarta las vacías y quita el plural final; después puntúa cada
// sección por palabra de la consulta: 3 si está en sus `palabras` (sinónimos), 2 si está en el título y 1 si
// está en el texto (una vez por palabra y sección). Hace falta un mínimo de puntos para devolver algo.
import { GUIA, type Seccion } from "./guia.ts";

/** Tope de secciones por respuesta. */
export const MAX_SECCIONES = 3;
/** Puntos mínimos de una sección para considerarla coincidencia. */
export const UMBRAL = 3;
/** Solo se devuelven las secciones con al menos esta fracción de la mejor puntuación. */
const FRACCION_MEJOR = 0.5;

const VACIAS = new Set([
    "como", "que", "puedo", "puede", "pueden", "hago", "hacer", "debo", "quiero", "tengo", "de", "del", "la", "las", "el", "los", "un",
    "una", "unos", "unas", "en", "a", "al", "mi", "mis", "tu", "tus", "se", "me", "te", "lo", "y", "o", "por", "para", "con", "es",
    "hay", "donde", "cual", "cuales", "cuando", "sobre", "si",
]);

/** Minúsculas, sin acentos y con todo lo que no sea letra o cifra convertido en un espacio. */
export const normalizar = (s: string): string =>
    s.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "").replace(/[^a-z0-9]+/g, " ").trim();

/** Plural → singular tosco («listas» → «lista», «invitaciones» → «invitacion»); solo palabras de más de 3 letras. */
const singular = (t: string): string => {
    if (t.length <= 3) return t;
    if (t.length > 4 && t.endsWith("es")) return t.slice(0, -2);
    return t.endsWith("s") ? t.slice(0, -1) : t;
};

/** Palabras significativas de un texto, normalizadas y en singular. */
export const tokens = (s: string): string[] =>
    normalizar(s).split(" ").filter((t) => t !== "" && !VACIAS.has(t)).map(singular);

export interface Resultado {
    secciones: Seccion[];
    /** Títulos de todos los temas, solo cuando no hay coincidencia. */
    temas?: string[];
    aviso?: string;
}

export const AVISO_SIN_COINCIDENCIA =
    "No hay en la guía ningún tema que encaje con eso. No inventes pasos ni pantallas: di con naturalidad que no lo sabes " +
    "y sugiere enviar feedback desde Ajustes › Enviar feedback. Estos son los temas que sí cubre la guía.";

const puntuar = (consulta: string[], s: Seccion): number => {
    const enPalabras = new Set(s.palabras.flatMap(tokens));
    const enTitulo = new Set(tokens(s.titulo));
    const enTexto = new Set(tokens(s.texto));
    let total = 0;
    for (const t of new Set(consulta)) {
        if (enPalabras.has(t)) total += 3;
        else if (enTitulo.has(t)) total += 2;
        else if (enTexto.has(t)) total += 1;
    }
    return total;
};

/** Las secciones que mejor casan con `tema` (máx. `MAX_SECCIONES`) o, si ninguna llega al umbral, la lista de temas. */
export const buscar = (tema: string, guia: Seccion[] = GUIA): Resultado => {
    const consulta = tokens(tema);
    const puntuadas = guia.map((s, i) => ({ s, i, p: puntuar(consulta, s) })).filter((x) => x.p >= UMBRAL);
    if (puntuadas.length === 0) {
        return { secciones: [], temas: guia.map((s) => s.titulo), aviso: AVISO_SIN_COINCIDENCIA };
    }
    puntuadas.sort((a, b) => b.p - a.p || a.i - b.i);
    const mejor = puntuadas[0].p;
    return {
        secciones: puntuadas.filter((x) => x.p >= mejor * FRACCION_MEJOR).slice(0, MAX_SECCIONES).map((x) => x.s),
    };
};
