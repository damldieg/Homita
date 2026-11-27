// Mundo con estado para las pruebas de menús del MCP: reutiliza el api falso de Kito (`asistente/tests/menus_util.ts`:
// revisión, client_request_id, estados, plan aceptado) y lo cuelga de las dependencias del MCP. Uno o dos mundos de
// Kito (uno por semana); la segunda semana se traduce a la del mundo B, igual que en los tests de rango de Kito.
import { crearMundo as crearMundoKito } from "../../asistente/tests/menus_util.ts";
import type { Mundo as MundoKito } from "../../asistente/tests/menus_util.ts";
import { currentHome } from "../../api/_shared/home.ts";
import { crearMundo, HOGARES } from "./util.ts";
import type { Mundo } from "./util.ts";

export { casilla, ANA, LEO, perfilBase, SEMANA } from "../../asistente/tests/menus_util.ts";
export type { MundoKito };
export const SEMANA2 = "2030-01-14";

type Obj = Record<string, unknown>;

/** Dependencias del MCP respaldadas por los mundos de Kito. `semanas` = [semana del mundo A, semana del mundo B]. */
export const mundoMenus = (
    a: MundoKito, b?: MundoKito, extra: { respuestas?: Record<string, unknown>; escribir?: Record<string, (c: Obj) => { ok: boolean; status: number; data: unknown; error?: string }> } = {},
): Mundo => {
    const esB = (semana: unknown) => b !== undefined && semana === SEMANA2;
    const aB = <T extends Obj>(o: T): T => ({ ...o, week_start: "2030-01-07" });
    const leerKito = async (ruta: string, params: Record<string, string | undefined>): Promise<unknown> => {
        if (ruta === "meal/plan") return esB(params.week_start) ? await b!.leer(ruta, aB(params)) : await a.leer(ruta, params);
        if (ruta === "meal/plan/check") {
            const ra = await a.leer(ruta, params);
            if (Array.isArray(ra) || b === undefined) return ra;
            return await b.leer(ruta, params);
        }
        return await a.leer(ruta, params);
    };
    const mundo: Mundo = crearMundo({}, {
        leerRuta: async (ruta, params, token, uid, tz) => {
            mundo.llamadas.push({ ruta, params, token, uid, tz, hogar: currentHome() });
            mundo.orden.push(`GET ${ruta}`);
            let body: unknown;
            if (ruta === "home") body = HOGARES;
            else if (extra.respuestas && ruta in extra.respuestas) body = extra.respuestas[ruta];
            else body = await leerKito(ruta, params);
            return { ok: true, status: 200, body, texto: JSON.stringify(body), json: true };
        },
        crearEscritor: () => async (metodo, ruta, cuerpo = {}) => {
            mundo.escrituras.push({ metodo, ruta, cuerpo, token: "", uid: "", tz: "", hogar: currentHome() });
            mundo.orden.push(`${metodo} ${ruta}`);
            const f = extra.escribir?.[`${metodo} ${ruta}`];
            if (f) return f(cuerpo);
            if (esB(cuerpo.week_start) && ruta === "meal/plan/items") return await b!.escribir(metodo as "PATCH", ruta, aB(cuerpo));
            return await a.escribir(metodo as "PATCH", ruta, cuerpo);
        },
    });
    return mundo;
};
