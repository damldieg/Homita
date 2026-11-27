// Personas propias del usuario en el hogar activo (Q2). `GET /person` puede traer personas de otros hogares
// del usuario, así que se filtra siempre por `home_id` además de `app_user_id`.
import type { LecturaCtx, Leer } from "./tipos.ts";
import { comoLista, nombre } from "./compacto.ts";

export interface PersonasPropias {
    /** `null` si no se pudo leer (no se debe tratar como «sin personas»). */
    ok: boolean;
    ids: number[];
    nombres: string[];
}

type Fila = Record<string, unknown>;

/** Filas de `GET /person` que pertenecen al hogar activo. */
export const personasDelHogar = (filas: unknown[], homeId: string | null): Fila[] =>
    filas.filter((p): p is Fila => p !== null && typeof p === "object")
        .filter((p) => homeId === null || p.home_id === undefined || String(p.home_id) === homeId);

const cache = new WeakMap<LecturaCtx, Promise<PersonasPropias>>();

const calcular = async (ctx: LecturaCtx, leer: Leer): Promise<PersonasPropias> => {
    const lista = comoLista(await leer("person"));
    if (lista === null) return { ok: false, ids: [], nombres: [] };
    const mias = personasDelHogar(lista, ctx.homeId)
        .filter((p) => ctx.appUserId !== undefined && p.app_user_id !== null && p.app_user_id !== undefined &&
            String(p.app_user_id) === ctx.appUserId)
        .sort((a, b) => Number(a.id) - Number(b.id));
    return { ok: true, ids: mias.map((p) => Number(p.id)), nombres: mias.map((p) => nombre(p.name)) };
};

/** Personas del hogar activo vinculadas a la cuenta del usuario; una lectura por petición. */
export const personasPropias = (ctx: LecturaCtx, leer: Leer): Promise<PersonasPropias> => {
    let p = cache.get(ctx);
    if (!p) {
        p = calcular(ctx, leer);
        cache.set(ctx, p);
    }
    return p;
};

export const AVISO_SIN_PERSONA = "tu cuenta no está vinculada a ninguna persona del hogar";
