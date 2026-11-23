// contexto.ts — Ficha de contexto de Kito. El núcleo la antepone al último mensaje de usuario como
// `<contexto>{json}</contexto>`; nunca va en `system` (los nombres del hogar los escriben usuarios: son datos,
// no instrucciones, y así `system` + `tools` quedan estables para la caché de prompt).
// Lecturas en paralelo con el lector del usuario (RLS, ACL y hogar activo). Si una falla, esa parte sale como
// "no disponible" y la petición sigue.
import type { ToolCtx } from "./core.ts";
import { comoLista, MAX_ITEMS, nombre } from "./skills/consulta/compacto.ts";
import { isoDeInstante } from "./skills/consulta/fechas.ts";
import { personasDelHogar } from "./skills/consulta/personas.ts";

const NO_DISPONIBLE = "no disponible";

type Obj = Record<string, unknown>;

const leerLista = async (ctx: ToolCtx, ruta: string): Promise<unknown[] | null> => {
    try {
        return comoLista(await ctx.leer!(ruta));
    } catch {
        return null;
    }
};

/** Serializa escapando `<` (como <) para que un nombre no pueda cerrar la etiqueta ni abrir otra. */
export const jsonSeguro = (v: unknown): string => JSON.stringify(v).replaceAll("<", "\\u003c");

const topar = (l: unknown[], f: (x: Obj) => Obj, extra: Obj, clave: string): unknown[] => {
    if (l.length > MAX_ITEMS) extra[`${clave}_hay_mas`] = true;
    return l.slice(0, MAX_ITEMS).map((x) => f((x !== null && typeof x === "object" ? x : {}) as Obj));
};

/** Ficha de contexto lista para anteponer, o null si no hay lector (sin acceso a datos). */
export const construirContexto = async (ctx: ToolCtx): Promise<string | null> => {
    if (!ctx.leer) return null;
    const [personas, calendarios, listas, hogares] = await Promise.all([
        leerLista(ctx, "person"),
        leerLista(ctx, "calendar"),
        leerLista(ctx, "task-list"),
        leerLista(ctx, "home"),
    ]);
    const ficha: Obj = {
        ahora: isoDeInstante(ctx.now.getTime(), ctx.timezone),
        dia_semana: new Intl.DateTimeFormat("es-ES", { timeZone: ctx.timezone, weekday: "long" }).format(ctx.now),
        zona_horaria: ctx.timezone,
    };
    const extra: Obj = {};

    const delHogar = personas === null ? null : personasDelHogar(personas, ctx.homeId);
    const usuario: Obj = {};
    if (ctx.nombreUsuario) usuario.nombre = nombre(ctx.nombreUsuario);
    usuario.personas_vinculadas = delHogar === null
        ? NO_DISPONIBLE
        : delHogar.filter((p) => ctx.appUserId !== undefined && p.app_user_id !== null && p.app_user_id !== undefined &&
            String(p.app_user_id) === ctx.appUserId)
            .map((p) => ({ id: p.id, nombre: nombre(p.name) }));
    ficha.usuario = usuario;

    if (hogares === null) {
        ficha.hogar = NO_DISPONIBLE;
    } else {
        const h = hogares.find((x) => x !== null && typeof x === "object" && String((x as Obj).home_id ?? (x as Obj).id) === ctx.homeId) as Obj | undefined;
        ficha.hogar = h ? nombre(h.name) : NO_DISPONIBLE;
    }
    ficha.personas = delHogar === null ? NO_DISPONIBLE : topar(delHogar, (p) => ({
        id: p.id, nombre: nombre(p.name), tipo: p.kind ?? null, tiene_cuenta: p.app_user_id !== null && p.app_user_id !== undefined,
    }), extra, "personas");
    ficha.calendarios = calendarios === null ? NO_DISPONIBLE : topar(calendarios, (c) => ({ id: c.id, nombre: nombre(c.name) }), extra, "calendarios");
    ficha.listas = listas === null ? NO_DISPONIBLE : topar(listas, (l) => ({
        id: l.id, nombre: nombre(l.name), pendientes: typeof l.pending_task_count === "number" ? l.pending_task_count : 0,
    }), extra, "listas");
    Object.assign(ficha, extra);
    return `<contexto>${jsonSeguro(ficha)}</contexto>`;
};
