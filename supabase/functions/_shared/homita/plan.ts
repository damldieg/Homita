// Forma compacta del plan semanal (`fn_meal_plan_json`) para el modelo; la tarjeta `menu` de la app la monta Kito.
import { arr, obj, str } from "./menus.ts";
import type { Obj } from "./menus.ts";

const compactarCasilla = (i: Obj, sinComprobar: Set<unknown>, motivos: Map<number, string>): Obj => {
    const motivo = typeof i.id === "number" ? motivos.get(i.id) : undefined;
    return {
        id: i.id,
        dia: i.day,
        franja: i.slot,
        posicion: i.position,
        tipo: i.kind,
        titulo: str(i.title, 120) ?? "",
        receta_id: i.recipe_id ?? null,
        estado: i.state ?? null,
        personas: arr(i.members),
        comprobada: !sinComprobar.has(i.id),
        ...(motivo !== undefined ? { motivo } : {}),
    };
};

/** Plan para el modelo: casillas con su estado (null | rejected | locked) y la revisión vigente. */
export const compactarPlan = (plan: Obj, motivos: Map<number, string> = new Map()): Obj => {
    const sin = new Set(arr(plan.unchecked_item_ids));
    return {
        plan_id: plan.id,
        estado: plan.status,
        revision: plan.revision,
        origen: plan.origin ?? "user",
        semana: plan.week_start,
        casillas: arr(plan.items).map(obj).map((i) => compactarCasilla(i, sin, motivos)),
        sin_comprobar: [...sin],
    };
};
