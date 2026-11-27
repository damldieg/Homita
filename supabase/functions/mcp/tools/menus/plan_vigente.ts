// Plan de una semana y su versión vigente tras un 409. Ante una revisión vieja el MCP relee el plan y lo devuelve en el
// resultado (el brief lo pide), para que Claude vuelva a mostrárselo a la persona antes de repetir el cambio. Esto vive
// solo en el MCP: `errorEscritura` de Kito no relee (cambiarlo sería cambiar su comportamiento).
import { compactarPlan } from "../../../_shared/homita/plan.ts";
import { diaInicio, inicioSemana, leerPerfil, leerPlan } from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import type { Leer } from "../../../_shared/homita/tipos.ts";

/** Resultado de error con el plan vigente: lleva `error` en la raíz, así que el resultado va marcado como error. */
export const conPlanVigente = async (leer: Leer, semana: string, texto?: string): Promise<Obj> => {
    const plan = await leerPlan(leer, semana).catch(() => null);
    return {
        ok: false,
        revision_vieja: true,
        error: texto ?? "El plan cambió desde que lo viste: vuelve a mostrárselo a la persona antes de repetir el cambio.",
        plan_vigente: plan === null ? null : compactarPlan(plan),
    };
};

/**
 * Plan por `plan_id`. `GET meal/plan` solo admite la semana, así que se resuelve por la semana de `fecha` y se verifica
 * que el plan sea ese: un `plan_id` de otro hogar o de otra semana no coincide y da `null`.
 */
export const planPorId = async (
    leer: Leer, planId: number, fecha: string,
): Promise<{ plan: Obj; semana: string; perfil: Obj } | null> => {
    const perfil = await leerPerfil(leer);
    const semana = inicioSemana(fecha, diaInicio(perfil));
    const plan = await leerPlan(leer, semana);
    if (plan === null || plan.id !== planId) return null;
    return { plan, semana, perfil };
};
