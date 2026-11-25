// UUID determinista para `client_request_id` (0035: tareas y listas). El `tool_use.id` de Anthropic
// («toolu_…») no es un UUID, así que se deriva uno con SHA-256 y forma de UUID v4.

const hex = (b: Uint8Array): string => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");

/** SHA-256 de `clave` → 16 primeros bytes con bits de versión 4 y variante 10xx → 8-4-4-4-12. */
export const uuidDe = async (clave: string): Promise<string> => {
    const h = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(clave))).slice(0, 16);
    h[6] = (h[6] & 0x0f) | 0x40;
    h[8] = (h[8] & 0x3f) | 0x80;
    const s = hex(h);
    return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
};

/** Clave de idempotencia de una alta: misma petición del bucle (mismo tool_use.id) → mismo UUID. */
export const clientRequestId = (
    quien: string,
    homeId: string | null,
    toolUseId: string,
    indice = 0,
): Promise<string> => uuidDe(`${quien}|${homeId ?? ""}|${toolUseId}|${indice}`);
