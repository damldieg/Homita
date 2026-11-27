// aceptar_menu: acepta un borrador (la persona lo ve como menú de la semana y la Compra se genera sola). Es la única
// herramienta destructiva: se anota con `destructiveHint: true` y su descripción exige un sí EXPLÍCITO de la persona en
// esta conversación (el servidor no ve la conversación: es el mecanismo decidido en la fase 0).
//
// Seguridad (el servidor NO comprueba conflictos al aceptar, solo la revisión): antes de aceptar se hace la comprobación
// completa (`check_meal_plan` + regla de «sin comprobar» con dieta o alergias) en esta misma invocación; con conflictos
// no se acepta. `expected_revision` cubre los cambios del propio plan entre la comprobación y el accept (409). Los
// cambios ajenos al plan (una receta editada, una alergia nueva) no suben la revisión: por eso, tras aceptar, se vuelve
// a comprobar y, si apareciera algo, se acepta igualmente (no hay deshacer) pero se AVISA. Riesgo residual declarado.
import { McpServer, z } from "../../deps.ts";
import { evaluar } from "../../../_shared/homita/conflictos.ts";
import { verCompra } from "../../../_shared/homita/compra.ts";
import { arr, entero, leerPlan, obj } from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import { textoDeEscritura } from "../../errores.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_ESCRITURA, AVISO_DATOS, campoHogar, campoZona, escribirEnHogar } from "../comun.ts";
import type { EscrituraCtx } from "../comun.ts";
import { planMcp } from "./plan_mcp.ts";
import { conPlanVigente, planPorId } from "./plan_vigente.ts";

const noAceptado = (motivo: string, texto: string, extra: Obj = {}): Obj => ({ aceptado: false, motivo, error: texto, ...extra });

/** Resumen de la Compra tras aceptar: lo que ha generado el menú (`shopping_sync`) y sus artículos pendientes. */
const resumenCompra = async (ctx: EscrituraCtx, sync: unknown): Promise<Obj> => {
    const s = obj(sync);
    const sincronizacion = { añadidos: s.added ?? 0, actualizados: s.updated ?? 0, quitados: s.removed ?? 0 };
    try {
        const compra = await verCompra({ solo_pendientes: true }, ctx);
        if (typeof compra.error === "string") throw new Error("compra");
        const delMenu = arr(compra.elementos).map(obj).filter((a) => a.de_menu === true);
        return { sincronizacion, articulos_del_menu: delMenu.length, articulos: delMenu };
    } catch {
        return { sincronizacion, aviso: "El menú se aceptó, pero no he podido leer la Compra ahora mismo: míralo con ver_compra." };
    }
};

export const aceptarMenu = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    const planId = entero(a.plan_id);
    if (planId === undefined) return { ok: false, error: "plan_id no válido (sale de leer_semana o guardar_borrador)." };
    const revisionPedida = typeof a.expected_revision === "number" && Number.isInteger(a.expected_revision) && a.expected_revision >= 0
        ? a.expected_revision
        : undefined;
    if (revisionPedida === undefined) return { ok: false, error: "expected_revision no válida: es la revision del plan que la persona acaba de ver." };
    if (typeof a.fecha !== "string") return { ok: false, error: "Falta fecha: cualquier día de la semana del plan (AAAA-MM-DD)." };

    // 1. El plan, tal como está ahora.
    const encontrado = await planPorId(ctx.leer, planId, a.fecha);
    if (encontrado === null) {
        return { ok: false, error: "No encuentro ese plan en esa semana del hogar. Usa el plan_id de leer_semana o guardar_borrador y una fecha de esa semana." };
    }
    const { plan, semana, perfil } = encontrado;
    if (plan.status === "accepted") return noAceptado("ya_aceptado", "Ese menú ya está aceptado.", { revision: plan.revision });
    if (plan.revision !== revisionPedida) {
        return noAceptado("revision_vieja", "El plan cambió desde que la persona lo vio: no lo acepto. Vuelve a mostrárselo y pídele otro sí.", {
            plan_vigente: (await conPlanVigente(ctx.leer, semana)).plan_vigente,
        });
    }
    if (arr(plan.items).length === 0) return noAceptado("sin_casillas", "El plan no tiene ninguna casilla: no hay nada que aceptar.");

    // 2. Comprobación completa justo antes de aceptar.
    const antes = await evaluar(ctx.leer, plan, perfil);
    if (antes.estado === "conflictos") {
        return noAceptado("conflictos", "El menú tiene conflictos (alergias, dietas o personas fuera): no se acepta. Corrígelos con cambiar_casillas o díselo a la persona.", { conflictos: antes.conflictos });
    }
    if (antes.estado === "sin_comprobar") {
        return noAceptado("conflictos", "Hay recetas que no se pueden comprobar (ingredientes sin catálogo) y las come alguien con dieta o alergias: no se acepta. Cámbialas por recetas con ingredientes del catálogo.", { sin_comprobar: antes.sin_comprobar });
    }
    if (antes.estado === "no_comprobado") {
        return noAceptado("no_comprobado", "No he podido comprobar el menú (alergias, dietas y personas fuera): no lo acepto sin comprobarlo. Inténtalo de nuevo.");
    }

    // 3. Aceptar con la revisión que vio la persona. Un 409 no se reintenta: la decisión era sobre otra revisión.
    const r = await ctx.escribir("POST", "meal/plan/accept", { plan_id: planId, expected_revision: revisionPedida });
    if (!r.ok) {
        if (r.status === 409) {
            return noAceptado("revision_vieja", "El plan cambió justo ahora: no se ha aceptado. Vuelve a mostrárselo a la persona y pídele otro sí.", {
                plan_vigente: (await conPlanVigente(ctx.leer, semana)).plan_vigente,
            });
        }
        if (r.status === 400) return noAceptado("no_aceptable", "El servidor no acepta ese plan (ya no es un borrador o no tiene casillas).");
        return { ok: false, error: textoDeEscritura(r.status, r.error) };
    }
    const aceptado = obj(r.data);

    // 4. Resumen de la Compra y segunda comprobación.
    const compra = await resumenCompra(ctx, aceptado.shopping_sync);
    const avisos: string[] = [];
    let despues: Awaited<ReturnType<typeof evaluar>> | null = null;
    try {
        const planDespues = await leerPlan(ctx.leer, semana);
        despues = planDespues === null ? null : await evaluar(ctx.leer, planDespues, perfil);
    } catch {
        despues = null;
    }
    if (despues === null || despues.estado === "no_comprobado") {
        avisos.push("Se aceptó, pero no he podido repetir la comprobación después: revisa el menú en la app.");
    } else if (despues.estado !== "ok") {
        avisos.push("Se aceptó, pero apareció un conflicto justo después (alguien cambió una receta o una alergia): avisa a la persona para que lo revise en la app.");
    }
    return {
        aceptado: true, plan_id: planId, semana, revision: aceptado.revision ?? null, compra,
        ...(despues !== null && despues.estado === "conflictos" ? { conflictos_tras_aceptar: despues.conflictos } : {}),
        ...(despues !== null && despues.estado === "sin_comprobar" ? { sin_comprobar_tras_aceptar: despues.sin_comprobar } : {}),
        ...(avisos.length > 0 ? { avisos } : {}),
        plan: planMcp(aceptado),
    };
};

export const registrarAceptar = (server: McpServer, env: Entorno): void => {
    server.registerTool("aceptar_menu", {
        title: "Aceptar el menú de una semana",
        description:
            `ACEPTA el menú de una semana: queda como menú de la familia y se genera la Compra. NUNCA lo llames sin un sí explícito de la persona en esta conversación, después de haberle enseñado el menú (con sus conflictos, si los hay): una frase como «sí, acéptalo». Que pida un menú no es un sí a aceptarlo. Pasa plan_id y expected_revision (la revision del menú que la persona vio) y fecha (cualquier día de esa semana, AAAA-MM-DD). Antes de aceptar comprueba el menú (alergias, dietas, personas fuera): con conflictos NO acepta y los devuelve; si el plan cambió desde que lo vio la persona (otra revision) tampoco acepta y devuelve plan_vigente. Si acepta, devuelve el resumen de la Compra generada. No se puede deshacer desde aquí. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            plan_id: z.number().int().positive().describe("Id del plan (leer_semana o guardar_borrador)."),
            expected_revision: z.number().int().nonnegative().describe("Revisión del menú que la persona acaba de ver."),
            fecha: z.string().describe("Cualquier día de la semana del plan, AAAA-MM-DD."),
        }),
        annotations: { ...ANOTACIONES_ESCRITURA, destructiveHint: true },
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => aceptarMenu(ctx, resto)));
};
