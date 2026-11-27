// Utilidades de la skill `menus`. La parte de lectura (argumentos, fechas de semana, rangos, lectores del perfil y del
// plan) vive en `_shared/homita/menus.ts`, compartida con el MCP, y aquí se reexporta con los mismos nombres. Aquí
// se queda lo que depende de `ToolCtx` y la parte de escritura (`escribirDe`, `errorEscritura`). Sin dependencias de `api`.
import type { Escribir, Leer, RespuestaApi, ToolCtx } from "../../core.ts";
import type { Tool } from "../../core.ts";
import {
    leerPerfil as leerPerfilDe, leerPlan as leerPlanDe, recetaComprobable as recetaComprobableDe,
} from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";

export {
    arr, AVISO_SIN_CATALOGO, comensalesEn, diaInicio, diaNombre, entero, ERROR_LECTURA, esFecha, FRANJA_ES, FRANJAS, inicioSemana,
    isoDow, MAX_DIAS_RANGO, norm, obj, resolverRango, restringidos, str, sumarDias,
} from "../../../_shared/homita/menus.ts";
export type {
    CasillaRango, Input, Obj, PuntoRango, SemanaRango,
} from "../../../_shared/homita/menus.ts";

export const leerDe = (ctx: ToolCtx): Leer => {
    if (!ctx.leer) throw new Error("lectura de datos no disponible");
    return ctx.leer;
};
export const escribirDe = (ctx: ToolCtx): Escribir => {
    if (!ctx.escribir) throw new Error("escritura de datos no disponible");
    return ctx.escribir;
};

/** Esquema de entrada de una herramienta: sin propiedades extra y sin uniones con null (strict se desactiva). */
export const esquema = (properties: Record<string, unknown>, required: string[] = []): Tool["input_schema"] =>
    ({ type: "object", properties, required, additionalProperties: false });

/** Respuesta de «falta algo»: no se llama al api y Kito lo pregunta. */
export const falta = (campos: string[], extra: Obj = {}): Obj => ({ falta: campos, ...extra });

/** Perfil de comidas del hogar (`GET /meal/profile`); lanza si el api devuelve un error. */
export const leerPerfil = async (ctx: ToolCtx): Promise<Obj> => await leerPerfilDe(leerDe(ctx));

/** Plan de la semana (`GET /meal/plan`): `null` si la semana no tiene plan; lanza si el api devuelve un error. */
export const leerPlan = async (ctx: ToolCtx, semana: string): Promise<Obj | null> => await leerPlanDe(leerDe(ctx), semana);

/** Frase para el modelo a partir de un error del api (sin detalles técnicos). */
export const errorEscritura = (r: RespuestaApi): Obj => {
    if (r.status === 409) {
        return { ok: false, revision_vieja: true, error: "El menú ha cambiado desde que lo leí. Léelo otra vez con leer_semana y vuelve a intentarlo." };
    }
    if (r.status === 403) return { ok: false, error: "No tienes permiso para hacer eso en el menú del hogar." };
    if (r.status === 404 || (r.status === 500 && r.error === "Not Found")) return { ok: false, error: "Ya no existe." };
    if (r.status === 400) {
        const motivo = typeof r.error === "string" && r.error.trim() !== "" ? r.error.trim().slice(0, 160) : "datos no válidos";
        return { ok: false, error: `No se ha podido guardar: ${motivo}.` };
    }
    return { ok: false, error: "No he podido guardarlo ahora mismo." };
};

/** Receta comprobable (ver `_shared/homita/menus.ts`); si no hay lector, se trata como no comprobable (falla cerrado). */
export const recetaComprobable = async (ctx: ToolCtx, id: unknown): Promise<boolean> => {
    try {
        return await recetaComprobableDe(leerDe(ctx), id);
    } catch {
        return false;
    }
};
