// guardar_borrador: guarda el menú de un rango como BORRADOR (origen Kito), una semana tras otra. Solo rellena casillas
// libres: no borra nada, no toca casillas ocupadas ni `locked`, y salta las semanas aceptadas o hechas por la persona
// (con aviso). Después comprueba cada semana (alergias, dietas, personas fuera) y devuelve los conflictos por semana.
// Es el espejo del modo rango de Kito (`proponerRango`), con las mismas reglas compartidas (`_shared/homita`).
import { McpServer, z } from "../../deps.ts";
import { evaluar, recetasNoComprobables } from "../../../_shared/homita/conflictos.ts";
import { idBorrador } from "../../../_shared/homita/idempotencia.ts";
import {
    arr, comensalesEn, diaInicio, entero, esFecha, FRANJA_ES, FRANJAS, inicioSemana, leerPerfil, leerPlan, obj, resolverRango, str,
} from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import { claveCasilla, itemDe, MAX_PLATOS, tipoApi, TIPOS_MCP, validarPlatos } from "../../../_shared/homita/menus-escritura.ts";
import type { Plato, TipoMcp } from "../../../_shared/homita/menus-escritura.ts";
import { textoDeEscritura } from "../../errores.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_ESCRITURA, AVISO_DATOS, campoHogar, campoZona, escribirEnHogar } from "../comun.ts";
import type { EscrituraCtx } from "../comun.ts";
import { planMcp } from "./plan_mcp.ts";
import { conPlanVigente } from "./plan_vigente.ts";

const MAX_ERRORES = 6;

export const PUNTO = z.object({
    fecha: z.string().describe("AAAA-MM-DD, fecha local del hogar."),
    franja: z.enum(FRANJAS).describe("«esta noche» = dinner, «a mediodía» = lunch."),
});

/** Cómo sale la comprobación de un plan en el resultado de una semana. */
export const veredicto = async (ctx: EscrituraCtx, plan: Obj, perfil: Obj): Promise<Obj> => {
    const ev = await evaluar(ctx.leer, plan, perfil);
    if (ev.estado === "ok") return { conflictos: [], listo_para_aceptar: true };
    if (ev.estado === "conflictos") {
        return { conflictos: ev.conflictos, listo_para_aceptar: false, aviso: "Hay conflictos (alergias, dietas o personas fuera). Cambia esas casillas con cambiar_casillas (si están libres o rechazadas) o díselo a la persona." };
    }
    if (ev.estado === "sin_comprobar") {
        return {
            conflictos: [], sin_comprobar: ev.sin_comprobar, listo_para_aceptar: false,
            aviso: "Hay recetas que no se pueden comprobar (ingredientes sin catálogo) y las come alguien con dieta o alergias: no se puede aceptar así. Cámbialas por recetas con ingredientes del catálogo.",
        };
    }
    return { conflictos: [], listo_para_aceptar: false, aviso: "No he podido comprobar el menú (alergias, dietas y personas fuera). Vuelve a intentarlo antes de aceptarlo." };
};

/** Traduce las casillas de entrada del MCP (`fecha`, tipos en español) a las de la lógica compartida (`dia`, tipos del api). */
export const aPlatos = (lista: Obj[]): { crudos: Obj[]; raciones: Map<string, number>; error?: string } => {
    const raciones = new Map<string, number>();
    const crudos: Obj[] = [];
    for (const [i, c] of lista.entries()) {
        let tipo: string | undefined;
        if (c.tipo !== undefined) {
            if (!(c.tipo as string in TIPOS_MCP)) return { crudos, raciones, error: `casilla ${i + 1}: tipo no válido (receta, texto, sobras o fuera)` };
            tipo = tipoApi(c.tipo as TipoMcp);
        }
        if (c.raciones !== undefined) {
            const r = entero(c.raciones);
            if (r === undefined) return { crudos, raciones, error: `casilla ${i + 1}: raciones no válidas` };
            raciones.set(`${c.fecha}|${c.franja}`, r);
        }
        crudos.push({ dia: c.fecha, franja: c.franja, tipo, receta_id: c.receta_id, titulo: c.titulo, personas: c.personas });
    }
    return { crudos, raciones };
};

export const itemConRaciones = (p: Plato, raciones: Map<string, number>): Obj => {
    const r = raciones.get(`${p.dia}|${p.franja}`);
    return { ...itemDe(p), ...(r !== undefined ? { servings: r } : {}) };
};

export const guardarBorrador = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    const perfil = await leerPerfil(ctx.leer);
    const habilitadas = arr(perfil.slots).map(obj).filter((s) => s.enabled === true).map((s) => String(s.slot));
    const inicio = diaInicio(perfil);
    const res = resolverRango(a.rango, habilitadas, inicio);
    if ("error" in res) return { ok: false, error: res.error };
    const avisos = [...res.avisos];
    if (res.semanas.length === 0) return { ok: false, error: "En ese rango no hay ninguna franja que planificar.", avisos };
    const lista = arr(a.casillas).map(obj);
    if (lista.length === 0) return { ok: false, error: "casillas está vacío: pasa al menos una casilla." };
    if (lista.length > MAX_PLATOS) return { ok: false, error: `Como máximo ${MAX_PLATOS} casillas.` };
    const conv = aPlatos(lista);
    if (conv.error !== undefined) return { ok: false, error: conv.error };

    // Cada casilla debe caer en una casilla del rango; se agrupan por semana.
    const dentro = new Set(res.semanas.flatMap((w) => w.casillas.map((c) => `${c.fecha}|${c.franja}`)));
    const porSemana = new Map<string, unknown[]>();
    const fuera: string[] = [];
    conv.crudos.forEach((p, i) => {
        if (!esFecha(p.dia) || !dentro.has(`${p.dia}|${String(p.franja)}`)) {
            return void fuera.push(`casilla ${i + 1}: ${String(p.dia)} ${FRANJA_ES[String(p.franja)] ?? String(p.franja)} está fuera del rango pedido`);
        }
        const semana = inicioSemana(p.dia, inicio);
        porSemana.set(semana, [...(porSemana.get(semana) ?? []), p]);
    });
    if (fuera.length > 0) return { ok: false, error: "Hay casillas fuera del rango.", errores: fuera.slice(0, MAX_ERRORES) };
    const validados: { semana: string; platos: Plato[] }[] = [];
    const errores: string[] = [];
    for (const [semana, crudos] of porSemana) {
        const v = validarPlatos(crudos, semana, perfil);
        if ("errores" in v) errores.push(...v.errores.map((e) => `semana ${semana}: ${e}`));
        else validados.push({ semana, platos: v.platos });
    }
    if (errores.length > 0) return { ok: false, error: "Hay casillas que corregir.", errores: errores.slice(0, MAX_ERRORES) };
    const sinCatalogo = await recetasNoComprobables(
        ctx.leer, perfil,
        validados.flatMap((w) => w.platos).filter((p) => p.receta_id !== undefined).map((p) => ({
            receta_id: p.receta_id as number, donde: `casilla ${p.dia} ${FRANJA_ES[p.franja]}`,
            comen: p.personas ?? comensalesEn(perfil, p.dia, p.franja).map((c) => c.id),
        })),
    );
    if (sinCatalogo.length > 0) return { ok: false, error: "Hay recetas que no puedo comprobar.", errores: sinCatalogo };

    const orden = new Map(res.semanas.map((w, i) => [w.semana, i]));
    validados.sort((x, y) => (orden.get(x.semana) ?? 0) - (orden.get(y.semana) ?? 0));
    const semanas: Obj[] = [];
    for (const { semana, platos } of validados) {
        const aviso = (texto: string) => `Semana ${semana}: ${texto}`;
        const saltada = (motivo: string): Obj => {
            avisos.push(aviso(motivo));
            return { semana, estado: "saltada", motivo };
        };
        const plan = await leerPlan(ctx.leer, semana);
        const existentes = plan === null ? [] : arr(plan.items).map(obj);
        if (plan !== null && plan.status === "accepted") {
            semanas.push(saltada("ya está aceptada: la cambia la persona en la app, no la toco."));
            continue;
        }
        if (plan !== null && plan.origin !== "kito" && existentes.length > 0) {
            semanas.push(saltada("ya tiene un menú hecho por la persona; no lo piso."));
            continue;
        }
        const ocupadas = new Map(existentes.map((i) => [`${i.day}|${i.slot}`, i]));
        const libres = platos.filter((p) => !ocupadas.has(`${p.dia}|${p.franja}`));
        const yaEstan = platos.filter((p) => {
            const e = ocupadas.get(`${p.dia}|${p.franja}`);
            return e !== undefined && claveCasilla(e.day, e.slot, e.kind, e.recipe_id, e.title) === claveCasilla(p.dia, p.franja, p.tipo, p.receta_id, p.titulo);
        });
        const ocupadasOtras = platos.length - libres.length - yaEstan.length;
        const avisosSemana: string[] = [];
        if (ocupadasOtras > 0) {
            avisosSemana.push(`${ocupadasOtras} casilla(s) ya tenían comida o están bloqueadas y no se tocan.`);
            avisos.push(aviso(avisosSemana[0]));
        }
        let planFinal: Obj;
        let estado: "escrito" | "ya_estaba";
        if (libres.length > 0) {
            const revision = typeof plan?.revision === "number" ? plan.revision : 0;
            const items = libres.map((p) => itemConRaciones(p, conv.raciones));
            const key = await idBorrador(ctx.uid, ctx.homeId, semana, revision, items);
            const r = await ctx.escribir("PATCH", "meal/plan/items", {
                week_start: semana, expected_revision: revision, items, client_request_id: key, origin: "kito",
            });
            if (!r.ok) {
                const base = r.status === 409
                    ? await conPlanVigente(ctx.leer, semana)
                    : { error: textoDeEscritura(r.status, r.error) };
                semanas.push({ semana, estado: "fallo", ...base });
                continue;
            }
            planFinal = obj(r.data);
            estado = "escrito";
        } else if (yaEstan.length > 0 && plan !== null) {
            // Reintento tras un éxito: ya están puestas; solo se vuelve a comprobar.
            planFinal = plan;
            estado = "ya_estaba";
        } else {
            semanas.push(saltada("no quedaba ninguna casilla libre en el rango."));
            continue;
        }
        const v = await veredicto(ctx, planFinal, perfil);
        const p = planMcp(planFinal);
        semanas.push({
            semana, estado, escritas: estado === "escrito" ? libres.length : 0,
            plan_id: p.plan_id, revision: p.revision, estado_plan: p.estado, casillas: p.casillas, ...v,
            ...(avisosSemana.length > 0 ? { avisos: avisosSemana } : {}),
        });
    }
    const guardadas = semanas.some((s) => s.estado === "escrito" || s.estado === "ya_estaba");
    const valor: Obj = {
        ok: guardadas,
        semanas,
        ...(avisos.length > 0 ? { avisos } : {}),
        siguiente_paso: "Es un borrador. Enséñaselo a la persona y, solo si dice que sí de forma explícita y no hay conflictos, llama a aceptar_menu con plan_id y revision de cada semana.",
    };
    return guardadas ? valor : { ...valor, error: "No se ha guardado nada: revisa los avisos y los motivos por semana." };
};

export const registrarBorrador = (server: McpServer, env: Entorno): void => {
    server.registerTool("guardar_borrador", {
        title: "Guardar el menú como borrador",
        description:
            `Guarda como BORRADOR el menú de un rango de casillas (aunque cruce dos semanas: se guarda un plan por semana). Antes lee con leer_perfil, leer_semana y buscar_recetas (recetario e historial primero). Las recetas o platos de fuera se guardan ANTES con guardar_receta (con ingredientes) para que salga la Compra; \`texto\` es solo para cosas sueltas sin receta. Pasa \`rango\` (desde y hasta, ambos inclusive, fecha y franja: «esta noche» es dinner, «a mediodía» es lunch; conviértelo con la fecha de hoy de leer_perfil) y una casilla por día y franja con tipo receta (con receta_id), texto (con titulo), sobras o fuera (comer fuera). Solo rellena casillas libres: no borra nada, no toca lo bloqueado ni lo ya puesto, y salta las semanas ya aceptadas o hechas por la persona (con aviso). Reintentar es seguro. Devuelve por semana plan_id, revision, las casillas, los conflictos (alergias, dietas, personas fuera) y avisos; si hay conflictos o recetas sin comprobar, no se puede aceptar. Presenta el resultado como una tabla día por franja. Si está listo, pregunta a la persona; no aceptes sin su sí (aceptar_menu). ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            rango: z.object({ desde: PUNTO, hasta: PUNTO }).describe("Rango a planificar, ambos extremos inclusive."),
            casillas: z.array(z.object({
                fecha: z.string().describe("AAAA-MM-DD, dentro del rango."),
                franja: z.enum(FRANJAS),
                tipo: z.enum(["receta", "texto", "sobras", "fuera"]).optional().describe("Por defecto receta si hay receta_id y texto si no."),
                receta_id: z.number().int().positive().optional().describe("Id de una receta del recetario (buscar_recetas) o recién guardada."),
                titulo: z.string().optional().describe("Nombre del plato; obligatorio si el tipo es texto."),
                raciones: z.number().int().positive().optional(),
                personas: z.array(z.number().int().positive()).optional().describe("Ids de quienes comen; por defecto, todos los que están en casa."),
            })).describe("Una casilla por día y franja."),
        }),
        annotations: ANOTACIONES_ESCRITURA,
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => guardarBorrador(ctx, resto)));
};

