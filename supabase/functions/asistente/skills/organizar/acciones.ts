// Registro de operaciones de la skill `organizar`, compartido por las herramientas (ejecución directa) y por
// `POST /asistente/confirmar` (ejecución tras confirmar). Una acción = {op, args}: `args` es el cuerpo que
// recibe el caso de uso del `api` (más claves propias de las altas compuestas, ver `ejecutarAccion`).
import type { Cambio, Escribir } from "../../core.ts";
import type { Accion } from "./confirmacion.ts";
import { OPS_PERMITIDAS } from "./confirmacion.ts";
import { esNoExiste, traducir } from "./errores.ts";

type Obj = Record<string, unknown>;

interface OpDef {
    tipo: Cambio["tipo"];
    op: Cambio["op"];
    metodo: "POST" | "PATCH" | "DELETE";
    ruta: string;
    /** «la lista», «el evento»… */
    art: string;
    fem: boolean;
}

const def = (tipo: Cambio["tipo"], op: Cambio["op"], metodo: OpDef["metodo"], ruta: string, art: string, fem: boolean): OpDef =>
    ({ tipo, op, metodo, ruta, art, fem });

export const OPS: Record<string, OpDef> = {
    crear_lista: def("lista", "crear", "POST", "task-list/create", "la lista", true),
    editar_lista: def("lista", "editar", "PATCH", "task-list/update", "la lista", true),
    borrar_lista: def("lista", "borrar", "DELETE", "task-list/delete", "la lista", true),
    crear_tarea: def("tarea", "crear", "POST", "task/create", "la tarea", true),
    editar_tarea: def("tarea", "editar", "PATCH", "task/update", "la tarea", true),
    completar_tarea: def("tarea", "editar", "PATCH", "task/complete", "la tarea", true),
    borrar_tarea: def("tarea", "borrar", "DELETE", "task/delete", "la tarea", true),
    crear_evento: def("evento", "crear", "POST", "event/create", "el evento", false),
    editar_evento: def("evento", "editar", "PATCH", "event/update", "el evento", false),
    borrar_evento: def("evento", "borrar", "DELETE", "event/delete", "el evento", false),
    crear_rutina: def("rutina", "crear", "POST", "routine/create", "la rutina", true),
    editar_rutina: def("rutina", "editar", "PATCH", "routine/update", "la rutina", true),
    borrar_rutina: def("rutina", "borrar", "DELETE", "routine/delete", "la rutina", true),
    crear_calendario: def("calendario", "crear", "POST", "calendar/create", "el calendario", false),
    editar_calendario: def("calendario", "editar", "PATCH", "calendar/update", "el calendario", false),
    borrar_calendario: def("calendario", "borrar", "DELETE", "calendar/delete", "el calendario", false),
};

// La lista blanca del token y el registro deben coincidir (se comprueba en tests).
export const opsCoinciden = (): boolean =>
    OPS_PERMITIDAS.length === Object.keys(OPS).length && OPS_PERMITIDAS.every((o) => o in OPS);

export const esBorrado = (op: string): boolean => OPS[op]?.op === "borrar";
export const esAlta = (op: string): boolean => OPS[op]?.op === "crear";

const etiqueta = (a: Accion): string => {
    const e = a.args.title ?? a.args.name ?? a.nombre;
    return typeof e === "string" && e !== "" ? `«${e}»` : "";
};

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

/** Frase de lo hecho: «Borrada la lista «Compra»». */
export const hechoDe = (a: Accion): string => {
    const d = OPS[a.op];
    if (a.op === "completar_tarea") return `Tarea ${etiqueta(a)} ${a.args.completed === false ? "marcada como pendiente" : "completada"}`.replace("  ", " ");
    const participio = d.op === "crear" ? "Cread" : d.op === "editar" ? "Editad" : "Borrad";
    return `${participio}${d.fem ? "a" : "o"} ${d.art} ${etiqueta(a)}`.trim();
};

export interface ResultadoAccion {
    ok: boolean;
    /** Borrado de algo que ya no existía: se da por hecho. */
    yaEstaba?: boolean;
    id: number | string | null;
    cambios: Cambio[];
    /** Frase de lo hecho (o del error si `ok` es false). */
    texto: string;
    /** Fallos parciales de una alta compuesta (fecha límite, compartir). */
    avisos: string[];
}

const idDe = (data: unknown): number | string | null => {
    const id = data !== null && typeof data === "object" ? (data as { id?: unknown }).id : undefined;
    return typeof id === "number" || typeof id === "string" ? id : null;
};

const idDeArgs = (v: unknown): number | string | null => (typeof v === "number" || typeof v === "string" ? v : null);

/**
 * Ejecuta una acción con el escritor. Las altas compuestas llevan claves propias en `args`:
 * `due_at` (crear_tarea: se fija tras crear, porque el alta no la admite) y `compartir`
 * (crear_calendario: [{user_id, can_edit, nombre}], se aplica tras crear con PATCH /calendar/user).
 * Los fallos de esos pasos extra no deshacen el alta: salen en `avisos`.
 */
export const ejecutarAccion = async (esc: Escribir, a: Accion): Promise<ResultadoAccion> => {
    const d = OPS[a.op];
    if (!d) return { ok: false, id: null, cambios: [], texto: "Acción no permitida.", avisos: [] };
    // Claves propias de las altas compuestas: no van al caso de uso de alta.
    const compuesta = a.op === "crear_tarea" || a.op === "crear_calendario";
    const { due_at: dueAt, compartir, ...sinExtras } = a.args;
    const cuerpo = compuesta ? sinExtras : a.args;
    const r = await esc(d.metodo, d.ruta, cuerpo);
    if (!r.ok) {
        if (d.op === "borrar" && esNoExiste(r.status, r.error)) {
            return { ok: true, yaEstaba: true, id: idDeArgs(a.args.id), cambios: [], texto: `Ya estaba hecho: ${d.art} ${etiqueta(a)} ya no existe`.replace("  ", " "), avisos: [] };
        }
        return { ok: false, id: null, cambios: [], texto: traducir(r.status, r.error, a.nombre), avisos: [] };
    }
    const id = d.op === "crear" ? idDe(r.data) : idDeArgs(a.args.id);
    const avisos: string[] = [];
    if (a.op === "crear_tarea" && typeof dueAt === "string" && id !== null) {
        const u = await esc("PATCH", "task/update", { id, title: a.args.title, due_at: dueAt });
        if (!u.ok) avisos.push(`La tarea está creada, pero no he podido ponerle la fecha límite: ${traducir(u.status, u.error, a.nombre)}`);
    }
    if (a.op === "crear_calendario" && Array.isArray(compartir) && id !== null) {
        for (const c of compartir as Obj[]) {
            const nombre = typeof c.nombre === "string" ? c.nombre : "esa persona";
            const u = await esc("PATCH", "calendar/user", { calendar_id: id, user_id: c.user_id, can_edit: c.can_edit === true });
            if (!u.ok) {
                avisos.push(u.status === 403
                    ? `No he podido compartirlo con ${nombre}: solo el propietario puede compartir, y esa persona debe ser del hogar.`
                    : `No he podido compartirlo con ${nombre}: ${traducir(u.status, u.error, a.nombre)}`);
            }
        }
    }
    return { ok: true, id, cambios: [{ tipo: d.tipo, id, op: d.op }], texto: hechoDe(a), avisos };
};
