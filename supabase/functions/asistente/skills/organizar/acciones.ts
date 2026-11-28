// Registro de operaciones de la skill `organizar`, compartido por las herramientas (ejecución directa) y por
// `POST /asistente/confirmar` (ejecución tras confirmar). Las operaciones y su ejecución viven en
// `_shared/homita/organizar/acciones.ts` (las comparte el MCP); aquí quedan las frases de la tarjeta de Kito.
import type { Accion } from "./confirmacion.ts";
import { OPS_PERMITIDAS } from "./confirmacion.ts";
import { etiqueta, OPS } from "../../../_shared/homita/organizar/acciones.ts";

export { ejecutarAccion, hechoDe, OPS } from "../../../_shared/homita/organizar/acciones.ts";
export type { ResultadoAccion } from "../../../_shared/homita/organizar/acciones.ts";

// La lista blanca del token y el registro deben coincidir (se comprueba en tests).
export const opsCoinciden = (): boolean =>
    OPS_PERMITIDAS.length === Object.keys(OPS).length && OPS_PERMITIDAS.every((o) => o in OPS);

export const esBorrado = (op: string): boolean => OPS[op]?.op === "borrar";
export const esAlta = (op: string): boolean => OPS[op]?.op === "crear";

/** Frase en primera persona para la tarjeta: «Borro la lista «Compra»». */
export const fraseDe = (a: Accion): string => {
    const d = OPS[a.op];
    if (a.op === "completar_tarea") return `${a.args.completed === false ? "Marco como pendiente" : "Completo"} la tarea ${etiqueta(a)}`.trim();
    const verbo = d.op === "crear" ? "Creo" : d.op === "editar" ? "Edito" : "Borro";
    return `${verbo} ${d.art} ${etiqueta(a)}`.trim();
};

const valor = (v: unknown): string =>
    v === null || v === undefined || v === "" ? "—" : Array.isArray(v) ? (v.length ? v.join(", ") : "—") : typeof v === "string" ? `«${v}»` : String(v);

/** Frase de edición que dice qué cambia: «Edito la lista «Compra»: nombre «Compra» → «Súper»; color … → …». */
export const fraseEdicion = (prefijo: string, cambios: Array<[campo: string, antes: unknown, despues: unknown]>): string => {
    const reales = cambios.filter(([, a, d]) => d !== undefined && valor(a) !== valor(d));
    return reales.length ? `${prefijo}: ${reales.map(([c, a, d]) => `${c} ${valor(a)} → ${valor(d)}`).join("; ")}` : prefijo;
};
