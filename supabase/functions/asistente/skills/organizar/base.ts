// Base de las herramientas de la skill `organizar`: lectura de argumentos, validación de «falta» y la
// decisión de qué hacer con una escritura (ejecutar al momento, dejarla pendiente de confirmar o negarla).
//
// Regla: crear o editar un solo elemento se ejecuta al momento. Borrar siempre, y cualquier escritura que no
// sea la única de la petición, se deja en una única tarjeta `confirmacion` con todas las acciones pendientes.
// Sin secreto de firma no se puede confirmar: los borrados se niegan y las altas siguen ejecutándose.
import { AsyncLocalStorage } from "node:async_hooks";
import { conEfectos } from "../../core.ts";
import type { Leer, Tool, ToolCtx } from "../../core.ts";
import { ejecutarAccion, esAlta, esBorrado, fraseDe } from "./acciones.ts";
import { esNoExiste, traducir } from "./errores.ts";
import { firmar, MAX_ACCIONES, TTL_SEGUNDOS } from "./confirmacion.ts";
import type { Accion } from "./confirmacion.ts";

export type Input = Record<string, unknown>;
export type Obj = Record<string, unknown>;

// ── Lectura de argumentos ──

export const texto = (i: Input, k: string): string | undefined => {
    const v = i[k];
    return typeof v === "string" && v.trim() !== "" ? v.trim() : undefined;
};
export const entero = (i: Input, k: string): number | undefined => {
    const v = i[k];
    if (typeof v === "number" && Number.isInteger(v) && v > 0) return v;
    if (typeof v === "string" && /^[1-9]\d{0,17}$/.test(v.trim())) return Number(v.trim());
    return undefined;
};
export const enteroNoNeg = (i: Input, k: string): number | undefined => {
    const v = i[k];
    return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : undefined;
};
export const booleano = (i: Input, k: string): boolean | undefined => (typeof i[k] === "boolean" ? i[k] as boolean : undefined);
export const lista = (i: Input, k: string): unknown[] | undefined => (Array.isArray(i[k]) ? i[k] as unknown[] : undefined);
/** Ids enteros positivos; `null` si algún elemento no lo es. */
export const ids = (i: Input, k: string): number[] | null | undefined => {
    const l = lista(i, k);
    if (l === undefined) return undefined;
    const r = l.filter((x): x is number => typeof x === "number" && Number.isInteger(x) && x > 0);
    return r.length === l.length ? [...new Set(r)] : null;
};

export const objeto = (v: unknown): Obj => (v !== null && typeof v === "object" ? v as Obj : {});

/** Respuesta de «falta algo»: no se llama al api y Kito lo pregunta. */
export const falta = (campos: string[], extra: Obj = {}): Obj => ({ falta: campos, ...extra });

/** Lista del api, o null si el lector devolvió un error o una forma inesperada. */
export const filas = async (leer: Leer | undefined, ruta: string): Promise<Obj[] | null> => {
    if (!leer) return null;
    const r = await leer(ruta);
    return Array.isArray(r) ? r.filter((x): x is Obj => x !== null && typeof x === "object") : null;
};

export const NO_PUEDO_BORRAR = "No puedo borrar desde aquí ahora mismo.";
export const NO_PUEDO_VARIOS = "No puedo hacer varios cambios a la vez desde aquí ahora mismo; pídemelos de uno en uno.";
export const PROPUESTA = "propuesta enviada al usuario para confirmar";

// ── Estado de la petición ──

interface Pendiente {
    accion: Accion;
    frase: string;
    /** Posición del tool_use en la petición: las acciones se confirman en el orden que pidió el modelo. */
    orden: number;
}

/** Posición del tool_use que se está ejecutando (varias herramientas de una vuelta corren en paralelo). */
const ejecucion = new AsyncLocalStorage<{ orden: number }>();
interface Estado {
    pendientes: Pendiente[];
    /** Escrituras ya ejecutadas en esta petición. */
    ejecutadas: number;
    tarjeta: Obj;
    /** Nº de pendientes con el que se firmó la tarjeta actual (la firma es asíncrona). */
    version: number;
}

const estados = new WeakMap<ToolCtx, Estado>();

const estadoDe = (ctx: ToolCtx): Estado => {
    let e = estados.get(ctx);
    if (!e) {
        e = { pendientes: [], ejecutadas: 0, tarjeta: { tipo: "confirmacion", id: "confirmacion" }, version: 0 };
        estados.set(ctx, e);
    }
    return e;
};

const textoTarjeta = (p: Pendiente[]): string =>
    p.length === 1 ? `¿${p[0].frase}?` : `Esto es lo que haría:\n${p.map((x) => `- ${x.frase}`).join("\n")}\n¿Lo confirmas?`;

/** Reconstruye la tarjeta con todas las acciones pendientes (mismo objeto e `id`: el núcleo la sustituye). */
const actualizarTarjeta = async (ctx: ToolCtx, e: Estado): Promise<void> => {
    const n = e.pendientes.length;
    const acciones = e.pendientes.map((p) => p.accion);
    const exp = Math.floor(ctx.now.getTime() / 1000) + TTL_SEGUNDOS;
    const token = await firmar({ v: 1, uid: ctx.uid, home_id: ctx.homeId ?? "", exp, acciones }, ctx.secretoConfirmacion!);
    if (n < e.version) return; // otra llamada más reciente ya firmó con más acciones
    e.version = n;
    Object.assign(e.tarjeta, {
        texto: textoTarjeta(e.pendientes),
        acciones,
        token,
        caduca: new Date(exp * 1000).toISOString(),
    });
};

export interface OpcionesDespacho {
    /** Frase en primera persona para la tarjeta (por defecto, `fraseDe`). */
    frase?: string;
    /** Datos extra para el modelo en el resultado de una ejecución directa (p. ej. la lista de la tarea). */
    extra?: Obj;
}

/**
 * Decide qué hacer con una escritura y lo hace. Devuelve el valor de la herramienta (con `conEfectos` si
 * hay tarjeta o cambios). No lanza por errores del api: los traduce.
 */
export const despachar = async (ctx: ToolCtx, accion: Accion, op: OpcionesDespacho = {}): Promise<unknown> => {
    if (!ctx.escribir) throw new Error("escritura de datos no disponible");
    const e = estadoDe(ctx);
    const secreto = ctx.secretoConfirmacion;
    const unica = (ctx.turno?.escrituras ?? 1) <= 1 && e.ejecutadas === 0 && e.pendientes.length === 0;

    if (esBorrado(accion.op) || (!unica && secreto)) {
        if (!secreto) return { ok: false, error: NO_PUEDO_BORRAR };
        if (e.pendientes.length >= MAX_ACCIONES) return { ok: false, error: "Son demasiadas acciones a la vez; pídemelas en grupos más pequeños." };
        e.pendientes.push({ accion, frase: op.frase ?? fraseDe(accion), orden: ejecucion.getStore()?.orden ?? e.pendientes.length });
        e.pendientes.sort((a, b) => a.orden - b.orden);
        await actualizarTarjeta(ctx, e);
        return conEfectos({ ok: true, estado: PROPUESTA, acciones_pendientes: e.pendientes.length }, { tarjeta: e.tarjeta });
    }
    if (!unica && !esAlta(accion.op)) return { ok: false, error: NO_PUEDO_VARIOS };

    const r = await ejecutarAccion(ctx.escribir, accion);
    if (!r.ok) return { ok: false, error: r.texto };
    e.ejecutadas++;
    return conEfectos(
        { ok: true, hecho: r.texto, id: r.id, ...(op.extra ?? {}), ...(r.avisos.length ? { avisos: r.avisos } : {}) },
        { cambios: r.cambios },
    );
};

/** Herramienta de escritura (marca `escritura` y desactiva `strict`: el servidor revalida todo). */
export const herramienta = (t: Omit<Tool, "escritura" | "strict">): Tool => ({
    ...t,
    escritura: true,
    strict: false,
    run: (input, ctx, extra) => ejecucion.run({ orden: extra?.orden ?? 0 }, () => t.run(input, ctx, extra)),
});

/** Esquema de entrada: indispensables en `required`; los opcionales son propiedades simples (sin uniones con null). */
export const esquema = (properties: Record<string, unknown>, required: string[] = []): Tool["input_schema"] =>
    ({ type: "object", properties, required, additionalProperties: false });

/** Una fila de una lista del api por id, o `null` si ya no existe. Lanza si no hay lector o falla la lectura. */
export const filaPorId = async (ctx: ToolCtx, ruta: string, id: number): Promise<Obj | null> => {
    const todas = await filas(ctx.leer, ruta);
    if (todas === null) throw new Error("No he podido leer los datos ahora mismo.");
    return todas.find((f) => Number(f.id) === id) ?? null;
};

export const YA_NO_EXISTE = { ok: false, error: "Ya no existe." };

/** Lee el detalle de un elemento con el escritor (GET). `null` si ya no existe; lanza ante otros fallos. */
export const detalle = async (ctx: ToolCtx, ruta: string, id: number): Promise<Obj | null> => {
    const r = await ctx.escribir!("GET", ruta, { id });
    if (r.ok) return objeto(r.data);
    if (esNoExiste(r.status, r.error)) return null;
    throw new Error(traducir(r.status, r.error));
};

/**
 * Elemento de destino (lista, calendario) de un alta: el indicado o, si solo hay uno donde se pueda escribir,
 * ese. Con varios y sin indicar, `falta` lleva las opciones para preguntar al usuario.
 */
export const resolverDestino = async (
    ctx: ToolCtx,
    ruta: string,
    singular: string,
    id: number | undefined,
): Promise<{ id: number; nombre: string } | { falta: Obj } | { error: string }> => {
    const todas = await filas(ctx.leer, ruta);
    if (todas === null) return { error: `No he podido leer tus ${singular}s ahora mismo.` };
    if (id !== undefined) {
        const x = todas.find((f) => Number(f.id) === id);
        return x ? { id, nombre: String(x.name) } : { error: "Ya no existe." };
    }
    const editables = todas.filter((f) => f.can_edit !== false);
    if (editables.length === 0) return { error: `No tienes ningún ${singular} donde puedas escribir.` };
    if (editables.length === 1) return { id: Number(editables[0].id), nombre: String(editables[0].name) };
    return { falta: falta([singular], { opciones: editables.map((f) => ({ id: f.id, nombre: f.name })) }) };
};
