// proponer_menu y reproponer: Kito guarda un BORRADOR del menú (origin kito) y, si `check_meal_plan` da 0
// conflictos, deja la tarjeta `menu`. Kito nunca acepta: la persona lo hace en la app. Idempotencia: la
// `client_request_id` sale del contenido (misma propuesta sobre la misma revisión = mismo UUID), así que un
// reintento no duplica. Concurrencia: `expected_revision` es la revisión que acaba de leer.
import { conEfectos } from "../../core.ts";
import type { Cambio, Tool, ToolCtx } from "../../core.ts";
import { uuidDe } from "../organizar/uuid.ts";
import { compactarPlan, tarjetaMenu } from "./plan.ts";
import {
    arr, comensalesEn, diaInicio, diaNombre, entero, errorEscritura, escribirDe, esFecha, esquema, FRANJA_ES, FRANJAS, isoDow, leerDe,
    leerPerfil, leerPlan, norm, obj, str, sumarDias,
} from "./util.ts";
import type { Obj } from "./util.ts";

const MAX_PLATOS = 60;
const MAX_ERRORES = 6;
const TIPOS = ["recipe", "free_text", "leftovers", "eat_out"] as const;

const CODIGOS: Record<string, string> = {
    allergen: "alergia", intolerance: "intolerancia", diet: "dieta", member_out: "persona fuera de casa",
};

/** `check_meal_plan` del plan: lista de conflictos, o `null` si no se pudo comprobar. */
const comprobar = async (ctx: ToolCtx, planId: number): Promise<Obj[] | null> => {
    const r = await leerDe(ctx)("meal/plan/check", { plan_id: String(planId) });
    return Array.isArray(r) ? r.map(obj) : null;
};

const compactarConflictos = (conflictos: Obj[], nombres: Map<unknown, string>, titulos: Map<unknown, string>): Obj[] =>
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
 * Cierra una propuesta o repropuesta ya guardada: comprueba el plan y, solo con 0 conflictos, emite la tarjeta.
 * Con conflictos NO hay tarjeta: el modelo recibe cuáles son para corregirlos y volver a proponer.
 */
const cerrar = async (
    ctx: ToolCtx, plan: Obj, perfil: Obj, op: Cambio["op"], motivos: Map<number, string>, extra: Obj = {},
): Promise<unknown> => {
    const planId = entero(plan.id);
    const conflictos = planId === undefined ? null : await comprobar(ctx, planId);
    if (conflictos === null) {
        return { ok: false, error: "No he podido comprobar el menú (alergias, dietas y personas fuera). No lo muestro hasta comprobarlo; inténtalo de nuevo." };
    }
    const nombres = new Map(arr(perfil.members).map(obj).map((m) => [m.home_member_id, str(m.name, 80) ?? ""]));
    if (conflictos.length > 0) {
        const titulos = new Map(arr(plan.items).map(obj).map((i) => [i.id, str(i.title, 80) ?? ""]));
        return {
            ok: false,
            tarjeta: false,
            conflictos: compactarConflictos(conflictos, nombres, titulos),
            aviso: "El menú guardado tiene conflictos y NO se muestra a la persona. Cambia esos platos y vuelve a llamar a proponer_menu (o a reproponer si ya hay casillas marcadas). Si no encuentras alternativa, explícaselo.",
            ...extra,
        };
    }
    const resumen = compactarPlan(plan, motivos);
    return conEfectos(
        {
            ok: true,
            estado: "borrador guardado y tarjeta mostrada; lo acepta la persona en la app (tú no puedes aceptarlo)",
            plan_id: resumen.plan_id,
            revision: resumen.revision,
            casillas: arr(resumen.casillas).length,
            conflictos: 0,
            sin_comprobar: resumen.sin_comprobar,
            ...extra,
        },
        { tarjeta: tarjetaMenu(plan, motivos), cambios: [{ tipo: "menu", id: planId ?? null, op }] },
    );
};

interface Plato {
    dia: string;
    franja: string;
    tipo: (typeof TIPOS)[number];
    receta_id?: number;
    titulo?: string;
    personas?: number[];
}

const validarPlatos = (crudo: unknown, semana: string, perfil: Obj): { platos: Plato[] } | { errores: string[] } => {
    const errores: string[] = [];
    const lista = arr(crudo);
    if (lista.length === 0) return { errores: ["platos está vacío"] };
    if (lista.length > MAX_PLATOS) return { errores: [`como máximo ${MAX_PLATOS} platos`] };
    const habilitadas = arr(perfil.slots).map(obj).filter((s) => s.enabled === true).map((s) => String(s.slot));
    const fin = sumarDias(semana, 6);
    const platos: Plato[] = [];
    const vistos = new Set<string>();
    lista.forEach((x, i) => {
        const p = obj(x);
        const donde = `plato ${i + 1}`;
        const dia = p.dia;
        const franja = typeof p.franja === "string" ? p.franja : "";
        if (!esFecha(dia) || dia < semana || dia > fin) return void errores.push(`${donde}: el día debe estar entre ${semana} y ${fin}`);
        if (!(FRANJAS as readonly string[]).includes(franja)) return void errores.push(`${donde}: franja no válida`);
        if (!habilitadas.includes(franja)) return void errores.push(`${donde}: la franja ${FRANJA_ES[franja]} no se planifica en este hogar`);
        const clave = `${dia}|${franja}`;
        if (vistos.has(clave)) return void errores.push(`${donde}: ya hay otro plato el ${dia} en ${FRANJA_ES[franja]}`);
        vistos.add(clave);
        const recetaId = p.receta_id === undefined ? undefined : entero(p.receta_id);
        if (p.receta_id !== undefined && recetaId === undefined) return void errores.push(`${donde}: receta_id no válido`);
        const titulo = str(p.titulo);
        const tipo = (TIPOS as readonly string[]).includes(String(p.tipo)) ? p.tipo as Plato["tipo"] : recetaId !== undefined ? "recipe" : "free_text";
        if (tipo === "recipe" && recetaId === undefined) return void errores.push(`${donde}: un plato de receta lleva receta_id (si no la tienes, guárdala antes con guardar_receta)`);
        if (tipo === "free_text" && titulo === undefined) return void errores.push(`${donde}: falta el título`);
        const comen = comensalesEn(perfil, dia, franja);
        if (comen.length === 0) return void errores.push(`${donde}: nadie come en casa el ${diaNombre(isoDow(dia))} en ${FRANJA_ES[franja]} (todos están fuera); no pongas plato ahí`);
        let personas: number[] | undefined;
        if (p.personas !== undefined) {
            const ids = arr(p.personas).map(entero);
            if (ids.some((n) => n === undefined || !comen.some((c) => c.id === n))) {
                return void errores.push(`${donde}: personas debe ser un subconjunto de quienes comen en casa ese día (${comen.map((c) => `${c.nombre}=${c.id}`).join(", ")})`);
            }
            personas = ids as number[];
        }
        platos.push({ dia, franja, tipo, ...(recetaId !== undefined ? { receta_id: recetaId } : {}), ...(titulo !== undefined ? { titulo } : {}), ...(personas ? { personas } : {}) });
    });
    return errores.length > 0 ? { errores: errores.slice(0, MAX_ERRORES) } : { platos };
};

const itemDe = (p: Plato): Obj => ({
    day: p.dia, slot: p.franja, position: 0, kind: p.tipo,
    ...(p.tipo === "recipe" ? { recipe_id: p.receta_id } : p.tipo === "free_text" || p.titulo ? { title: p.titulo } : {}),
    ...(p.personas ? { members: p.personas } : {}),
});

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

const claveCasilla = (dia: unknown, franja: unknown, tipo: unknown, receta: unknown, titulo: unknown): string =>
    `${dia}|${franja}|${tipo}|${receta ?? ""}|${tipo === "recipe" ? "" : norm(String(titulo ?? ""))}`;

/** `true` si las casillas no bloqueadas del plan son exactamente los platos propuestos (mismo día, franja y plato). */
const yaCoincide = (existentes: Obj[], platos: Plato[]): boolean => {
    const libres = existentes.filter((i) => i.state !== "locked").map((i) => claveCasilla(i.day, i.slot, i.kind, i.recipe_id, i.title));
    const nuevos = platos.map((p) => claveCasilla(p.dia, p.franja, p.tipo, p.receta_id, p.titulo));
    if (libres.length !== nuevos.length) return false;
    const a = [...libres].sort();
    const b = [...nuevos].sort();
    return a.every((x, n) => x === b[n]) && !existentes.some((i) => i.state === "rejected");
};

export const proponerMenuTool: Tool = {
    name: "proponer_menu",
    description:
        "Guarda el menú de UNA semana completa como borrador (origen Kito) y, si la comprobación de alergias, dietas y personas fuera da 0 conflictos, muestra la tarjeta del menú. Se llama una vez con todos los platos. Pasa `semana` = semana.inicio de leer_semana. No acepta el menú: lo acepta la persona en la app. Si hay conflictos no se muestra nada y te devuelve cuáles son. Si esa semana ya tiene un menú aceptado o hecho por la persona, no lo pisa.",
    input_schema: esquema({
        semana: { type: "string", description: "Primer día de la semana, AAAA-MM-DD (semana.inicio de leer_semana)." },
        platos: { type: "array", items: ESQUEMA_PLATO, description: "Un plato por día y franja." },
    }, ["semana", "platos"]),
    escritura: true,
    strict: false,
    run: async (input, ctx) => {
        const semana = input.semana;
        if (!esFecha(semana)) return { falta: ["semana"], error: "La semana debe tener formato AAAA-MM-DD." };
        const perfil = await leerPerfil(ctx);
        if (isoDow(semana) !== diaInicio(perfil)) {
            return { ok: false, error: `La semana debe empezar el ${diaNombre(diaInicio(perfil))}; usa semana.inicio de leer_semana.` };
        }
        const v = validarPlatos(input.platos, semana, perfil);
        if ("errores" in v) return { ok: false, error: "Hay platos que corregir.", errores: v.errores };
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
