// Preparación de las operaciones de eventos: crear, editar y borrar.
import { detalle, entero, enteroNoNeg, falta, ids, resolverDestino, texto, YA_NO_EXISTE } from "./argumentos.ts";
import { fraseEdicion } from "./frases.ts";
import { paredTexto, parsearPared } from "./tiempo.ts";
import { listo } from "./tipos.ts";
import type { Input, Obj, OrgCtx, Preparacion } from "./tipos.ts";

const ERROR_INICIO = { ok: false, error: "«inicio» debe ser AAAA-MM-DD HH:MM (hora local)." };
const ERROR_FIN = { ok: false, error: "«fin» debe ser una fecha AAAA-MM-DD." };

/** 'AAAA-MM-DD' → fecha de fin; `null` si no es válida. */
const finDe = (v: string): string | null => {
    const p = parsearPared(v);
    return p === null || p.h !== null ? null : paredTexto(p).slice(0, 10);
};

/** « del 12/01 a las 20:30» a partir de `date_at`; vacío si no tiene esa forma. */
export const cuando = (dateAt: unknown): string => {
    const m = /^\d{4}-(\d{2})-(\d{2}) (\d{2}:\d{2})/.exec(String(dateAt));
    return m ? ` del ${m[2]}/${m[1]} a las ${m[3]}` : "";
};

export const prepararCrearEvento = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const titulo = texto(input, "titulo");
    const inicio = texto(input, "inicio");
    const pared = inicio === undefined ? null : parsearPared(inicio);
    const cal = await resolverDestino(c, "calendar", "calendario", entero(input, "calendario_id"));
    if ("error" in cal) return listo({ ok: false, error: cal.error });
    const faltan = [titulo ? "" : "titulo", inicio === undefined || (pared !== null && pared.h === null) ? "inicio (fecha y hora)" : "",
        "falta" in cal ? "calendario" : ""].filter((x) => x);
    if ("falta" in cal) return listo({ ...cal.falta, falta: faltan });
    if (faltan.length) return listo(falta(faltan));
    if (pared === null) return listo(ERROR_INICIO);
    const personas = ids(input, "persona_ids");
    if (personas === null) return listo({ ok: false, error: "persona_ids debe ser una lista de ids." });
    const finTxt = texto(input, "fin");
    const fin = finTxt === undefined ? undefined : finDe(finTxt);
    if (fin === null) return listo(ERROR_FIN);
    const alarma = enteroNoNeg(input, "alarma_min");
    const args: Obj = { calendar_id: cal.id, title: titulo, date_at: paredTexto(pared!) };
    if (alarma !== undefined) args.alarm = alarma;
    if (personas) args.person_ids = personas;
    if (fin) args.end_date = fin;
    return {
        accion: { op: "crear_evento", args, nombre: cal.nombre },
        frase: `Creo el evento «${titulo}»${cuando(args.date_at)} en «${cal.nombre}»`,
        extra: { calendario: cal.nombre, inicio: args.date_at },
    };
};

export const prepararEditarEvento = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    const titulo = texto(input, "titulo");
    const inicio = texto(input, "inicio");
    const finTxt = texto(input, "fin");
    const personas = ids(input, "persona_ids");
    const alarma = enteroNoNeg(input, "alarma_min");
    const cambia = titulo !== undefined || inicio !== undefined || finTxt !== undefined || personas !== undefined || alarma !== undefined;
    const pide = [id === undefined ? "evento" : "", !cambia ? "qué cambiar" : ""].filter((x) => x);
    if (pide.length) return listo(falta(pide));
    const pared = inicio === undefined ? undefined : parsearPared(inicio);
    if (pared === null) return listo(ERROR_INICIO);
    const fin = finTxt === undefined ? undefined : finDe(finTxt);
    if (fin === null) return listo(ERROR_FIN);
    if (personas === null) return listo({ ok: false, error: "persona_ids debe ser una lista de ids." });
    const cur = await detalle(c, "event/detail", id!);
    if (cur === null) return listo(YA_NO_EXISTE);
    const dateAtActual = String(cur.date_at);
    // El api exige título e inicio, y una alarma ausente la borra: se rellenan con lo actual.
    const args: Obj = {
        id,
        title: titulo ?? cur.title,
        date_at: pared ? paredTexto(pared, dateAtActual.slice(11, 16)) : dateAtActual,
        alarm: alarma ?? cur.alarm ?? null,
    };
    if (fin) args.end_date = fin;
    if (personas) args.person_ids = personas;
    return {
        accion: { op: "editar_evento", args, nombre: String(cur.title) },
        frase: fraseEdicion(`Edito el evento «${cur.title}»${cuando(dateAtActual)}`, [
            ["título", cur.title, titulo], ["inicio", dateAtActual, pared ? args.date_at : undefined],
            ["último día", cur.end_date, fin ?? undefined], ["personas", cur.person_ids, personas ?? undefined],
            ["alarma (min)", cur.alarm, alarma],
        ]),
    };
};

export const prepararBorrarEvento = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    if (id === undefined) return listo(falta(["evento"]));
    const cur = await detalle(c, "event/detail", id);
    if (cur === null) return listo(YA_NO_EXISTE);
    return {
        accion: { op: "borrar_evento", args: { id }, nombre: String(cur.title) },
        frase: `Borro el evento «${cur.title}»${cuando(cur.date_at)}`,
        extra: { nombre: String(cur.title), cuando: cuando(cur.date_at) },
    };
};
