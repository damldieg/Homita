// Resolución del hogar de cada llamada. `hogar` es opcional en todas las herramientas de lectura:
//  - Con `hogar`: el usuario debe ser miembro (`checkHomeMember`). Si no lo es -> error claro y no se llama a ningún
//    caso de uso (un hogar ajeno y uno que no existe dan el mismo mensaje).
//  - Sin `hogar`: el predeterminado de `GET /home` (`is_default`); si no hay marca y solo tiene uno, ese; si tiene
//    varios sin predeterminado, error que pide `hogar`.
import { ErrorApi } from "./errores.ts";
import type { Entorno } from "./entorno.ts";

const HOME_RE = /^[0-9]{1,18}$/;

export type HogarResuelto = { ok: true; homeId: string } | { ok: false; mensaje: string };

export interface FilaHogar {
    id: string;
    nombre: string;
    rol: string | null;
    predeterminado: boolean;
    personal: boolean;
}

/** Hogares del usuario (`GET /home`), sin hogar activo. Lanza `ErrorApi` si el api falla. */
export const leerHogares = async (env: Entorno, tz: string): Promise<FilaHogar[]> => {
    const r = await env.leerRuta("home", {}, env.token, env.uid, tz);
    if (!r.ok || !r.json || !Array.isArray(r.body)) throw new ErrorApi(r.ok ? 502 : r.status);
    return r.body.filter((h): h is Record<string, unknown> => h !== null && typeof h === "object")
        .map((h) => ({
            id: String(h.home_id),
            nombre: typeof h.name === "string" ? h.name.slice(0, 80) : "",
            rol: typeof h.role === "string" ? h.role : null,
            predeterminado: h.is_default === true,
            personal: h.is_personal === true,
        }));
};

export const resolverHogar = async (hogar: unknown, env: Entorno, tz: string): Promise<HogarResuelto> => {
    if (hogar !== undefined && hogar !== null && hogar !== "") {
        if (typeof hogar !== "string" || !HOME_RE.test(hogar)) {
            return { ok: false, mensaje: "`hogar` debe ser el id numérico de un hogar (lo da ver_hogares)." };
        }
        const homeId = BigInt(hogar).toString();
        if (!(await env.checkHomeMember(homeId, env.token))) {
            return { ok: false, mensaje: "No tienes acceso a ese hogar o no existe. Usa ver_hogares para ver los tuyos." };
        }
        return { ok: true, homeId };
    }
    const hogares = await leerHogares(env, tz);
    if (hogares.length === 0) return { ok: false, mensaje: "No tienes ningún hogar en Homita." };
    const marcado = hogares.find((h) => h.predeterminado);
    if (marcado) return { ok: true, homeId: marcado.id };
    if (hogares.length === 1) return { ok: true, homeId: hogares[0].id };
    return {
        ok: false,
        mensaje: "Tienes varios hogares y ninguno es el predeterminado: indica `hogar` con el id de uno de ver_hogares.",
    };
};
