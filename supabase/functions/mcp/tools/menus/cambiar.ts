// cambiar_casillas: cambia casillas concretas de un borrador. Solo toca casillas LIBRES o marcadas por la persona para
// cambiar (`rejected`); las bloqueadas (`locked`) y las ocupadas con un plato normal no se tocan (se devuelven en
// `rechazadas` con el motivo). Un plan aceptado no se edita. `expected_revision` lo envía quien llama (la revisión que
// vio): si el plan cambió desde entonces no se escribe y se devuelve el plan vigente.
import { McpServer, z } from "../../deps.ts";
import { recetasNoComprobables } from "../../../_shared/homita/conflictos.ts";
import { idCambios } from "../../../_shared/homita/idempotencia.ts";
import { arr, comensalesEn, entero, esFecha, FRANJA_ES, FRANJAS, obj, sumarDias } from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import { validarPlatos } from "../../../_shared/homita/menus-escritura.ts";
import type { Plato } from "../../../_shared/homita/menus-escritura.ts";
import { textoDeEscritura } from "../../errores.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_ESCRITURA, AVISO_DATOS, campoHogar, campoZona, escribirEnHogar } from "../comun.ts";
import type { EscrituraCtx } from "../comun.ts";
import { aPlatos, itemConRaciones, veredicto } from "./borrador.ts";
import { planMcp } from "./plan_mcp.ts";
import { conPlanVigente, planPorId } from "./plan_vigente.ts";

const MAX_CAMBIOS = 60;

const error = (texto: string, extra: Obj = {}): Obj => ({ ok: false, error: texto, ...extra });

export const cambiarCasillas = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    const planId = entero(a.plan_id);
    if (planId === undefined) return error("plan_id no válido (sale de leer_semana o guardar_borrador).");
    const revisionPedida = typeof a.expected_revision === "number" && Number.isInteger(a.expected_revision) && a.expected_revision >= 0
        ? a.expected_revision
        : undefined;
    if (revisionPedida === undefined) return error("expected_revision no válida: es la revision del plan que acabas de leer.");
    const cambios = arr(a.cambios).map(obj);
    if (cambios.length === 0) return error("cambios está vacío: pasa al menos una casilla.");
    if (cambios.length > MAX_CAMBIOS) return error(`Como máximo ${MAX_CAMBIOS} cambios.`);
    const fechas = cambios.map((c) => c.fecha);
    if (fechas.some((f) => !esFecha(f)) || cambios.some((c) => !(FRANJAS as readonly string[]).includes(String(c.franja)))) {
        return error("Cada cambio lleva fecha (AAAA-MM-DD) y franja válidas.");
    }

    const encontrado = await planPorId(ctx.leer, planId, fechas[0] as string);
    if (encontrado === null) {
        return error("No encuentro ese plan en la semana de esas fechas del hogar. Usa el plan_id de leer_semana o guardar_borrador y fechas de esa misma semana.");
    }
    const { plan, semana, perfil } = encontrado;
    const fin = sumarDias(semana, 6);
    if (fechas.some((f) => (f as string) < semana || (f as string) > fin)) {
        return error(`Todas las fechas deben estar en la semana del plan (${semana} a ${fin}); llama una vez por semana.`);
    }
    if (plan.status === "accepted") return error("Ese menú ya está aceptado: lo cambia la persona en la app, no lo toco.");
    if (plan.revision !== revisionPedida) return await conPlanVigente(ctx.leer, semana);

    const existentes = arr(plan.items).map(obj);
    const porCasilla = new Map(existentes.map((i) => [`${i.day}|${i.slot}`, i]));
    const rechazadas: { fecha: unknown; franja: unknown; motivo: string }[] = [];
    const aEscribir: { c: Obj; existente?: Obj }[] = [];
    const borrar: number[] = [];
    const vistos = new Set<string>();
    for (const c of cambios) {
        const clave = `${c.fecha}|${c.franja}`;
        const rechazar = (motivo: string) => rechazadas.push({ fecha: c.fecha, franja: c.franja, motivo });
        if (vistos.has(clave)) {
            rechazar("casilla repetida en la llamada");
            continue;
        }
        vistos.add(clave);
        const e = porCasilla.get(clave);
        if (e !== undefined && e.state === "locked") {
            rechazar("bloqueada por la persona: no se toca");
        } else if (e !== undefined && e.state !== "rejected") {
            rechazar("ocupada con un plato: solo se cambian casillas libres o marcadas para cambiar (rejected); la persona puede marcarla en la app");
        } else if (c.quitar === true) {
            if (e === undefined) rechazar("ya está libre");
            else borrar.push(e.id as number);
        } else {
            aEscribir.push({ c, existente: e });
        }
    }

    const { crudos, raciones, error: errConv } = aPlatos(aEscribir.map((x) => x.c));
    if (errConv !== undefined) return error(errConv);
    let platos: Plato[] = [];
    if (crudos.length > 0) {
        const v = validarPlatos(crudos, semana, perfil);
        if ("errores" in v) return error("Hay casillas que corregir.", { errores: v.errores });
        platos = v.platos;
        const sinCatalogo = await recetasNoComprobables(
            ctx.leer, perfil,
            platos.filter((p) => p.receta_id !== undefined).map((p) => ({
                receta_id: p.receta_id as number, donde: `casilla ${p.dia} ${FRANJA_ES[p.franja]}`,
                comen: p.personas ?? comensalesEn(perfil, p.dia, p.franja).map((x) => x.id),
            })),
        );
        if (sinCatalogo.length > 0) return error("Hay recetas que no puedo comprobar.", { errores: sinCatalogo });
    }
    const items = platos.map((p, i) => {
        const existente = aEscribir[i].existente;
        const base = itemConRaciones(p, raciones);
        // Casilla rechazada: se reemplaza el plato en la misma casilla y vuelve a estado normal.
        return existente === undefined ? base : { ...base, id: existente.id, position: existente.position, state: null };
    });
    if (items.length === 0 && borrar.length === 0) {
        return error("No se ha cambiado nada: ninguna de esas casillas se puede cambiar.", { rechazadas });
    }

    const clave = await idCambios(ctx.uid, ctx.homeId, planId, revisionPedida, { items, borrar });
    const r = await ctx.escribir("PATCH", "meal/plan/items", {
        week_start: semana, expected_revision: revisionPedida, items,
        ...(borrar.length > 0 ? { delete_ids: borrar } : {}), client_request_id: clave, origin: "kito",
    });
    if (!r.ok) {
        return r.status === 409 ? await conPlanVigente(ctx.leer, semana) : error(textoDeEscritura(r.status, r.error), { rechazadas });
    }
    const planFinal = obj(r.data);
    const p = planMcp(planFinal);
    return {
        ok: true, semana, plan_id: p.plan_id, revision: p.revision, estado_plan: p.estado, cambiadas: items.length, quitadas: borrar.length,
        casillas: p.casillas, ...(await veredicto(ctx, planFinal, perfil)), rechazadas,
    };
};

export const registrarCambiar = (server: McpServer, env: Entorno): void => {
    server.registerTool("cambiar_casillas", {
        title: "Cambiar casillas del borrador",
        description:
            `Cambia casillas concretas de un borrador (una semana por llamada). Pasa plan_id y expected_revision (la revision que acabas de leer o guardar). Solo cambia casillas libres o marcadas por la persona para cambiar (estado rejected); NO toca las bloqueadas (locked) ni las que ya tienen un plato: esas vuelven en \`rechazadas\` con el motivo. Con quitar: true vacía una casilla rechazada. No sirve con un menú ya aceptado. Si el plan cambió desde que lo viste (otra revisión), no escribe y devuelve plan_vigente: vuelve a mostrárselo a la persona antes de repetir. Después comprueba alergias, dietas y personas fuera y devuelve los conflictos. Las recetas o platos de fuera se guardan antes con guardar_receta. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            plan_id: z.number().int().positive().describe("Id del plan (leer_semana o guardar_borrador)."),
            expected_revision: z.number().int().nonnegative().describe("Revisión del plan que acabas de leer."),
            cambios: z.array(z.object({
                fecha: z.string().describe("AAAA-MM-DD, dentro de la semana del plan."),
                franja: z.enum(FRANJAS),
                tipo: z.enum(["receta", "texto", "sobras", "fuera"]).optional(),
                receta_id: z.number().int().positive().optional(),
                titulo: z.string().optional().describe("Obligatorio si el tipo es texto."),
                raciones: z.number().int().positive().optional(),
                personas: z.array(z.number().int().positive()).optional(),
                quitar: z.boolean().optional().describe("true: vacía una casilla rechazada en vez de cambiarla."),
            })).describe("Casillas a cambiar."),
        }),
        annotations: ANOTACIONES_ESCRITURA,
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => cambiarCasillas(ctx, resto)));
};
