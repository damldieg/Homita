// Adaptadores puros del contrato PHP (sin I/O): serialización JSON, filtros de ModelAbstract y
// parsers de body de ControllerAbstract (semántica pinneada con php -r).

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

// ── ControllerAbstract: body + $_GET con precedencia del body (ControllerAbstract.php:27) ──

export type PhpInput = Record<string, unknown>;

export const phpInput = async (req: Request): Promise<PhpInput> => {
    const q: PhpInput = {};
    for (const [k, v] of new URL(req.url).searchParams) q[k] = v;
    // PHP: json_decode(file_get_contents('php://input')) (ControllerAbstract.php:25-29). Nota: el
    // runtime descarta el body de GET/HEAD (fetch spec, req.body === null): en GET solo llega el
    // query — desviación documentada (contract-inventory desviación 9, R1-03).
    const raw = await req.text().catch(() => "");
    let body: unknown = null;
    try {
        body = raw ? JSON.parse(raw) : null;
    } catch {
        body = null;
    }
    const b: PhpInput = body !== null && typeof body === "object" && !Array.isArray(body) ? body : {};
    return { ...q, ...b };
};

export const getInput = (input: PhpInput, key: string): unknown => (key in input ? input[key] : null);

// getInputString: solo strings (sin trim)
export const inputString = (input: PhpInput, key: string, dflt: string | null = null): string | null =>
    typeof getInput(input, key) === "string" ? (getInput(input, key) as string) : dflt;

// getInputInt: int JSON o string /^[0-9]+$/; el resto → default
export const inputInt = (input: PhpInput, key: string, dflt: number | null = null): number | null => {
    const v = getInput(input, key);
    if (typeof v === "number" && Number.isInteger(v)) return v;
    if (typeof v === "string" && /^[0-9]+$/.test(v)) return parseInt(v, 10);
    return dflt;
};

// getInputDateHour: 'YYYY-MM-DD HH:MM:SS' o default
export const inputDateHour = (input: PhpInput, key: string, dflt: string | null = null): string | null => {
    const v = inputString(input, key);
    if (v === null || v === "") return dflt;
    return /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(v) ? v : dflt;
};

// filter_var(FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) (pinneado con php -r):
// true/1/"1"/"true"/"on"/"yes" → true; false/0/"0"/"false"/"off"/"no"/"" → false; resto → null
export const filterBool = (v: unknown): boolean | null => {
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v === 1 ? true : v === 0 ? false : null;
    if (typeof v === "string") return phpBool(v);
    return null;
};

// getInputBool: null (ausente/JSON null) → default; resto filter_var ?? default
export const inputBool = (input: PhpInput, key: string, dflt: boolean | null = null): boolean | null => {
    const v = getInput(input, key);
    if (v === null) return dflt;
    return filterBool(v) ?? dflt;
};

// getInputEmail: string truthy → trim ('' y '0' → default)
export const inputEmail = (input: PhpInput, key: string, dflt: string | null = null): string | null => {
    const v = inputString(input, key);
    return v && v !== "0" ? v.trim() : dflt;
};

// empty() de PHP sobre los valores de getInput* (null, false, 0, "", "0" → true)
export const phpEmpty = (v: unknown): boolean =>
    v === null || v === undefined || v === false || v === 0 || v === "" || v === "0";

// intval() de PHP (TaskOrder.php:18)
export const phpIntval = (v: unknown): number => {
    if (typeof v === "number") return Math.trunc(v);
    if (typeof v === "boolean") return v ? 1 : 0;
    if (typeof v === "string") {
        const m = v.trim().match(/^[+-]?\d+/);
        return m ? parseInt(m[0], 10) : 0;
    }
    return 0;
};

// getInputTimezone (ControllerAbstract.php:94-98): default 'UTC'; no string o IANA inválido →
// error 'Invalid timezone' (lo lanzan los handlers con errInvalidTimezone)
export const inputTimezone = (input: PhpInput): string | "INVALID" => {
    const tz = "timezone" in input ? input.timezone : "UTC";
    if (typeof tz !== "string") return "INVALID";
    try {
        new Intl.DateTimeFormat("en-US", { timeZone: tz });
        return tz;
    } catch {
        return "INVALID";
    }
};
