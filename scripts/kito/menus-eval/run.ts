// scripts/kito/menus-eval/run.ts — Comparación de modelos para el menú semanal de Kito (change kito-menus, T14/T15).
// Ejecuta `runKito` con la skill `menus` real sobre hogares de ejemplo (fixtures/) con lector y escritor FALSOS
// (el mundo de tests/menus_util.ts: sin BD ni red salvo la llamada al modelo) y mide por modelo: conflictos
// del menú resultante, repeticiones y tokens (entrada, salida, caché).
//
// Con --seco usa un modelo simulado (sin red ni clave) para validar el script y la tabla. SIN --seco GASTA
// TOKENS REALES de Anthropic: la clave se toma de la variable de entorno ANTHROPIC_API_KEY en ese momento;
// nunca se lee ningún fichero de secretos. Cada hogar es una llamada a runKito (hasta 7 al modelo), así que se
// limita con --max-llamadas (por defecto 150 llamadas HTTP en total).
//
// Uso (raíz del repo):
//   deno run --allow-read --allow-write --allow-env scripts/kito/menus-eval/run.ts --seco
//   ANTHROPIC_API_KEY=… deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com \
//     scripts/kito/menus-eval/run.ts --modelos claude-haiku-5-5,claude-sonnet-5-5 --hogares 10 \
//     --salida docs/planificador-comidas/comparacion-modelos-kito.md
import { runKito } from "../../../supabase/functions/asistente/core.ts";
import type { CallModel, ModelResponse } from "../../../supabase/functions/asistente/core.ts";
import { crearCallModel } from "../../../supabase/functions/asistente/modelo.ts";
import { menus } from "../../../supabase/functions/asistente/skills/menus/index.ts";
import { crearMundo, ctxDe } from "../../../supabase/functions/asistente/tests/menus_util.ts";

type Obj = Record<string, unknown>;

export interface Receta { id: number; name: string; servings: number; minutes: number; slots: string[]; alergenos: string[]; ingredientes?: Obj[] }
export interface Hogar { id: string; nombre: string; nota: string; semana: string; mensaje: string; perfil: Obj; historial?: Record<string, Obj> }

/** Tarifas en USD por millón de tokens. Configurables: ver `TARIFAS_POR_DEFECTO` y el informe. */
export interface Tarifa { entrada: number; salida: number }
export const TARIFAS_POR_DEFECTO: Record<string, Tarifa> = {
    // Referencia: página pública de precios de Anthropic (https://www.anthropic.com/pricing); sin verificar
    // para la generación 5.5, por eso se pueden sobreescribir con --tarifa modelo=entrada/salida.
    "claude-haiku-5-5": { entrada: 1, salida: 5 },
    "claude-sonnet-5-5": { entrada: 3, salida: 15 },
};
const LECTURA_CACHE = 0.1; // multiplicador sobre la tarifa de entrada
const ESCRITURA_CACHE = 1.25;

export interface Resultado {
    hogar: string;
    modelo: string;
    ok: boolean;
    error?: string;
    casillas: number;
    conflictos: number;
    detalleConflictos: string[];
    repeticiones: number;
    repeticionesHistorial: number;
    tarjeta: boolean;
    herramientas: number;
    tokens: { input: number; output: number; cacheRead: number; cacheWrite: number };
    llamadas: number;
}

const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\s+/g, " ").trim();

const PALABRAS: Record<string, string[]> = {
    gluten: ["pasta", "pizza", "fideua", "lasana", "cuscus", "pan ", "tacos", "hamburguesa", "empanad", "macarron", "espagueti", "tortilla de trigo", "bocadillo"],
    lactosa: ["queso", "yogur", "pizza", "lasana", "bechamel", "nata", "leche", "mantequilla"],
    huevo: ["huevo", "tortilla de patatas", "revuelto", "lasana", "mayonesa", "pad thai"],
    cacahuete: ["cacahuete", "pad thai", "mani"],
    frutos_secos: ["frutos secos", "nuez", "almendra", "avellana", "pistacho"],
    sesamo: ["sesamo", "tahini", "sushi"],
    marisco: ["marisco", "gamba", "langostino", "calamar", "mejillon", "fideua", "pad thai"],
    pescado: ["pescado", "salmon", "merluza", "atun", "bacalao", "sushi", "sardina"],
    soja: ["soja", "tofu"],
};
const CARNE = ["pollo", "carne", "ternera", "cerdo", "jamon", "hamburguesa de ternera", "chorizo", "atun", "salmon", "merluza", "gamba", "marisco", "bacalao", "fideua", "sushi", "pad thai"];
const NO_HALAL = ["cerdo", "jamon", "chorizo", "panceta", "bacon", "vino"];
const NO_VEGANO = ["huevo", "queso", "yogur", "leche", "tortilla", "revuelto", "pizza", "lasana", "mantequilla", "miel"];

/** Quita las negaciones («sin carne», «sin gluten»…): lo que va tras «sin» no está en el plato. */
export const sinNegaciones = (titulo: string): string => titulo.replace(/\bsin\s+\S+(\s+(ni|y|o)\s+\S+)*/g, " ").replace(/\s+/g, " ").trim();

/**
 * Conflicto de dieta por título y alérgenos de la receta. Es un criterio aproximado: el servidor
 * (check_meal_plan) mira las secciones de los ingredientes, que el catálogo de fixtures no tiene.
 */
export const conflictoDieta = (dieta: string, titulo: string, alergenos: string[] = []): boolean => {
    const t = sinNegaciones(norm(titulo));
    const animal = alergenos.includes("pescado") || alergenos.includes("marisco");
    if (dieta === "vegetarian") return animal || CARNE.some((p) => t.includes(p));
    if (dieta === "vegan") return animal || alergenos.includes("huevo") || alergenos.includes("lactosa") || CARNE.some((p) => t.includes(p)) || NO_VEGANO.some((p) => t.includes(p));
    if (dieta === "halal") return NO_HALAL.some((p) => t.includes(p));
    return false;
};

const clave = (it: Obj): string => it.kind === "recipe" ? `r${it.recipe_id}` : norm(String(it.title ?? ""));

/** Mide el plan final: conflictos (check del mundo + palabras clave sobre el título) y repeticiones. */
export const medirPlan = async (
    plan: Obj | null, hogar: Hogar, recetas: Receta[], leer: (r: string, p?: Record<string, string | undefined>) => Promise<unknown>,
): Promise<{ casillas: number; conflictos: string[]; repeticiones: number; repeticionesHistorial: number }> => {
    if (plan === null) return { casillas: 0, conflictos: [], repeticiones: 0, repeticionesHistorial: 0 };
    const items = (plan.items as Obj[]) ?? [];
    const vistos = new Set<string>();
    const conflictos: string[] = [];
    const anota = (it: Obj, m: unknown, code: string, det: string) => {
        const k = `${it.id}|${m}|${code}|${det}`;
        if (vistos.has(k)) return;
        vistos.add(k);
        conflictos.push(`${it.day} ${it.slot} ${String(it.title ?? "")} persona ${m}: ${code} ${det}`.trim());
    };
    const check = await leer("meal/plan/check", { plan_id: String(plan.id) });
    for (const c of Array.isArray(check) ? check as Obj[] : []) {
        const it = items.find((i) => i.id === c.item_id) ?? { id: c.item_id, day: c.day, slot: c.slot, title: "" };
        // Mismo dedupe que el de palabras clave: un alérgeno detectado por receta no se cuenta dos veces.
        anota(it, c.member_id, String(c.code), String((c.detail as Obj | undefined)?.allergen ?? ""));
    }
    const miembros = hogar.perfil.members as Obj[];
    for (const it of items) {
        const titulo = norm(String(it.title ?? ""));
        const rec = it.kind === "recipe" ? recetas.find((r) => r.id === it.recipe_id) : undefined;
        for (const id of (it.members as number[]) ?? []) {
            const m = miembros.find((x) => x.home_member_id === id);
            if (!m) continue;
            for (const a of (m.allergies as Obj[]) ?? []) {
                const al = String(a.allergen);
                const alRec = rec?.alergenos.includes(al) ?? false;
                const alPal = (PALABRAS[al] ?? []).some((p) => titulo.includes(p));
                if (alRec || alPal) anota(it, id, "allergen", al);
            }
            const dieta = String(m.diet ?? "");
            if (conflictoDieta(dieta, String(it.title ?? ""), rec?.alergenos)) anota(it, id, "diet", dieta);
        }
    }
    // Repeticiones: casillas con un plato ya servido antes esa misma semana (las copias extra).
    const cuenta = new Map<string, number>();
    for (const it of items) cuenta.set(clave(it), (cuenta.get(clave(it)) ?? 0) + 1);
    const repeticiones = [...cuenta.values()].reduce((s, n) => s + Math.max(0, n - 1), 0);
    const previos = new Set<string>();
    for (const p of Object.values(hogar.historial ?? {})) for (const i of (p.items as Obj[]) ?? []) previos.add(clave(i));
    const repeticionesHistorial = items.filter((i) => previos.has(clave(i))).length;
    return { casillas: items.length, conflictos, repeticiones, repeticionesHistorial };
};

const sumar = (a: Resultado["tokens"], b: Resultado["tokens"]) => ({
    input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite,
});

/** Ejecuta un hogar con un modelo (la skill real, el mundo falso del fixture) y mide el resultado. */
export const evaluarHogar = async (hogar: Hogar, recetas: Receta[], modelo: string, callModel: CallModel, effort?: string): Promise<Resultado> => {
    const alergenos: Record<number, string[]> = {};
    for (const r of recetas) alergenos[r.id] = r.alergenos;
    // Ingredientes de las recetas con texto libre (sin food_id): no son comprobables para quien tiene dieta o alergias.
    const ingredientes: Record<number, Obj[]> = {};
    for (const r of recetas) if (r.ingredientes) ingredientes[r.id] = r.ingredientes;
    const recetasSinComprobar = recetas.filter((r) => r.ingredientes?.some((i) => i.food_id === null || i.food_id === undefined)).map((r) => r.id);
    const mundo = crearMundo({
        perfil: JSON.parse(JSON.stringify(hogar.perfil)),
        recetas: recetas.map(({ alergenos: _a, ingredientes: _i, ...r }) => r),
        alergenos, ingredientes, recetasSinComprobar,
        historial: hogar.historial,
    });
    let llamadas = 0;
    const contado: CallModel = (b, o) => {
        llamadas++;
        return callModel(b, o);
    };
    const base: Resultado = {
        hogar: hogar.id, modelo, ok: false, casillas: 0, conflictos: 0, detalleConflictos: [], repeticiones: 0, repeticionesHistorial: 0,
        tarjeta: false, herramientas: 0, tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, llamadas: 0,
    };
    try {
        const r = await runKito({
            mensajes: [{ role: "user", content: hogar.mensaje }],
            ctx: ctxDe(mundo, { now: new Date(`${hogar.semana}T08:00:00Z`) }),
            skills: [menus], callModel: contado, model: modelo, effort,
        });
        const med = await medirPlan(mundo.plan(), hogar, recetas, mundo.leer);
        return {
            ...base, ok: true, casillas: med.casillas, conflictos: med.conflictos.length, detalleConflictos: med.conflictos,
            repeticiones: med.repeticiones, repeticionesHistorial: med.repeticionesHistorial,
            tarjeta: r.tarjetas.length > 0, herramientas: r.herramientasUsadas, tokens: r.tokens, llamadas,
        };
    } catch (e) {
        const med = await medirPlan(mundo.plan(), hogar, recetas, mundo.leer);
        return { ...base, error: e instanceof Error ? e.message : String(e), casillas: med.casillas, llamadas };
    }
};

export const costeUsd = (t: Resultado["tokens"], tarifa: Tarifa): number =>
    (t.input * tarifa.entrada + t.cacheRead * tarifa.entrada * LECTURA_CACHE + t.cacheWrite * tarifa.entrada * ESCRITURA_CACHE + t.output * tarifa.salida) / 1e6;

export interface Resumen { modelo: string; hogares: number; fallos: number; conflictos: number; hogaresConConflicto: number; repeticiones: number; repeticionesHistorial: number; tarjetas: number; casillas: number; tokens: Resultado["tokens"]; coste: number }

export const resumir = (resultados: Resultado[], tarifas: Record<string, Tarifa>): Resumen[] => {
    const modelos = [...new Set(resultados.map((r) => r.modelo))];
    return modelos.map((modelo) => {
        const rs = resultados.filter((r) => r.modelo === modelo);
        const tokens = rs.reduce((t, r) => sumar(t, r.tokens), { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
        const t = tarifas[modelo];
        return {
            modelo, hogares: rs.length, fallos: rs.filter((r) => !r.ok).length, conflictos: rs.reduce((s, r) => s + r.conflictos, 0),
            hogaresConConflicto: rs.filter((r) => r.conflictos > 0).length, repeticiones: rs.reduce((s, r) => s + r.repeticiones, 0),
            repeticionesHistorial: rs.reduce((s, r) => s + r.repeticionesHistorial, 0), tarjetas: rs.filter((r) => r.tarjeta).length,
            casillas: rs.reduce((s, r) => s + r.casillas, 0), tokens, coste: t ? costeUsd(tokens, t) : Number.NaN,
        };
    });
};

const usd = (n: number) => (Number.isFinite(n) ? `${n.toFixed(4)} USD` : "sin tarifa");

export const tablaMarkdown = (resultados: Resultado[], tarifas: Record<string, Tarifa>): string => {
    const res = resumir(resultados, tarifas);
    const l: string[] = [];
    l.push("| Modelo | Hogares | Fallos | Casillas | Conflictos (hogares) | Repeticiones (semana / historial) | Menús mostrados | Tokens entrada | Tokens salida | Caché leída / escrita | Coste estimado |");
    l.push("|---|---|---|---|---|---|---|---|---|---|---|");
    for (const r of res) {
        l.push(`| ${r.modelo} | ${r.hogares} | ${r.fallos} | ${r.casillas} | ${r.conflictos} (${r.hogaresConConflicto}) | ${r.repeticiones} / ${r.repeticionesHistorial} | ${r.tarjetas}/${r.hogares} | ${r.tokens.input} | ${r.tokens.output} | ${r.tokens.cacheRead} / ${r.tokens.cacheWrite} | ${usd(r.coste)} |`);
    }
    l.push("", "Detalle por hogar:", "", "| Hogar | Modelo | OK | Casillas | Conflictos | Rep. semana | Rep. historial | Menú mostrado | Llamadas | Entrada | Salida |", "|---|---|---|---|---|---|---|---|---|---|---|");
    for (const r of resultados) {
        l.push(`| ${r.hogar} | ${r.modelo} | ${r.ok ? "sí" : `no (${r.error})`} | ${r.casillas} | ${r.conflictos} | ${r.repeticiones} | ${r.repeticionesHistorial} | ${r.tarjeta ? "sí" : "no"} | ${r.llamadas} | ${r.tokens.input} | ${r.tokens.output} |`);
    }
    const detalle = resultados.filter((r) => r.detalleConflictos.length > 0);
    if (detalle.length > 0) {
        l.push("", "Conflictos detectados:", "");
        for (const r of detalle) for (const d of r.detalleConflictos.slice(0, 5)) l.push(`- ${r.hogar} (${r.modelo}): ${d}`);
    }
    return l.join("\n");
};

export const cargarFixtures = async (dir: string): Promise<{ hogares: Hogar[]; recetas: Receta[] }> => {
    const recetas = JSON.parse(await Deno.readTextFile(`${dir}/recetas.json`)) as Receta[];
    const hogares: Hogar[] = [];
    const nombres: string[] = [];
    for await (const e of Deno.readDir(dir)) if (e.isFile && e.name.endsWith(".json") && e.name !== "recetas.json") nombres.push(e.name);
    for (const n of nombres.sort()) hogares.push(JSON.parse(await Deno.readTextFile(`${dir}/${n}`)) as Hogar);
    return { hogares, recetas };
};

/** Modelo simulado (--seco y tests): lee el perfil, propone un menú sin conflictos con las recetas seguras y cierra. */
export const modeloSimulado = (hogar: Hogar, recetas: Receta[]): CallModel => {
    let ronda = 0;
    const usage = (i: number, o: number) => ({ input_tokens: i, output_tokens: o, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 });
    return (): Promise<ModelResponse> => {
        ronda++;
        if (ronda > 1) return Promise.resolve({ stop_reason: "end_turn", content: [{ type: "text", text: "Menú propuesto." }], usage: usage(900, 40) });
        const alergias = new Set((hogar.perfil.members as Obj[]).flatMap((m) => ((m.allergies as Obj[]) ?? []).map((a) => String(a.allergen))));
        const seguras = recetas.filter((r) => r.alergenos.every((a) => !alergias.has(a)));
        const franjas = (hogar.perfil.slots as Obj[]).filter((s) => s.enabled).map((s) => String(s.slot));
        const platos: Obj[] = [];
        let n = 0;
        for (let d = 0; d < 7; d++) {
            const dia = new Date(Date.parse(`${hogar.semana}T00:00:00Z`) + d * 86400000).toISOString().slice(0, 10);
            for (const franja of franjas) {
                const aptas = seguras.filter((r) => r.slots.includes(franja));
                platos.push(aptas.length > 0 ? { dia, franja, receta_id: aptas[n++ % aptas.length].id } : { dia, franja, titulo: "Ensalada de la casa" });
            }
        }
        return Promise.resolve({
            stop_reason: "tool_use", content: [{ type: "tool_use", id: "toolu_sim", name: "proponer_menu", input: { semana: hogar.semana, platos } }], usage: usage(1500, 600),
        });
    };
};

const parseArgs = (argv: string[]) => {
    const o = { modelos: ["claude-haiku-5-5", "claude-sonnet-5-5"], hogares: 10, salida: "", seco: false, maxLlamadas: 150, effort: undefined as string | undefined, tarifas: { ...TARIFAS_POR_DEFECTO } };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === "--seco") o.seco = true;
        else if (a === "--modelos") o.modelos = argv[++i].split(",").map((s) => s.trim()).filter(Boolean);
        else if (a === "--hogares") o.hogares = Number(argv[++i]);
        else if (a === "--salida") o.salida = argv[++i];
        else if (a === "--max-llamadas") o.maxLlamadas = Number(argv[++i]);
        else if (a === "--effort") o.effort = argv[++i];
        else if (a === "--tarifa") {
            const [m, t] = argv[++i].split("=");
            const [e, s] = t.split("/").map(Number);
            o.tarifas[m] = { entrada: e, salida: s };
        } else throw new Error(`argumento desconocido: ${a}`);
    }
    return o;
};

export const main = async (argv: string[]): Promise<number> => {
    const o = parseArgs(argv);
    const clavApi = Deno.env.get("ANTHROPIC_API_KEY");
    if (!o.seco && (clavApi === undefined || clavApi.trim() === "")) {
        console.error("Falta ANTHROPIC_API_KEY en el entorno (no se lee de ningún fichero). Usa --seco para la ejecución simulada.");
        return 2;
    }
    const dir = new URL("./fixtures", import.meta.url).pathname;
    const { hogares: todos, recetas } = await cargarFixtures(dir);
    const hogares = todos.slice(0, o.hogares);
    const real = o.seco ? undefined : crearCallModel(clavApi!);
    let total = 0;
    const resultados: Resultado[] = [];
    for (const modelo of o.modelos) {
        for (const h of hogares) {
            if (total >= o.maxLlamadas) {
                console.error(`Tope de ${o.maxLlamadas} llamadas alcanzado; se omite ${modelo} / ${h.id}`);
                continue;
            }
            const cm: CallModel = real
                ? (b, opts) => {
                    total++;
                    return real(b, opts);
                }
                : modeloSimulado(h, recetas);
            const r = await evaluarHogar(h, recetas, modelo, cm, o.effort);
            console.error(`${modelo} ${h.id}: ${r.ok ? "ok" : "ERROR " + r.error} conflictos=${r.conflictos} rep=${r.repeticiones} in=${r.tokens.input} out=${r.tokens.output}`);
            resultados.push(r);
        }
    }
    const tabla = tablaMarkdown(resultados, o.tarifas);
    if (o.salida) await Deno.writeTextFile(o.salida, tabla + "\n");
    else console.log(tabla);
    return 0;
};

if (import.meta.main) Deno.exit(await main(Deno.args));
