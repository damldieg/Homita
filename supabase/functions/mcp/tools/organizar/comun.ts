// Piezas comunes de las herramientas de escritura de organizar: cómo se ejecuta una `Preparacion` (D9), el flujo de
// borrado con `confirmado` (D2, D5, D8) y la clave de idempotencia de altas de tareas y listas (D3).
//
// El MCP no llama a ningún modelo: las reglas (qué falta, qué se rellena, qué cuerpo recibe el api) son las de Kito
// (`_shared/homita/organizar`); aquí solo se ejecuta con el JWT del usuario dentro de `runInHome`.
import { z } from "../../deps.ts";
import { ejecutarAccion, OPS } from "../../../_shared/homita/organizar/acciones.ts";
import { ErrorLectura } from "../../../_shared/homita/organizar/errores.ts";
import { YA_NO_EXISTE } from "../../../_shared/homita/organizar/argumentos.ts";
import type { ClaveFn, Obj, OrgCtx, Preparacion } from "../../../_shared/homita/organizar/tipos.ts";
import { idOrganizar } from "../../../_shared/homita/idempotencia.ts";
import type { ResultadoTool } from "../../errores.ts";
import { ANOTACIONES_ESCRITURA, AVISO_DATOS, campoHogar, campoZona, escribirEnHogar } from "../comun.ts";
import type { EscrituraCtx } from "../comun.ts";
import type { Entorno } from "../../entorno.ts";

export { AVISO_DATOS, campoHogar, campoZona };

/** Crear y editar no destruyen nada: `destructiveHint: false`. */
export const ANOTACIONES_ORGANIZAR = ANOTACIONES_ESCRITURA;
/** Borrar: el cliente pide aprobación al usuario (`destructiveHint`) y la herramienta exige `confirmado: true`. */
export const ANOTACIONES_BORRADO = { ...ANOTACIONES_ESCRITURA, destructiveHint: true } as const;

export const campoConfirmado = z.boolean().optional().describe(
    "Déjalo sin poner la primera vez: la herramienta no borra y te dice qué se borraría. Pásalo a true solo cuando la persona haya dicho que sí, después de contárselo.",
);

/** Aviso común de las descripciones de las herramientas de escritura de organizar. */
export const AVISO_ESCRITURA = `${AVISO_DATOS} Usa ids (de ver_*), no nombres.`;

/** Contexto de la lógica compartida a partir del de la herramienta (el lector y el escritor ya son los del usuario). */
export const orgCtx = (ctx: EscrituraCtx): OrgCtx => ({
    homeId: ctx.homeId, timezone: ctx.timezone, now: ctx.now, appUserId: ctx.appUserId, leer: ctx.leer, escribir: ctx.escribir,
});

/**
 * Clave de idempotencia de un alta (D3): hash del cuerpo resuelto + usuario + hogar + herramienta + minuto. Usa el
 * `uid` del usuario (el `appUserId` no se rellena en el MCP salvo con la opción `appUser`).
 */
export const claveOrganizar = (ctx: EscrituraCtx, herramienta: string): ClaveFn =>
(cuerpo) => idOrganizar(ctx.uid, ctx.homeId, herramienta, cuerpo, ctx.now);

/** Los fallos de lectura de la lógica compartida ya traen una frase para el usuario: salen como error de herramienta. */
const comoError = (e: unknown): Obj | null => (e instanceof ErrorLectura ? { ok: false, error: e.message } : null);

/** Prepara con la lógica compartida; un fallo de lectura se devuelve como `{ok:false, error}`, el resto se propaga. */
export const preparar = async (fn: () => Promise<Preparacion> | Preparacion): Promise<Preparacion> => {
    try {
        return await fn();
    } catch (e) {
        const r = comoError(e);
        if (r === null) throw e;
        return { valor: r };
    }
};

/**
 * Ejecuta una `Preparacion` de alta o edición. «Falta» y errores de validación salen tal cual (el `falta` es contenido
 * normal; un `error` en la raíz marca `isError`); una acción se ejecuta con `ejecutarAccion`: éxito
 * `{ok, hecho, id, ...extra, avisos?}`, fallo del api `{ok:false, error}` traducido por `traducir`.
 */
export const ejecutar = async (ctx: EscrituraCtx, p: Preparacion): Promise<Obj> => {
    if ("valor" in p) return p.valor as Obj;
    const r = await ejecutarAccion(ctx.escribir, p.accion);
    if (!r.ok) return { ok: false, error: r.texto };
    return { ok: true, hecho: r.texto, id: r.id, ...(p.extra ?? {}), ...(r.avisos.length ? { avisos: r.avisos } : {}) };
};

/**
 * Flujo de borrado (D2): sin `confirmado === true` NO se escribe y se devuelve lo que se borraría; con él se ejecuta.
 * Borrar algo que ya no existe es éxito (D8). `describir` da el texto de «se_borraria» (puede leer, p. ej. contar
 * las tareas de una lista); si falla, el aviso sigue siendo seguro porque `describir` debe dar un texto por defecto.
 */
export const borrar = async (
    ctx: EscrituraCtx,
    p: Preparacion,
    confirmado: boolean | undefined,
    describir: (extra: Obj, nombre: string) => Promise<string> | string,
): Promise<Obj> => {
    if ("valor" in p) {
        if (p.valor === YA_NO_EXISTE) return { ok: true, ya_estaba: true, hecho: "Ya estaba hecho: ya no existe." };
        return p.valor as Obj;
    }
    const nombre = p.accion.nombre ?? "";
    if (confirmado !== true) {
        return {
            ejecutado: false,
            requiere_confirmacion: true,
            se_borraria: await describir(p.extra ?? {}, nombre),
            mensaje: "No se ha borrado nada. Cuéntale a la persona lo que se borraría y pregúntale si quiere hacerlo; solo si dice que sí, vuelve a llamar con confirmado: true.",
        };
    }
    const r = await ejecutarAccion(ctx.escribir, p.accion);
    if (!r.ok) return { ok: false, error: r.texto };
    return { ok: true, ...(r.yaEstaba ? { ya_estaba: true } : {}), hecho: r.texto, id: r.id, ...(r.avisos.length ? { avisos: r.avisos } : {}) };
};

/** Frase del tipo de elemento de una operación («la lista», «el evento»). */
export const articuloDe = (op: string): string => OPS[op]?.art ?? "el elemento";

export type Manejador<A> = (ctx: EscrituraCtx, args: A) => Promise<Obj>;

/** Registra el manejo común: hogar, JWT y `runInHome`; los fallos inesperados salen como error de herramienta genérico. */
export const conHogar = <A extends { hogar?: string; timezone?: string }>(
    env: Entorno,
    fn: Manejador<Omit<A, "hogar" | "timezone">>,
    opciones: { appUser?: boolean } = {},
) =>
(args: A): Promise<ResultadoTool> => {
    const { hogar, timezone, ...resto } = args;
    return escribirEnHogar(env, { hogar, timezone }, (ctx) => fn(ctx, resto), opciones);
};
