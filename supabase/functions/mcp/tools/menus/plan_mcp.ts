// Forma del plan para Claude: el plan compacto compartido (`compactarPlan`) con los nombres del MCP (`fecha`, tipos
// `receta|texto|sobras|fuera`). La parte compartida no cambia: Kito sigue viendo `dia` y los tipos del api.
import { tipoMcp } from "../../../_shared/homita/menus-escritura.ts";
import { arr, obj } from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import { compactarPlan } from "../../../_shared/homita/plan.ts";

export const casillaMcp = (c: Obj): Obj => ({
    id: c.id,
    fecha: c.dia,
    franja: c.franja,
    tipo: tipoMcp(String(c.tipo)) ?? c.tipo,
    titulo: c.titulo,
    receta_id: c.receta_id,
    estado: c.estado,
    personas: c.personas,
    comprobada: c.comprobada,
});

/** Plan con casillas `{id, fecha, franja, tipo, titulo, receta_id, estado, personas, comprobada}`. */
export const planMcp = (plan: Obj): Obj => {
    const p = compactarPlan(plan);
    return { ...p, casillas: arr(p.casillas).map(obj).map(casillaMcp) };
};
