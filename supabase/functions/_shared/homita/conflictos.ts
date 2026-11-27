// Comprobación de un menú contra alergias, dietas y personas fuera de casa. Es la ÚNICA copia de la regla que protege
// al menú: la usan Kito (antes de enseñar la tarjeta) y el MCP (antes y después de aceptar). Movido sin cambios de
// lógica desde `asistente/skills/menus/menu.ts`; lo único que cambia es que recibe un `Leer` en vez de un `ToolCtx`
// y devuelve el veredicto estructurado, para que cada consumidor redacte su mensaje.
import { arr, AVISO_SIN_CATALOGO, entero, FRANJA_ES, obj, recetaComprobable, restringidos, str } from "./menus.ts";
import type { Obj } from "./menus.ts";
import type { Leer } from "./tipos.ts";

export const MAX_ERRORES = 6;

const CODIGOS: Record<string, string> = {
    allergen: "alergia", intolerance: "intolerancia", diet: "dieta", member_out: "persona fuera de casa",
};

/** `check_meal_plan` del plan: lista de conflictos, o `null` si no se pudo comprobar. */
export const comprobar = async (leer: Leer, planId: number): Promise<Obj[] | null> => {
    const r = await leer("meal/plan/check", { plan_id: String(planId) });
    return Array.isArray(r) ? r.map(obj) : null;
};

export const compactarConflictos = (conflictos: Obj[], nombres: Map<unknown, string>, titulos: Map<unknown, string>): Obj[] =>
    conflictos.slice(0, 20).map((c) => ({
        casilla: c.item_id,
        plato: titulos.get(c.item_id) ?? "",
        dia: c.day,
        franja: FRANJA_ES[String(c.slot)] ?? c.slot,
        persona: nombres.get(c.member_id) ?? "",
        tipo: CODIGOS[String(c.code)] ?? c.code,
        detalle: c.detail,
    }));

/**
 * Regla de texto libre: a quien tiene dieta o alergias no se le propone una receta con ingredientes sin enlazar al
 * catálogo (el servidor no puede comprobarla). Devuelve un error por cada receta excluida; `[]` si todo va bien.
 */
export const recetasNoComprobables = async (
    leer: Leer, perfil: Obj, recetas: { receta_id: number; donde: string; comen: number[] }[],
): Promise<string[]> => {
    const rest = restringidos(perfil);
    const errores: string[] = [];
    const cache = new Map<number, boolean>();
    for (const r of recetas) {
        if (!r.comen.some((id) => rest.has(id))) continue;
        if (!cache.has(r.receta_id)) cache.set(r.receta_id, await recetaComprobable(leer, r.receta_id));
        if (!cache.get(r.receta_id)) errores.push(`${r.donde}: la receta ${r.receta_id} tiene ingredientes sin catálogo y hay dieta o alergias; ${AVISO_SIN_CATALOGO}`);
    }
    return errores.slice(0, MAX_ERRORES);
};

/** Veredicto de la comprobación de un plan. */
export type Evaluacion =
    | { estado: "no_comprobado" }
    | { estado: "sin_comprobar"; sin_comprobar: Obj[] }
    | { estado: "conflictos"; conflictos: Obj[] }
    | { estado: "ok" };

/**
 * Comprueba el plan (`GET meal/plan/check`) y aplica la regla de «sin comprobar»: una receta que el servidor no pudo
 * comprobar (ingredientes sin catálogo) bloquea si la come alguien con dieta o alergias (falla cerrado). Texto libre y
 * sobras no bloquean. `no_comprobado`: el servidor no devolvió la lista.
 */
export const evaluar = async (leer: Leer, plan: Obj, perfil: Obj): Promise<Evaluacion> => {
    const planId = entero(plan.id);
    const conflictos = planId === undefined ? null : await comprobar(leer, planId);
    if (conflictos === null) return { estado: "no_comprobado" };
    const rest = restringidos(perfil);
    const sin = new Set(arr(plan.unchecked_item_ids));
    const sinComprobarRestringidos = arr(plan.items).map(obj).filter((i) =>
        i.kind === "recipe" && sin.has(i.id) && arr(i.members).some((n) => typeof n === "number" && rest.has(n))
    );
    if (sinComprobarRestringidos.length > 0) {
        return {
            estado: "sin_comprobar",
            sin_comprobar: sinComprobarRestringidos.slice(0, 20).map((i) => ({ casilla: i.id, plato: str(i.title, 80) ?? "", dia: i.day, franja: FRANJA_ES[String(i.slot)] ?? i.slot })),
        };
    }
    if (conflictos.length > 0) {
        const nombres = new Map(arr(perfil.members).map(obj).map((m) => [m.home_member_id, str(m.name, 80) ?? ""]));
        const titulos = new Map(arr(plan.items).map(obj).map((i) => [i.id, str(i.title, 80) ?? ""]));
        return { estado: "conflictos", conflictos: compactarConflictos(conflictos, nombres, titulos) };
    }
    return { estado: "ok" };
};
