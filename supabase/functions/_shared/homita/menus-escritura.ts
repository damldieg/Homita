// Reglas de las casillas del menú, compartidas por Kito y el MCP: validar los platos de una semana, convertirlos en
// casillas del api y comparar con las ya guardadas. Movido sin cambios de lógica desde `asistente/skills/menus/menu.ts`.
// Los tipos son los del api (`recipe`, `free_text`, `leftovers`, `eat_out`); el MCP usa nombres en español y los
// traduce con `TIPOS_MCP`.
import { MAX_ERRORES } from "./conflictos.ts";
import {
    arr, comensalesEn, diaNombre, entero, esFecha, FRANJA_ES, FRANJAS, isoDow, norm, obj, str, sumarDias,
} from "./menus.ts";
import type { Obj } from "./menus.ts";

export const MAX_PLATOS = 60;
export const TIPOS = ["recipe", "free_text", "leftovers", "eat_out"] as const;

/** Tipos del MCP (español) -> tipos del api. */
export const TIPOS_MCP = { receta: "recipe", texto: "free_text", sobras: "leftovers", fuera: "eat_out" } as const;
export type TipoMcp = keyof typeof TIPOS_MCP;
export const tipoApi = (t: TipoMcp): (typeof TIPOS)[number] => TIPOS_MCP[t];
export const tipoMcp = (t: string): TipoMcp | undefined =>
    (Object.keys(TIPOS_MCP) as TipoMcp[]).find((k) => TIPOS_MCP[k] === t);

export interface Plato {
    dia: string;
    franja: string;
    tipo: (typeof TIPOS)[number];
    receta_id?: number;
    titulo?: string;
    personas?: number[];
}

export const validarPlatos = (crudo: unknown, semana: string, perfil: Obj): { platos: Plato[] } | { errores: string[] } => {
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

export const itemDe = (p: Plato): Obj => ({
    day: p.dia, slot: p.franja, position: 0, kind: p.tipo,
    ...(p.tipo === "recipe" ? { recipe_id: p.receta_id } : p.tipo === "free_text" || p.titulo ? { title: p.titulo } : {}),
    ...(p.personas ? { members: p.personas } : {}),
});

export const claveCasilla = (dia: unknown, franja: unknown, tipo: unknown, receta: unknown, titulo: unknown): string =>
    `${dia}|${franja}|${tipo}|${receta ?? ""}|${tipo === "recipe" ? "" : norm(String(titulo ?? ""))}`;

/** `true` si las casillas no bloqueadas del plan son exactamente los platos propuestos (mismo día, franja y plato). */
export const yaCoincide = (existentes: Obj[], platos: Plato[]): boolean => {
    const libres = existentes.filter((i) => i.state !== "locked").map((i) => claveCasilla(i.day, i.slot, i.kind, i.recipe_id, i.title));
    const nuevos = platos.map((p) => claveCasilla(p.dia, p.franja, p.tipo, p.receta_id, p.titulo));
    if (libres.length !== nuevos.length) return false;
    const a = [...libres].sort();
    const b = [...nuevos].sort();
    return a.every((x, n) => x === b[n]) && !existentes.some((i) => i.state === "rejected");
};
