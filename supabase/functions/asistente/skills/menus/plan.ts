// Forma compacta del plan semanal (`fn_meal_plan_json`) para el modelo y para la tarjeta `menu` de la app.
// `compactarPlan` vive en el módulo compartido con el MCP; la tarjeta es solo de Kito.
import { compactarPlan } from "../../../_shared/homita/plan.ts";
import { arr, FRANJA_ES, obj } from "./util.ts";
import type { Obj } from "./util.ts";

export { compactarPlan };

/**
 * Tarjeta `menu` (solo la emite Kito con 0 conflictos). No lleva token: aceptar lo hace la app con
 * `POST /meal/plan/accept {plan_id, expected_revision: revision}`; Kito nunca acepta.
 */
export const tarjetaMenu = (plan: Obj, motivos: Map<number, string> = new Map(), id = "menu"): Obj => {
    const c = compactarPlan(plan, motivos);
    const casillas = arr(c.casillas).map(obj).map((x) => ({ ...x, franja_es: FRANJA_ES[String(x.franja)] ?? x.franja }));
    return {
        tipo: "menu",
        id,
        semana: c.semana,
        plan_id: c.plan_id,
        revision: c.revision,
        estado: c.estado,
        origen: c.origen,
        casillas,
        sin_comprobar: c.sin_comprobar,
        conflictos: 0,
    };
};
