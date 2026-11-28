// Frase de una edición que dice qué cambia (la usa la tarjeta de Kito; el MCP la ignora).
const valor = (v: unknown): string =>
    v === null || v === undefined || v === "" ? "—" : Array.isArray(v) ? (v.length ? v.join(", ") : "—") : typeof v === "string" ? `«${v}»` : String(v);

/** Frase de edición que dice qué cambia: «Edito la lista «Compra»: nombre «Compra» → «Súper»; color … → …». */
export const fraseEdicion = (prefijo: string, cambios: Array<[campo: string, antes: unknown, despues: unknown]>): string => {
    const reales = cambios.filter(([, a, d]) => d !== undefined && valor(a) !== valor(d));
    return reales.length ? `${prefijo}: ${reales.map(([c, a, d]) => `${c} ${valor(a)} → ${valor(d)}`).join("; ")}` : prefijo;
};
