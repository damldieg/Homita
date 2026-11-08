// Adaptadores puros del contrato PHP (sin I/O): serialización JSON y filtros de ModelAbstract.

export const json = (body: unknown, status = 200): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// getFilterBool de ModelAbstract: FILTER_VALIDATE_BOOLEAN con NULL_ON_FAILURE
export const phpBool = (v: string | null): boolean | null => {
    if (v === null) return null;
    const s = v.toLowerCase();
    if (s === "1" || s === "true" || s === "on" || s === "yes") return true;
    if (s === "0" || s === "false" || s === "off" || s === "no" || s === "") return false;
    return null;
};

// getFilterInt: intval sobre valor truthy; 0 o no numérico = sin filtro
export const phpInt = (v: string | null): number | null => {
    if (v === null) return null;
    const n = parseInt(v, 10);
    return n ? n : null;
};

// getFilterString: trim sobre valor truthy; vacío o '0' = sin filtro
export const phpStr = (v: string | null): string | null => {
    if (v === null || v === "" || v === "0") return null;
    const t = v.trim();
    return t === "" ? null : t;
};

// getFilterTimestamp: epoch de 10 dígitos → 'YYYY-MM-DD HH:MM:SS' en UTC
export const phpTimestamp = (v: string | null): string | null => {
    const s = phpStr(v);
    if (s === null || !/^\d{10}$/.test(s)) return null;
    return new Date(parseInt(s, 10) * 1000).toISOString().slice(0, 19).replace("T", " ");
};

// PostgREST serializa timestamps como ISO ('T' y microsegundos): se recorta al formato PHP
export const fmt = (ts: string): string => ts.replace("T", " ").slice(0, 19);
