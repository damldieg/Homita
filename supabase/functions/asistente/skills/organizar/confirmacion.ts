// Confirmaciones firmadas de la skill `organizar`. Una acción peligrosa (borrar, o tocar varios elementos en
// una petición) no se ejecuta: se devuelve una tarjeta con un token que la app envía a
// `POST /asistente/confirmar`. Token = base64url(payload) + "." + base64url(HMAC-SHA256(payload)).
// La verificación calcula el HMAC sobre los bytes recibidos (no re-serializa) y después valida el contenido.

import type { Accion } from "../../../_shared/homita/organizar/tipos.ts";
export type { Accion }; // el tipo vive en el módulo compartido con el MCP

/** Operaciones que se pueden confirmar (lista blanca). Las define `acciones.ts`; aquí solo se comprueba el nombre. */
export const OPS_PERMITIDAS = [
    "crear_lista", "editar_lista", "borrar_lista",
    "crear_tarea", "editar_tarea", "completar_tarea", "borrar_tarea",
    "crear_evento", "editar_evento", "borrar_evento",
    "crear_rutina", "editar_rutina", "borrar_rutina",
    "crear_calendario", "editar_calendario", "borrar_calendario",
] as const;

export const MAX_ACCIONES = 20;
export const TTL_SEGUNDOS = 120;

/** Secreto de firma normalizado: sin espacios en los extremos; vacío = no configurado. Único punto de lectura. */
export const secretoDe = (env: (k: string) => string | undefined): string | undefined =>
    ((env("KITO_CONFIRM_SECRET") ?? "").trim()) || undefined;

type Obj = Record<string, unknown>;

export interface Payload {
    v: 1;
    uid: string;
    home_id: string;
    /** Caducidad, en segundos desde epoch. */
    exp: number;
    acciones: Accion[];
}

/** JSON determinista: claves de objeto ordenadas recursivamente, sin `undefined`. */
export const canonico = (valor: unknown): string => {
    const orden = (v: unknown): unknown => {
        if (Array.isArray(v)) return v.map(orden);
        if (v !== null && typeof v === "object") {
            const o = v as Obj;
            const r: Obj = {};
            for (const k of Object.keys(o).sort()) if (o[k] !== undefined) r[k] = orden(o[k]);
            return r;
        }
        return v;
    };
    return JSON.stringify(orden(valor));
};

const aB64Url = (b: Uint8Array): string => {
    let s = "";
    for (const x of b) s += String.fromCharCode(x);
    return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
};

const deB64Url = (t: string): Uint8Array<ArrayBuffer> | null => {
    if (!/^[A-Za-z0-9_-]*$/.test(t)) return null;
    try {
        const s = atob(t.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (t.length % 4)) % 4));
        return Uint8Array.from(s, (c) => c.charCodeAt(0)) as Uint8Array<ArrayBuffer>;
    } catch {
        return null;
    }
};

const clave = (secreto: string): Promise<CryptoKey> =>
    crypto.subtle.importKey("raw", new TextEncoder().encode(secreto), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);

/** Firma el payload (JSON canónico) y devuelve el token. */
export const firmar = async (payload: Payload, secreto: string): Promise<string> => {
    const bytes = new TextEncoder().encode(canonico(payload));
    const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await clave(secreto), bytes));
    return `${aB64Url(bytes)}.${aB64Url(sig)}`;
};

export type Verificacion = { ok: true; payload: Payload } | { ok: false; motivo: string };

export interface Esperado {
    uid: string;
    homeId: string;
    /** Instante actual en ms. */
    ahora: number;
}

const esObjeto = (v: unknown): v is Obj => v !== null && typeof v === "object" && !Array.isArray(v);

/** Verifica firma, caducidad, uid, hogar y que las acciones sean de la lista blanca. Nunca lanza. */
export const verificar = async (token: unknown, secreto: string, esperado: Esperado): Promise<Verificacion> => {
    if (typeof token !== "string") return { ok: false, motivo: "token mal formado" };
    const partes = token.split(".");
    if (partes.length !== 2) return { ok: false, motivo: "token mal formado" };
    const bytes = deB64Url(partes[0]);
    const sig = deB64Url(partes[1]);
    if (bytes === null || sig === null || bytes.length === 0) return { ok: false, motivo: "token mal formado" };
    let firmaOk = false;
    try {
        firmaOk = await crypto.subtle.verify("HMAC", await clave(secreto), sig, bytes);
    } catch {
        firmaOk = false;
    }
    if (!firmaOk) return { ok: false, motivo: "firma no válida" };
    let p: unknown;
    try {
        p = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
        return { ok: false, motivo: "token mal formado" };
    }
    if (!esObjeto(p) || p.v !== 1 || typeof p.uid !== "string" || typeof p.home_id !== "string" ||
        typeof p.exp !== "number" || !Array.isArray(p.acciones)) {
        return { ok: false, motivo: "token mal formado" };
    }
    if (p.exp * 1000 <= esperado.ahora) return { ok: false, motivo: "token caducado" };
    if (p.uid !== esperado.uid) return { ok: false, motivo: "token de otro usuario" };
    if (p.home_id !== esperado.homeId) return { ok: false, motivo: "token de otro hogar" };
    if (p.acciones.length === 0 || p.acciones.length > MAX_ACCIONES) return { ok: false, motivo: "número de acciones no válido" };
    const permitidas: readonly string[] = OPS_PERMITIDAS;
    for (const a of p.acciones) {
        if (!esObjeto(a) || typeof a.op !== "string" || !permitidas.includes(a.op) || !esObjeto(a.args) ||
            (a.nombre !== undefined && typeof a.nombre !== "string")) {
            return { ok: false, motivo: "acción no permitida" };
        }
    }
    return { ok: true, payload: p as unknown as Payload };
};
