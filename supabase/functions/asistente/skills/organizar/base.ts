// Base de las herramientas de la skill `organizar`: lectura de argumentos, validación de «falta» y la
// decisión de qué hacer con una escritura (ejecutar al momento, dejarla pendiente de confirmar o negarla).
//
// Regla: crear o editar un solo elemento se ejecuta al momento. Borrar siempre, y cualquier escritura que no
// sea la única de la petición, se deja en una única tarjeta `confirmacion` con todas las acciones pendientes.
// Sin secreto de firma no se puede confirmar: los borrados se niegan y las altas siguen ejecutándose.
import { AsyncLocalStorage } from "node:async_hooks";
import { conEfectos } from "../../core.ts";
import type { Tool, ToolCtx } from "../../core.ts";
import { ejecutarAccion, esAlta, esBorrado, fraseDe } from "./acciones.ts";
import { firmar, MAX_ACCIONES, TTL_SEGUNDOS } from "./confirmacion.ts";
import type { Accion } from "./confirmacion.ts";
import type { ClaveFn, Preparacion } from "../../../_shared/homita/organizar/tipos.ts";
import { clientRequestId } from "./uuid.ts";

import type { Obj } from "../../../_shared/homita/organizar/argumentos.ts";
export type { Input, Obj } from "../../../_shared/homita/organizar/argumentos.ts";
export {
    booleano, entero, enteroNoNeg, falta, filas, ids, lista, objeto, texto, YA_NO_EXISTE,
} from "../../../_shared/homita/organizar/argumentos.ts";

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

// Lecturas auxiliares: los mismos helpers del módulo compartido, con el `ToolCtx` de Kito (que es un `OrgCtx`).
export { detalle, filaPorId, resolverDestino } from "../../../_shared/homita/organizar/argumentos.ts";

/** Pasa una `Preparacion` del módulo compartido a Kito: una acción va a `despachar` (con su frase y extra); lo demás es el valor. */
export const ejecutar = (ctx: ToolCtx, p: Preparacion): Promise<unknown> | unknown =>
    "accion" in p ? despachar(ctx, p.accion, { frase: p.frase, extra: p.extra }) : p.valor;

/** Clave de idempotencia de Kito: depende del `tool_use.id` (no del cuerpo); sin él, no hay clave. */
export const claveDe = (ctx: ToolCtx, extra?: { toolUseId?: string }): ClaveFn =>
    () => extra?.toolUseId ? clientRequestId(ctx.appUserId ?? ctx.uid, ctx.homeId, extra.toolUseId) : undefined;
