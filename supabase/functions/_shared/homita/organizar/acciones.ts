// Operaciones de «organizar» y su ejecución con un escritor inyectado. La comparten Kito (ejecución directa y
// `POST /asistente/confirmar`) y el MCP. Una acción = {op, args}: `args` es el cuerpo que recibe el caso de uso
// del `api` (más claves propias de las altas compuestas, ver `ejecutarAccion`).
import type { EscribirFn } from "../escritor.ts";
import { esNoExiste, traducir } from "./errores.ts";
import type { Accion, Cambio, Obj, ResultadoAccion } from "./tipos.ts";

export type { ResultadoAccion };

export interface OpDef {
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

export const etiqueta = (a: Accion): string => {
    const e = a.args.title ?? a.args.name ?? a.nombre;
    return typeof e === "string" && e !== "" ? `«${e}»` : "";
};

/** Frase de lo hecho: «Borrada la lista «Compra»». */
export const hechoDe = (a: Accion): string => {
    const d = OPS[a.op];
    if (a.op === "completar_tarea") return `Tarea ${etiqueta(a)} ${a.args.completed === false ? "marcada como pendiente" : "completada"}`.replace("  ", " ");
    const participio = d.op === "crear" ? "Cread" : d.op === "editar" ? "Editad" : "Borrad";
    return `${participio}${d.fem ? "a" : "o"} ${d.art} ${etiqueta(a)}`.trim();
};

const idDe = (data: unknown): number | string | null => {
    const id = data !== null && typeof data === "object" ? (data as { id?: unknown }).id : undefined;
    return typeof id === "number" || typeof id === "string" ? id : null;
};

const idDeArgs = (v: unknown): number | string | null => (typeof v === "number" || typeof v === "string" ? v : null);

/**
 * Da acceso a un calendario a una cuenta del hogar (`PATCH /calendar/user`: upsert, así que repetirlo solo cambia
 * el permiso). Solo el propietario puede compartir y la cuenta debe ser miembro del hogar. En fallo, `texto` es la
 * frase para el usuario («No he podido compartirlo con Lucía: …»).
 */
export const compartirCalendario = async (
    esc: EscribirFn,
    calendarioId: number | string,
    userId: unknown,
    puedeEditar: boolean,
    nombre = "esa persona",
    nombreCalendario?: string,
): Promise<{ ok: true } | { ok: false; status: number; texto: string }> => {
    const u = await esc("PATCH", "calendar/user", { calendar_id: calendarioId, user_id: userId, can_edit: puedeEditar });
    if (u.ok) return { ok: true };
    return {
        ok: false,
        status: u.status,
        texto: u.status === 403
            ? `No he podido compartirlo con ${nombre}: solo el propietario puede compartir, y esa persona debe ser del hogar.`
            : `No he podido compartirlo con ${nombre}: ${traducir(u.status, u.error, nombreCalendario)}`,
    };
};

/**
 * Ejecuta una acción con el escritor. Las altas compuestas llevan claves propias en `args`:
 * `due_at` (crear_tarea: se fija tras crear, porque el alta no la admite) y `compartir`
 * (crear_calendario: [{user_id, can_edit, nombre}], se aplica tras crear con PATCH /calendar/user).
 * Los fallos de esos pasos extra no deshacen el alta: salen en `avisos`.
 */
export const ejecutarAccion = async (esc: EscribirFn, a: Accion): Promise<ResultadoAccion> => {
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
            const u = await compartirCalendario(esc, id, c.user_id, c.can_edit === true, nombre, a.nombre);
            if (!u.ok) avisos.push(u.texto);
        }
    }
    return { ok: true, id, cambios: [{ tipo: d.tipo, id, op: d.op }], texto: hechoDe(a), avisos };
};
