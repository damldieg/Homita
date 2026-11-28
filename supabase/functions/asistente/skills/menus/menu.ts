// proponer_menu y reproponer: Kito guarda un BORRADOR del menú (origin kito) y, si `check_meal_plan` da 0
// conflictos, deja la tarjeta `menu`. Kito nunca acepta: la persona lo hace en la app. Idempotencia: la
// `client_request_id` sale del contenido (misma propuesta sobre la misma revisión = mismo UUID), así que un
// reintento no duplica. Concurrencia: `expected_revision` es la revisión que acaba de leer.
import { conEfectos } from "../../core.ts";
import type { Cambio, Efectos, Tool, ToolCtx } from "../../core.ts";
import {
    evaluar as evaluarPlan, MAX_ERRORES, recetasNoComprobables as recetasNoComprobablesDe,
} from "../../../_shared/homita/conflictos.ts";
import type { Leer } from "../../../_shared/homita/tipos.ts";
import {
    claveCasilla, itemDe, MAX_PLATOS, TIPOS, validarPlatos, yaCoincide,
} from "../../../_shared/homita/menus-escritura.ts";
import type { Plato } from "../../../_shared/homita/menus-escritura.ts";
import { uuidDe } from "../organizar/uuid.ts";
import { compactarPlan, tarjetaMenu } from "./plan.ts";
import {
    arr, comensalesEn, diaInicio, diaNombre, entero, errorEscritura, escribirDe, esFecha, esquema, FRANJA_ES, FRANJAS, inicioSemana, isoDow, leerDe,
    leerPerfil, leerPlan, norm, obj, resolverRango, str, sumarDias,
} from "./util.ts";
import type { Obj } from "./util.ts";

/** Lector perezoso del contexto: si no hay lector falla al usarlo (y las recetas se tratan como no comprobables). */
const lector = (ctx: ToolCtx): Leer => (ruta, params) => leerDe(ctx)(ruta, params);

/** Regla de texto libre (ver `_shared/homita/conflictos.ts`). */
const recetasNoComprobables = (
    ctx: ToolCtx, perfil: Obj, recetas: { receta_id: number; donde: string; comen: number[] }[],
): Promise<string[]> => recetasNoComprobablesDe(lector(ctx), perfil, recetas);

/**
 * Cierra una propuesta o repropuesta ya guardada: comprueba el plan y, solo con 0 conflictos, emite la tarjeta.
 * Con conflictos NO hay tarjeta: el modelo recibe cuáles son para corregirlos y volver a proponer.
 */
const cerrar = async (
    ctx: ToolCtx, plan: Obj, perfil: Obj, op: Cambio["op"], motivos: Map<number, string>, extra: Obj = {},
): Promise<unknown> => {
    const r = await evaluar(ctx, plan, perfil, op, motivos, extra);
    return r.efectos === undefined ? r.valor : conEfectos(r.valor, r.efectos);
};

/** Como `cerrar`, pero devuelve el valor para el modelo y los efectos (tarjeta, cambios) por separado. */
const evaluar = async (
    ctx: ToolCtx, plan: Obj, perfil: Obj, op: Cambio["op"], motivos: Map<number, string>, extra: Obj = {}, idTarjeta = "menu",
): Promise<{ valor: Obj; efectos?: Efectos }> => {
    const planId = entero(plan.id);
    // La regla (comprobación + bloqueo de recetas sin comprobar) vive en `_shared/homita/conflictos.ts`.
    const ev = await evaluarPlan(lector(ctx), plan, perfil);
    if (ev.estado === "no_comprobado") {
        return { valor: { ok: false, error: "No he podido comprobar el menú (alergias, dietas y personas fuera). No lo muestro hasta comprobarlo; inténtalo de nuevo." } };
    }
    if (ev.estado === "sin_comprobar") {
        return { valor: {
            ok: false,
            tarjeta: false,
            sin_comprobar: ev.sin_comprobar,
            aviso: "Hay recetas que no se han podido comprobar (ingredientes sin catálogo) y las come alguien con dieta o alergias: NO se muestra el menú. Cámbialas por recetas con ingredientes del catálogo y vuelve a proponer.",
            ...extra,
        } };
    }
    if (ev.estado === "conflictos") {
        return { valor: {
            ok: false,
            tarjeta: false,
            conflictos: ev.conflictos,
            aviso: "El menú guardado tiene conflictos y NO se muestra a la persona. Cambia esos platos y vuelve a llamar a proponer_menu (o a reproponer si ya hay casillas marcadas). Si no encuentras alternativa, explícaselo.",
            ...extra,
        } };
    }
    const resumen = compactarPlan(plan, motivos);
    return {
        valor: {
            ok: true,
            estado: "borrador guardado y tarjeta mostrada; lo acepta la persona en la app (tú no puedes aceptarlo)",
            plan_id: resumen.plan_id,
            revision: resumen.revision,
            casillas: arr(resumen.casillas).length,
            conflictos: 0,
            sin_comprobar: resumen.sin_comprobar,
            ...extra,
        },
        efectos: { tarjeta: tarjetaMenu(plan, motivos, idTarjeta), cambios: [{ tipo: "menu", id: planId ?? null, op }] },
    };
};

const ESQUEMA_PLATO = {
    type: "object",
    properties: {
        dia: { type: "string", description: "AAAA-MM-DD, dentro de la semana." },
        franja: { type: "string", enum: [...FRANJAS] },
        receta_id: { type: "integer", description: "Id de una receta del recetario (buscar_recetas) o recién guardada." },
        titulo: { type: "string", description: "Nombre del plato; obligatorio si no hay receta_id." },
        tipo: { type: "string", enum: [...TIPOS], description: "Por defecto recipe si hay receta_id y free_text si no." },
        personas: { type: "array", items: { type: "integer" }, description: "Ids de quienes comen; por defecto, todos los que están en casa." },
    },
    required: ["dia", "franja"],
    additionalProperties: false,
};

const ESQUEMA_PUNTO = {
    type: "object",
    properties: {
        fecha: { type: "string", description: "AAAA-MM-DD, fecha local del hogar." },
        franja: { type: "string", enum: [...FRANJAS], description: "«esta noche» = dinner, «a mediodía» = lunch." },
    },
    required: ["fecha", "franja"],
    additionalProperties: false,
};

/**
 * Modo rango de proponer_menu: planifica solo las casillas del rango, una semana tras otra (cada semana es su propio
 * plan). Solo rellena huecos: no borra nada, salta las semanas aceptadas o hechas por la persona y no toca casillas
 * ocupadas (con comida o bloqueadas) ni fuera del rango.
 */
const proponerRango = async (input: Obj, ctx: ToolCtx): Promise<unknown> => {
    const perfil = await leerPerfil(ctx);
    const habilitadas = arr(perfil.slots).map(obj).filter((s) => s.enabled === true).map((s) => String(s.slot));
    const inicio = diaInicio(perfil);
    const res = resolverRango(input.rango, habilitadas, inicio);
    if ("error" in res) return { ok: false, error: res.error };
    const avisos = [...res.avisos];
    if (res.semanas.length === 0) return { ok: false, error: "En ese rango no hay ninguna franja que planificar.", avisos };
    const lista = arr(input.platos);
    if (lista.length === 0) return { ok: false, error: "platos está vacío" };
    if (lista.length > MAX_PLATOS) return { ok: false, error: `como máximo ${MAX_PLATOS} platos` };
    // Cada plato debe caer en una casilla del rango; se agrupan por semana.
    const dentro = new Set(res.semanas.flatMap((w) => w.casillas.map((c) => `${c.fecha}|${c.franja}`)));
    const porSemana = new Map<string, unknown[]>();
    const fuera: string[] = [];
    lista.forEach((x, i) => {
        const p = obj(x);
        if (!esFecha(p.dia) || !dentro.has(`${p.dia}|${String(p.franja)}`)) {
            return void fuera.push(`plato ${i + 1}: ${String(p.dia)} ${FRANJA_ES[String(p.franja)] ?? String(p.franja)} está fuera del rango pedido`);
        }
        const semana = inicioSemana(p.dia, inicio);
        porSemana.set(semana, [...(porSemana.get(semana) ?? []), x]);
    });
    if (fuera.length > 0) return { ok: false, error: "Hay platos fuera del rango.", errores: fuera.slice(0, MAX_ERRORES) };
    const validados: { semana: string; platos: Plato[] }[] = [];
    const errores: string[] = [];
    for (const [semana, crudos] of porSemana) {
        const v = validarPlatos(crudos, semana, perfil);
        if ("errores" in v) errores.push(...v.errores.map((e) => `semana ${semana}: ${e}`));
        else validados.push({ semana, platos: v.platos });
    }
    if (errores.length > 0) return { ok: false, error: "Hay platos que corregir.", errores: errores.slice(0, MAX_ERRORES) };
    const sinCatalogo = await recetasNoComprobables(
        ctx, perfil,
        validados.flatMap((w) => w.platos).filter((p) => p.receta_id !== undefined).map((p) => ({
            receta_id: p.receta_id as number, donde: `plato ${p.dia} ${FRANJA_ES[p.franja]}`,
            comen: p.personas ?? comensalesEn(perfil, p.dia, p.franja).map((c) => c.id),
        })),
    );
    if (sinCatalogo.length > 0) return { ok: false, error: "Hay recetas que no puedo comprobar.", errores: sinCatalogo };

    const resultados: Obj[] = [];
    const tarjetas: Record<string, unknown>[] = [];
    const cambios: Cambio[] = [];
    const orden = new Map(res.semanas.map((w, i) => [w.semana, i]));
    validados.sort((a, b) => (orden.get(a.semana) ?? 0) - (orden.get(b.semana) ?? 0));
    for (const { semana, platos } of validados) {
        const plan = await leerPlan(ctx, semana);
        const existentes = plan === null ? [] : arr(plan.items).map(obj);
        const saltada = (motivo: string) => {
            avisos.push(`Semana ${semana}: ${motivo}`);
            resultados.push({ semana, ok: false, saltada: true });
        };
        if (plan !== null && plan.status === "accepted") {
            saltada("ya está aceptada: la cambia la persona en la app, no la toco.");
            continue;
        }
        if (plan !== null && plan.origin !== "kito" && existentes.length > 0) {
            saltada("ya tiene un menú hecho por la persona; no lo piso.");
            continue;
        }
        const ocupadas = new Map(existentes.map((i) => [`${i.day}|${i.slot}`, i]));
        const libres = platos.filter((p) => !ocupadas.has(`${p.dia}|${p.franja}`));
        const yaEstan = platos.filter((p) => {
            const e = ocupadas.get(`${p.dia}|${p.franja}`);
            return e !== undefined && claveCasilla(e.day, e.slot, e.kind, e.recipe_id, e.title) === claveCasilla(p.dia, p.franja, p.tipo, p.receta_id, p.titulo);
        });
        const ocupadasOtras = platos.length - libres.length - yaEstan.length;
        if (ocupadasOtras > 0) {
            avisos.push(`Semana ${semana}: ${ocupadasOtras} casilla(s) ya tenían comida o están bloqueadas y no se tocan.`);
        }
        const op: Cambio["op"] = plan === null ? "crear" : "editar";
        const idTarjeta = `menu-${semana}`;
        let planFinal: Obj;
        let opFinal = op;
        if (libres.length > 0) {
            const revision = typeof plan?.revision === "number" ? plan.revision : 0;
            const items = libres.map(itemDe);
            const key = await uuidDe(`menu-rango|${ctx.appUserId ?? ctx.uid}|${ctx.homeId ?? ""}|${semana}|${revision}|${JSON.stringify(items)}`);
            const r = await escribirDe(ctx)("PATCH", "meal/plan/items", {
                week_start: semana, expected_revision: revision, items, client_request_id: key, origin: "kito",
            });
            if (!r.ok) {
                resultados.push({ semana, ...errorEscritura(r) });
                continue;
            }
            planFinal = obj(r.data);
        } else if (yaEstan.length > 0 && plan !== null) {
            // Reintento tras un éxito: ya están puestas; solo se vuelve a comprobar y mostrar.
            planFinal = plan;
            opFinal = "editar";
        } else {
            saltada("no quedaba ninguna casilla libre en el rango.");
            continue;
        }
        const ev = await evaluar(ctx, planFinal, perfil, opFinal, new Map(), { semana, escritas: libres.length }, idTarjeta);
        resultados.push({ semana, ...ev.valor });
        if (ev.efectos?.tarjeta) tarjetas.push(ev.efectos.tarjeta);
        if (ev.efectos?.cambios) cambios.push(...ev.efectos.cambios);
    }
    const valor: Obj = { ok: tarjetas.length > 0, semanas: resultados, ...(avisos.length > 0 ? { avisos } : {}) };
    return tarjetas.length > 0 ? conEfectos(valor, { tarjetas, cambios }) : valor;
};

export const proponerMenuTool: Tool = {
    name: "proponer_menu",
    description:
        "Guarda el menú de UNA semana completa como borrador (origen Kito) y, si la comprobación de alergias, dietas y personas fuera da 0 conflictos, muestra la tarjeta del menú. Se llama una vez con todos los platos. Pasa `semana` = semana.inicio de leer_semana. No acepta el menú: lo acepta la persona en la app. Si hay conflictos no se muestra nada y te devuelve cuáles son. Si esa semana ya tiene un menú aceptado o hecho por la persona, no lo pisa. Con `rango` (desde y hasta, ambos inclusive, fecha y franja) planificas solo esas casillas, aunque crucen dos semanas: conviertes tú la petición («desde esta noche hasta el viernes a mediodía») a fechas con la fecha y zona de `hoy` de leer_perfil; «esta noche» es la cena (dinner) y «a mediodía» la comida (lunch). En modo rango no pases `semana` y solo se rellenan casillas vacías: no se borra nada, ni lo aceptado ni lo bloqueado.",
    input_schema: esquema({
        semana: { type: "string", description: "Primer día de la semana, AAAA-MM-DD (semana.inicio de leer_semana)." },
        platos: { type: "array", items: ESQUEMA_PLATO, description: "Un plato por día y franja." },
        rango: {
            type: "object",
            description: "Opcional: planifica solo este rango (ambos extremos inclusive). Sustituye a `semana`.",
            properties: { desde: ESQUEMA_PUNTO, hasta: ESQUEMA_PUNTO },
            required: ["desde", "hasta"],
            additionalProperties: false,
        },
    }, ["platos"]),
    escritura: true,
    strict: false,
    run: async (input, ctx) => {
        if (input.rango !== undefined) return await proponerRango(input, ctx);
        const semana = input.semana;
        if (!esFecha(semana)) return { falta: ["semana"], error: "La semana debe tener formato AAAA-MM-DD." };
        const perfil = await leerPerfil(ctx);
        if (isoDow(semana) !== diaInicio(perfil)) {
            return { ok: false, error: `La semana debe empezar el ${diaNombre(diaInicio(perfil))}; usa semana.inicio de leer_semana.` };
        }
        const v = validarPlatos(input.platos, semana, perfil);
        if ("errores" in v) return { ok: false, error: "Hay platos que corregir.", errores: v.errores };
        const sinCatalogo = await recetasNoComprobables(
            ctx, perfil,
            v.platos.filter((p) => p.receta_id !== undefined).map((p, i) => ({
                receta_id: p.receta_id as number, donde: `plato ${i + 1} (${p.dia} ${FRANJA_ES[p.franja]})`,
                comen: p.personas ?? comensalesEn(perfil, p.dia, p.franja).map((c) => c.id),
            })),
        );
        if (sinCatalogo.length > 0) return { ok: false, error: "Hay recetas que no puedo comprobar.", errores: sinCatalogo };
        const plan = await leerPlan(ctx, semana);
        const existentes = plan === null ? [] : arr(plan.items).map(obj);
        if (plan !== null && plan.status === "accepted") {
            return { ok: false, error: "Ese menú ya está aceptado: lo cambia la persona en la app, tú no lo tocas." };
        }
        if (plan !== null && plan.origin !== "kito" && existentes.length > 0) {
            return { ok: false, error: "Esa semana ya tiene un menú hecho por la persona; no lo piso. Dile que lo cambie en la app o que lo borre si quiere una propuesta tuya." };
        }
        const bloqueadas = new Set(existentes.filter((i) => i.state === "locked").map((i) => `${i.day}|${i.slot}`));
        const choque = v.platos.filter((p) => bloqueadas.has(`${p.dia}|${p.franja}`));
        if (choque.length > 0) {
            return { ok: false, error: `Esas casillas están bloqueadas por la persona y no se tocan: ${choque.map((p) => `${p.dia} ${FRANJA_ES[p.franja]}`).join(", ")}.` };
        }
        const revision = typeof plan?.revision === "number" ? plan.revision : 0;
        // Reintento tras un éxito: la revisión ya cambió (otra client_request_id), pero si las casillas
        // libres ya son estas mismas no se escribe de nuevo; solo se vuelve a comprobar y mostrar.
        if (plan !== null && plan.origin === "kito" && yaCoincide(existentes, v.platos)) {
            return await cerrar(ctx, plan, perfil, "editar", new Map());
        }
        const borrar = existentes.filter((i) => i.state !== "locked").map((i) => i.id as number);
        const items = v.platos.map(itemDe);
        const key = await uuidDe(`menu|${ctx.appUserId ?? ctx.uid}|${ctx.homeId ?? ""}|${semana}|${revision}|${JSON.stringify(items)}|${borrar.join(",")}`);
        const r = await escribirDe(ctx)("PATCH", "meal/plan/items", {
            week_start: semana, expected_revision: revision, items,
            ...(borrar.length > 0 ? { delete_ids: borrar } : {}), client_request_id: key, origin: "kito",
        });
        if (!r.ok) return errorEscritura(r);
        return await cerrar(ctx, obj(r.data), perfil, plan === null ? "crear" : "editar", new Map());
    },
};

export const reproponerTool: Tool = {
    name: "reproponer",
    description:
        "Cambia SOLO las casillas que la persona ha marcado para cambiar (estado rejected) en el menú de una semana. Para cada una pasa casilla_id y el plato nuevo (receta_id o titulo); `motivo` es lo que dijo la persona. No toca las casillas aceptadas ni las bloqueadas (locked) y no sirve para un menú ya aceptado. Después comprueba el menú y, con 0 conflictos, muestra la tarjeta actualizada.",
    input_schema: esquema({
        semana: { type: "string", description: "Primer día de la semana, AAAA-MM-DD." },
        cambios: {
            type: "array",
            items: {
                type: "object",
                properties: {
                    casilla_id: { type: "integer", description: "Id de la casilla rechazada (leer_semana)." },
                    receta_id: { type: "integer" },
                    titulo: { type: "string", description: "Obligatorio si no hay receta_id." },
                    motivo: { type: "string", description: "Por qué la persona la rechazó." },
                },
                required: ["casilla_id"],
                additionalProperties: false,
            },
        },
    }, ["semana", "cambios"]),
    escritura: true,
    strict: false,
    run: async (input, ctx) => {
        const semana = input.semana;
        if (!esFecha(semana)) return { falta: ["semana"], error: "La semana debe tener formato AAAA-MM-DD." };
        const plan = await leerPlan(ctx, semana);
        if (plan === null) return { ok: false, error: "Esa semana no tiene menú: usa proponer_menu." };
        if (plan.status === "accepted") return { ok: false, error: "Ese menú ya está aceptado: lo cambia la persona en la app, tú no lo tocas." };
        const casillas = arr(plan.items).map(obj);
        const rechazadas = casillas.filter((i) => i.state === "rejected");
        const cambios = arr(input.cambios).map(obj);
        if (cambios.length === 0) {
            return rechazadas.length === 0
                ? { ok: false, error: "No hay casillas marcadas para cambiar." }
                : { falta: ["cambios"], rechazadas: rechazadas.map((i) => ({ casilla_id: i.id, dia: i.day, franja: i.slot, titulo: i.title })) };
        }
        const errores: string[] = [];
        const items: Obj[] = [];
        const motivos = new Map<number, string>();
        const vistos = new Set<number>();
        for (const c of cambios) {
            const id = entero(c.casilla_id);
            const casilla = casillas.find((i) => i.id === id);
            if (id === undefined || casilla === undefined) {
                errores.push(`casilla ${String(c.casilla_id)}: no existe en ese menú`);
            } else if (casilla.state === "locked") {
                errores.push(`casilla ${id}: está bloqueada por la persona y no se toca`);
            } else if (casilla.state !== "rejected") {
                errores.push(`casilla ${id}: no está marcada para cambiar (solo repropongo las rechazadas)`);
            } else if (vistos.has(id)) {
                errores.push(`casilla ${id}: repetida`);
            } else {
                const recetaId = c.receta_id === undefined ? undefined : entero(c.receta_id);
                const titulo = str(c.titulo);
                if ((c.receta_id !== undefined && recetaId === undefined) || (recetaId === undefined && titulo === undefined)) {
                    errores.push(`casilla ${id}: falta el plato nuevo (receta_id o titulo)`);
                } else {
                    vistos.add(id);
                    const motivo = str(c.motivo, 160);
                    if (motivo !== undefined) motivos.set(id, motivo);
                    items.push({
                        id, day: casilla.day, slot: casilla.slot, position: casilla.position,
                        kind: recetaId !== undefined ? "recipe" : "free_text",
                        ...(recetaId !== undefined ? { recipe_id: recetaId } : { title: titulo }),
                        state: null,
                    });
                }
            }
        }
        if (errores.length > 0) return { ok: false, error: "Hay cambios que corregir.", errores: errores.slice(0, MAX_ERRORES) };
        const perfil = await leerPerfil(ctx);
        const sinCatalogo = await recetasNoComprobables(
            ctx, perfil,
            items.filter((i) => i.kind === "recipe").map((i) => {
                const c = casillas.find((x) => x.id === i.id)!;
                return { receta_id: i.recipe_id as number, donde: `casilla ${i.id}`, comen: arr(c.members).filter((n): n is number => typeof n === "number") };
            }),
        );
        if (sinCatalogo.length > 0) return { ok: false, error: "Hay recetas que no puedo comprobar.", errores: sinCatalogo };
        const revision = plan.revision as number;
        const key = await uuidDe(`repropone|${ctx.appUserId ?? ctx.uid}|${ctx.homeId ?? ""}|${plan.id}|${revision}|${JSON.stringify(items)}`);
        const r = await escribirDe(ctx)("PATCH", "meal/plan/items", {
            week_start: semana, expected_revision: revision, items, client_request_id: key, origin: "kito",
        });
        if (!r.ok) return errorEscritura(r);
        const nuevo = obj(r.data);
        const pendientes = arr(nuevo.items).map(obj).filter((i) => i.state === "rejected").length;
        return await cerrar(ctx, nuevo, perfil, "editar", motivos, { cambiadas: items.length, rechazadas_pendientes: pendientes });
    },
};
