// Preparación de las operaciones de calendarios: crear (con compartir), editar y borrar.
//
// «De quién es» un calendario = con quién se comparte: crear pregunta con quién (o «solo yo»). Se comparte por
// persona del hogar con `PATCH /calendar/user` (0029: agrega a la cuenta vinculada a esa persona, sin email): la
// persona debe tener cuenta en Homita. Por defecto el permiso es solo lectura.
import { booleano, entero, falta, filaPorId, filas, lista, objeto, texto, YA_NO_EXISTE } from "./argumentos.ts";
import { fraseEdicion } from "./frases.ts";
import { COLOR_DEFECTO, COLOR_RE, ERROR_COLOR } from "./listas.ts";
import { listo } from "./tipos.ts";
import type { Input, Obj, OrgCtx, Preparacion } from "./tipos.ts";
import { personasDelHogar } from "../personas.ts";

/**
 * Persona del hogar con cuenta a la que se puede dar acceso a un calendario. `{ error }` si no existe en el hogar;
 * `{ sinCuenta }` si no tiene cuenta; `{ propia }` si es el propio usuario (no se comparte consigo mismo).
 */
export const personaConCuenta = (
    todas: Obj[],
    homeId: string | null,
    personaId: number | undefined,
    appUserId: string | undefined,
): { error: string } | { sinCuenta: string } | { propia: true } | { userId: unknown; nombre: string } => {
    const p = personasDelHogar(todas, homeId).find((x) => Number(x.id) === personaId);
    if (!p) return { error: "Esa persona ya no existe en el hogar." };
    if (p.app_user_id === null || p.app_user_id === undefined) return { sinCuenta: String(p.name) };
    if (String(p.app_user_id) === appUserId) return { propia: true };
    return { userId: p.app_user_id, nombre: String(p.name) };
};

export const prepararCrearCalendario = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const nombre = texto(input, "nombre");
    const soloYo = booleano(input, "solo_yo") === true;
    const compartir = lista(input, "compartir_con") ?? [];
    const faltan = [nombre ? "" : "nombre", soloYo || compartir.length > 0 ? "" : "con quién se comparte (o solo para ti)"].filter((x) => x);
    if (faltan.length) return listo(falta(faltan));
    const color = texto(input, "color");
    if (color !== undefined && !COLOR_RE.test(color)) return listo(ERROR_COLOR);

    const destinos: Obj[] = [];
    if (!soloYo) {
        const todas = await filas(c.leer, "person");
        if (todas === null) return listo({ ok: false, error: "No he podido leer las personas del hogar ahora mismo." });
        const sinCuenta: string[] = [];
        for (const item of compartir) {
            const o = objeto(item);
            const r = personaConCuenta(todas, c.homeId, entero(o, "persona_id"), c.appUserId);
            if ("error" in r) return listo({ ok: false, error: r.error });
            if ("sinCuenta" in r) sinCuenta.push(r.sinCuenta);
            else if ("userId" in r) destinos.push({ user_id: r.userId, can_edit: o.puede_editar === true, nombre: r.nombre });
        }
        if (sinCuenta.length > 0) {
            return listo({
                ok: false,
                sin_cuenta: sinCuenta,
                error: `${sinCuenta.join(" y ")} no tiene cuenta en Homita, así que no puedo compartirlo con esa persona. No he creado nada.`,
            });
        }
    }
    const args: Obj = { name: nombre, color: color ?? COLOR_DEFECTO, compartir: destinos };
    const compartido = destinos.map((d) => `${d.nombre} (${d.can_edit ? "puede editar" : "solo lectura"})`);
    return {
        accion: { op: "crear_calendario", args, nombre },
        frase: `Creo el calendario «${nombre}»${compartido.length ? ` compartido con ${compartido.join(", ")}` : " solo para ti"}`,
        extra: { compartido_con: compartido.length ? compartido : "solo contigo", color: args.color },
    };
};

export const prepararEditarCalendario = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    const nombre = texto(input, "nombre");
    const color = texto(input, "color");
    const pide = [id === undefined ? "calendario" : "", nombre === undefined && color === undefined ? "qué cambiar" : ""].filter((x) => x);
    if (pide.length) return listo(falta(pide));
    if (color !== undefined && !COLOR_RE.test(color)) return listo(ERROR_COLOR);
    const cur = await filaPorId(c, "calendar", id!);
    if (cur === null) return listo(YA_NO_EXISTE);
    // El api exige nombre y color, y pone widget/dashboard a true si faltan: se rellenan con lo actual.
    const args: Obj = {
        id,
        name: nombre ?? cur.name,
        color: color ?? cur.color,
        widget: Number(cur.widget) === 1 || cur.widget === true,
        dashboard: Number(cur.dashboard) === 1 || cur.dashboard === true,
    };
    const frase = fraseEdicion(`Edito el calendario «${cur.name}»`, [["nombre", cur.name, nombre], ["color", cur.color, color]]);
    return { accion: { op: "editar_calendario", args, nombre: String(cur.name) }, frase };
};

export const prepararBorrarCalendario = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    if (id === undefined) return listo(falta(["calendario"]));
    const cur = await filaPorId(c, "calendar", id);
    if (cur === null) return listo(YA_NO_EXISTE);
    return {
        accion: { op: "borrar_calendario", args: { id }, nombre: String(cur.name) },
        frase: `Borro el calendario «${cur.name}» con todos sus eventos y rutinas`,
        extra: { nombre: String(cur.name) },
    };
};
