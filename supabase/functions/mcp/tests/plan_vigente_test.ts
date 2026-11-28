import { assertEquals } from "jsr:@std/assert@1";
import { conPlanVigente, planPorId } from "../tools/menus/plan_vigente.ts";
import type { Leer } from "../../_shared/homita/tipos.ts";

const PLAN = { id: 5, status: "draft", revision: 4, origin: "kito", week_start: "2030-01-07", items: [], unchecked_item_ids: [] };
const lector = (r: Record<string, unknown>): Leer => (ruta) => Promise.resolve(r[ruta]);

Deno.test("conPlanVigente: error con revisión vieja y el plan releído compacto", async () => {
    const r = await conPlanVigente(lector({ "meal/plan": PLAN }), "2030-01-07");
    assertEquals(r.ok, false);
    assertEquals(r.revision_vieja, true);
    assertEquals(typeof r.error, "string");
    assertEquals((r.plan_vigente as Record<string, unknown>).revision, 4);
    assertEquals((r.plan_vigente as Record<string, unknown>).plan_id, 5);
});

Deno.test("conPlanVigente: si la relectura falla, plan_vigente es null pero sigue siendo error", async () => {
    const roto: Leer = () => Promise.reject(new Error("x"));
    const r = await conPlanVigente(roto, "2030-01-07");
    assertEquals(r.plan_vigente, null);
    assertEquals(typeof r.error, "string");
});

Deno.test("planPorId: resuelve por la semana de la fecha y verifica el id", async () => {
    const leer = lector({ "meal/profile": { profile: { week_start_day: 1 } }, "meal/plan": PLAN });
    const ok = await planPorId(leer, 5, "2030-01-10");
    assertEquals(ok?.semana, "2030-01-07");
    assertEquals(await planPorId(leer, 6, "2030-01-10"), null);
    assertEquals(await planPorId(lector({ "meal/profile": { profile: {} }, "meal/plan": null }), 5, "2030-01-10"), null);
});
