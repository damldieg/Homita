// Herramientas de lectura de la skill `menus`: leer_perfil, leer_semana y buscar_recetas. Solo leen con el lector
// del usuario (`ctx.leer`): RLS, permisos y hogar activo los pone el api. No escriben nada.
import type { Tool, ToolCtx } from "../../core.ts";
import { compactarEvento } from "../consulta/compacto.ts";
import { finRango, inicioRango } from "../consulta/fechas.ts";
import {
    arr, AVISO_SIN_CATALOGO, diaInicio, diaNombre, entero, esFecha, esquema, FRANJA_ES, FRANJAS, inicioSemana, isoDow, leerDe, leerPerfil,
    leerPlan, obj, recetaComprobable, restringidos, str, sumarDias,
} from "./util.ts";
import type { Obj } from "./util.ts";
import { compactarPlan } from "./plan.ts";

const AVISO_SIN_PAISES =
    "El hogar no tiene países elegidos: no asumas ninguna cocina. Pregunta de dónde son los platos que les gustan (cuenta como una de las 2 preguntas de perfil) o propón variado.";

/** Países del hogar: lista de textos o de objetos {name|code}. Tolera que el campo no exista aún (PR de países). */
export const paisesDe = (perfil: Obj): string[] => {
    const p = obj(perfil.profile);
    const crudo = perfil.countries ?? p.countries ?? obj(p.preferences).countries;
    return arr(crudo)
        .map((x) => (typeof x === "string" ? x : str(obj(x).name) ?? str(obj(x).code) ?? ""))
        .map((x) => x.trim())
        .filter((x) => x !== "")
        .slice(0, 20);
};

const textos = (v: unknown, max = 50): string[] => arr(v).filter((x): x is string => typeof x === "string").slice(0, max);

/**
 * Ficha de una persona que come. Los datos de salud (`goals`, `diet_note`) solo se incluyen si el usuario tiene
 * `menu.health.view` (`ctx.permisos`); el piloto no los expone y, mientras no se sepan los permisos, se omiten.
 */
const compactarPersona = (m: Obj, conSalud: boolean): Obj => {
    const alergias = arr(m.allergies).map((a) => {
        const o = obj(a);
        return typeof a === "string" ? a : { alergeno: o.allergen, gravedad: o.severity };
    });
    return {
        id: m.home_member_id,
        nombre: str(m.name, 80) ?? "",
        tipo: m.kind,
        edad: m.age_band ?? null,
        porcion: m.portion_size ?? null,
        alergias_respondidas: m.allergies_answered === true,
        alergias,
        dieta: m.diet ?? null,
        no_le_gusta: textos(m.dislikes),
        favoritos: textos(m.favorites),
        manias: str(m.quirks) ?? null,
        picante: m.spice ?? null,
        ...(conSalud ? { objetivos: m.goals ?? null, nota_dieta: m.diet_note ?? null } : {}),
    };
};

/** Zona horaria del hogar (la del perfil; si falta, la del usuario) y fecha/hora local de hoy en ella. */
export const hoyLocal = (perfil: Obj, ctx: ToolCtx): { zona_horaria: string; fecha: string; dia: string; hora: string } => {
    const zona = str(perfil.timezone, 60) ?? ctx.timezone;
    const valida = (z: string): string => {
        try {
            new Intl.DateTimeFormat("sv-SE", { timeZone: z });
            return z;
        } catch {
            return ctx.timezone;
        }
    };
    const tz = valida(zona);
    const fecha = ctx.now.toLocaleDateString("sv-SE", { timeZone: tz });
    const hora = ctx.now.toLocaleTimeString("sv-SE", { timeZone: tz, hour: "2-digit", minute: "2-digit" });
    return { zona_horaria: tz, fecha, dia: diaNombre(isoDow(fecha)), hora };
};

export const compactarPerfil = (perfil: Obj, ctx: ToolCtx): Obj => {
    const p = obj(perfil.profile);
    const conSalud = ctx.permisos?.includes("menu.health.view") === true;
    const paises = paisesDe(perfil);
    const comen = arr(perfil.members).map(obj).map((m) => compactarPersona(m, conSalud));
    const sinAlergias = comen.filter((m) => m.alergias_respondidas !== true).map((m) => m.nombre);
    return {
        hoy: hoyLocal(perfil, ctx),
        hogar: {
            franjas: arr(perfil.slots).map(obj).filter((s) => s.enabled === true).map((s) => ({ franja: s.slot, hora: s.time })),
            dia_inicio_semana: diaInicio(perfil),
            dia_compra: p.shopping_day ?? null,
            minutos_cocina_diario: p.cook_minutes_weekday ?? null,
            minutos_cocina_finde: p.cook_minutes_weekend ?? null,
            nivel_cocina: p.cook_skill ?? null,
            repeticion: p.repeat_policy ?? null,
            sobras: p.leftovers ?? null,
            postre: p.dessert ?? null,
            equipamiento: textos(p.equipment, 20),
        },
        paises,
        ...(paises.length === 0 ? { aviso_paises: AVISO_SIN_PAISES } : {}),
        comen,
        ...(sinAlergias.length > 0
            ? { pendiente: { alergias_sin_responder: sinAlergias, aviso: "No propongas menú hasta saber las alergias de estas personas (aunque sea «ninguna»)." } }
            : {}),
        puede_editar_perfil: perfil.can_edit === true,
    };
};

export const leerPerfilTool: Tool = {
    name: "leer_perfil",
    description:
        "Lee el perfil de comidas del hogar: franjas que se planifican, cuánto tiempo hay para cocinar, países del hogar, y por persona alergias, dieta, lo que no le gusta, favoritos y picante. Ejecútala siempre antes de proponer un menú. Si hay alergias sin responder, pregúntalas antes de proponer.",
    input_schema: esquema({}),
    strict: false,
    run: async (_input, ctx) => compactarPerfil(await leerPerfil(ctx), ctx),
};

/** Una semana a partir de una fecha cualquiera (por defecto, hoy en la zona del usuario). */
const semanaDe = (input: Obj, perfil: Obj, ctx: ToolCtx): string => {
    const f = input.fecha;
    const base = esFecha(f) ? f : ctx.now.toLocaleDateString("sv-SE", { timeZone: ctx.timezone });
    return inicioSemana(base, diaInicio(perfil));
};

export const leerSemanaTool: Tool = {
    name: "leer_semana",
    description:
        "Lee una semana: eventos del calendario, quién no come en casa cada día y franja (meal_schedule), y el menú que ya existe (casillas, estado, revisión). Con `fecha` (AAAA-MM-DD, cualquier día de esa semana; por defecto hoy) elige la semana. Devuelve `semana.inicio` (el día de inicio que hay que pasar a proponer_menu). Los días fuera hay que confirmarlos con la persona antes de proponer.",
    input_schema: esquema({ fecha: { type: "string", description: "Cualquier día de la semana, AAAA-MM-DD." } }),
    strict: false,
    run: async (input, ctx) => {
        if (input.fecha !== undefined && !esFecha(input.fecha)) return { error: "La fecha debe tener formato AAAA-MM-DD." };
        const perfil = await leerPerfil(ctx);
        const inicio = semanaDe(input, perfil, ctx);
        const fin = sumarDias(inicio, 6);
        const [plan, crudoEventos] = await Promise.all([
            leerPlan(ctx, inicio),
            leerDe(ctx)("event", {
                start_date: String(inicioRango(inicio)), end_date: String(finRango(fin)), routine: "false",
                order_mode: "asc", limit: "100",
            }),
        ]);
        const eventos = Array.isArray(crudoEventos) ? crudoEventos : null;
        const habilitadas = arr(perfil.slots).map(obj).filter((s) => s.enabled === true).map((s) => String(s.slot));
        const nombres = new Map(arr(perfil.members).map(obj).map((m) => [m.home_member_id, str(m.name, 80) ?? ""]));
        const dias = Array.from({ length: 7 }, (_, i) => sumarDias(inicio, i)).map((dia) => {
            const wd = isoDow(dia);
            const fuera = arr(perfil.schedule).map(obj)
                .filter((e) => e.weekday === wd && e.status !== "home" && habilitadas.includes(String(e.slot)))
                .map((e) => ({ persona: nombres.get(e.home_member_id) ?? "", franja: FRANJA_ES[String(e.slot)] ?? e.slot, estado: e.status }));
            const evs = (eventos ?? []).map((e) => compactarEvento(e, ctx.timezone))
                .filter((e) => String(e.inicio ?? "").startsWith(dia))
                .map((e) => ({ titulo: e.titulo, inicio: e.inicio }));
            return { fecha: dia, dia: diaNombre(wd), fuera, eventos: evs };
        });
        const hayFuera = dias.some((d) => d.fuera.length > 0);
        return {
            semana: { inicio, fin },
            franjas: habilitadas,
            dias,
            ...(eventos === null ? { aviso_eventos: "No he podido leer los eventos ahora mismo." } : {}),
            ...(hayFuera ? { confirmar: "Hay personas fuera algún día: dilo a la persona y confirma que es correcto antes de proponer." } : {}),
            menu: plan === null ? null : compactarPlan(plan),
        };
    },
};

const MAX_RECETAS = 40;
const SEMANAS_HISTORIAL = 3;
const MAX_SEMANAS_HISTORIAL = 8;

export const buscarRecetasTool: Tool = {
    name: "buscar_recetas",
    description:
        "Busca en el recetario del hogar (por texto, franja o minutos máximos) y devuelve también `ya_tomados`: los platos de las últimas semanas, para no repetirlos. Con `semana` (el inicio de la semana que vas a proponer) se miran las semanas anteriores a esa.",
    input_schema: esquema({
        texto: { type: "string", description: "Texto a buscar en el nombre." },
        franja: { type: "string", enum: [...FRANJAS], description: "breakfast, midmorning, lunch, snack o dinner." },
        max_minutos: { type: "integer", description: "Tiempo máximo de preparación." },
        semana: { type: "string", description: "Inicio de la semana que se va a proponer, AAAA-MM-DD." },
        semanas_historial: { type: "integer", description: "Cuántas semanas anteriores mirar (por defecto 3, máximo 8)." },
    }),
    strict: false,
    run: async (input, ctx) => {
        const franja = str(input.franja);
        if (franja !== undefined && !(FRANJAS as readonly string[]).includes(franja)) return { error: "Franja no válida." };
        if (input.semana !== undefined && !esFecha(input.semana)) return { error: "La semana debe tener formato AAAA-MM-DD." };
        const n = Math.min(entero(input.semanas_historial) ?? SEMANAS_HISTORIAL, MAX_SEMANAS_HISTORIAL);
        const minutos = entero(input.max_minutos);
        const perfil = await leerPerfil(ctx);
        const ref = esFecha(input.semana) ? input.semana : semanaDe({}, perfil, ctx);
        const params: Record<string, string | undefined> = {
            q: str(input.texto, 80), slot: franja, max_minutes: minutos === undefined ? undefined : String(minutos),
        };
        const semanas = Array.from({ length: n }, (_, i) => sumarDias(ref, -7 * (i + 1)));
        const [recetas, ...planes] = await Promise.all([
            leerDe(ctx)("recipe", params),
            ...semanas.map((s) => leerPlan(ctx, s).catch(() => null)),
        ]);
        if (!Array.isArray(recetas)) return { error: "No he podido leer el recetario ahora mismo." };
        const yaTomados = planes.flatMap((p, i) =>
            p === null ? [] : arr(p.items).map(obj).filter((it) => it.kind === "recipe" || it.kind === "free_text")
                .map((it) => ({ semana: semanas[i], dia: it.day, franja: it.slot, titulo: str(it.title, 80), receta_id: it.recipe_id ?? null }))
        );
        // Hogar con dieta o alergias: se excluyen las recetas con algún ingrediente sin food_id (no comprobables).
        let lista = recetas.map(obj);
        let excluidas: Obj[] = [];
        if (restringidos(perfil).size > 0) {
            const ok = await Promise.all(lista.slice(0, MAX_RECETAS).map((r) => recetaComprobable(ctx, r.id)));
            const dentro = lista.slice(0, MAX_RECETAS);
            excluidas = dentro.filter((_, i) => !ok[i]).map((r) => ({ id: r.id, nombre: str(r.name, 80) ?? "" }));
            lista = [...dentro.filter((_, i) => ok[i]), ...lista.slice(MAX_RECETAS)];
        }
        return {
            recetas: lista.slice(0, MAX_RECETAS).map((r) => ({
                id: r.id, nombre: str(r.name, 80) ?? "", raciones: r.servings, minutos: r.minutes ?? null, franjas: r.slots ?? [],
            })),
            hay_mas: lista.length > MAX_RECETAS,
            ...(excluidas.length > 0 ? { excluidas_sin_catalogo: excluidas, aviso_excluidas: AVISO_SIN_CATALOGO } : {}),
            ya_tomados: yaTomados.slice(0, 80),
            ...(lista.length === 0 && excluidas.length === 0 ? { aviso: "El recetario no tiene nada que encaje: propón platos nuevos y guárdalos con guardar_receta (con pasos)." } : {}),
        };
    },
};
