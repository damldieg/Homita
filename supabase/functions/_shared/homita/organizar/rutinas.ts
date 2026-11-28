// Preparación de las operaciones de rutinas: crear, editar y borrar.
import { booleano, detalle, entero, enteroNoNeg, falta, ids, lista, resolverDestino, texto, YA_NO_EXISTE } from "./argumentos.ts";
import { fraseEdicion } from "./frases.ts";
import { hoyLocal, paredTexto, parsearPared } from "./tiempo.ts";
import { listo } from "./tipos.ts";
import type { Input, Obj, OrgCtx, Preparacion } from "./tipos.ts";

export const FRECUENCIAS: Record<string, string> = {
    diaria: "daily", daily: "daily", semanal: "weekly", weekly: "weekly", mensual: "monthly", monthly: "monthly",
};
const HORA = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const ERROR_FECHA = { ok: false, error: "Las fechas deben ser AAAA-MM-DD." };
const ERROR_HORA = { ok: false, error: "La hora debe ser HH:MM." };
const ERROR_DIAS = { ok: false, error: "Los días son números del 1 (lunes) al 7 (domingo)." };

const soloFecha = (v: string): string | null => {
    const p = parsearPared(v);
    return p === null || p.h !== null ? null : paredTexto(p).slice(0, 10);
};

/** Días de la semana 1..7 sin repetir; `null` si algún valor no es válido; `undefined` si no se manda. */
const dias = (input: Input): number[] | null | undefined => {
    const l = lista(input, "dias");
    if (l === undefined) return undefined;
    const r = l.filter((d): d is number => typeof d === "number" && Number.isInteger(d) && d >= 1 && d <= 7);
    return r.length === l.length ? [...new Set(r)].sort((a, b) => a - b) : null;
};

const NOMBRES_DIAS = ["", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
const descripcionHorario = (frecuencia: string, d: number[], hora: string): string =>
    `${frecuencia === "weekly" ? `los ${d.map((x) => NOMBRES_DIAS[x]).join(", ")}` : frecuencia === "daily" ? "cada día" : "cada mes"} a las ${hora}`;

export const prepararCrearRutina = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const titulo = texto(input, "titulo");
    const hora = texto(input, "hora");
    const d = dias(input);
    const fTxt = texto(input, "frecuencia")?.toLowerCase();
    const frecuencia = fTxt !== undefined ? FRECUENCIAS[fTxt] : (d && d.length > 0 ? "weekly" : undefined);
    const cal = await resolverDestino(c, "calendar", "calendario", entero(input, "calendario_id"));
    if ("error" in cal) return listo({ ok: false, error: cal.error });
    const faltan = [
        titulo ? "" : "titulo",
        "falta" in cal ? "calendario" : "",
        hora !== undefined && HORA.test(hora) ? "" : "hora",
        frecuencia ? "" : "frecuencia",
        frecuencia === "weekly" && (d === undefined || d === null || d.length === 0) ? "días" : "",
    ].filter((x) => x);
    if ("falta" in cal) return listo({ ...cal.falta, falta: faltan });
    if (faltan.length) return listo(falta(faltan));
    if (d === null) return listo(ERROR_DIAS);
    const personas = ids(input, "persona_ids");
    if (personas === null) return listo({ ok: false, error: "persona_ids debe ser una lista de ids." });
    const desdeTxt = texto(input, "desde");
    const hastaTxt = texto(input, "hasta");
    const desde = desdeTxt === undefined ? hoyLocal(c.now, c.timezone) : soloFecha(desdeTxt);
    const hasta = hastaTxt === undefined ? undefined : soloFecha(hastaTxt);
    if (desde === null || hasta === null) return listo(ERROR_FECHA);
    const intervalo = entero(input, "intervalo") ?? 1;
    const alarma = enteroNoNeg(input, "alarma_min");
    // start_date y active son obligatorios para el api: por defecto, hoy y activa (Kito lo dice al confirmar).
    const args: Obj = {
        calendar_id: cal.id, title: titulo, frequency: frecuencia, interval: intervalo,
        days: frecuencia === "weekly" ? d : [], time: hora, start_date: desde, active: true,
    };
    if (hasta) args.end_date = hasta;
    if (alarma !== undefined) args.alarm = alarma;
    if (personas) args.person_ids = personas;
    return {
        accion: { op: "crear_rutina", args, nombre: cal.nombre },
        frase: `Creo la rutina «${titulo}» ${descripcionHorario(frecuencia!, d ?? [], hora!)} en «${cal.nombre}»`,
        extra: { calendario: cal.nombre, empieza: desde, activa: true, horario: descripcionHorario(frecuencia!, d ?? [], hora!) },
    };
};

export const prepararEditarRutina = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    const titulo = texto(input, "titulo");
    const hora = texto(input, "hora");
    const fTxt = texto(input, "frecuencia")?.toLowerCase();
    const d = dias(input);
    const intervalo = entero(input, "intervalo");
    const desdeTxt = texto(input, "desde");
    const hastaTxt = texto(input, "hasta");
    const activa = booleano(input, "activa");
    const cambia = [titulo, hora, fTxt, d, intervalo, desdeTxt, hastaTxt, activa, input.hasta === "" ? "" : undefined].some((v) => v !== undefined);
    const pide = [id === undefined ? "rutina" : "", !cambia ? "qué cambiar" : ""].filter((x) => x);
    if (pide.length) return listo(falta(pide));
    if (hora !== undefined && !HORA.test(hora)) return listo(ERROR_HORA);
    if (fTxt !== undefined && FRECUENCIAS[fTxt] === undefined) return listo({ ok: false, error: "La frecuencia debe ser diaria, semanal o mensual." });
    if (d === null) return listo(ERROR_DIAS);
    const desde = desdeTxt === undefined ? undefined : soloFecha(desdeTxt);
    const hasta = hastaTxt === undefined ? undefined : soloFecha(hastaTxt);
    if (desde === null || hasta === null) return listo(ERROR_FECHA);
    const cur = await detalle(c, "routine/detail", id!);
    if (cur === null) return listo(YA_NO_EXISTE);
    const frecuencia = fTxt !== undefined ? FRECUENCIAS[fTxt] : String(cur.frequency);
    const diasFinal = frecuencia === "weekly"
        ? (d ?? (Array.isArray(cur.days) ? cur.days as number[] : []))
        : [];
    if (frecuencia === "weekly" && diasFinal.length === 0) return listo(falta(["días"]));
    const horaFinal = hora ?? String(cur.time).slice(0, 5);
    // El api valida la rutina completa y una fecha de fin ausente la borra: se rellena con lo actual. Las personas
    // asignadas no se mandan: el api las conserva si falta `person_ids` (0029: `v_persons is not null` para cambiarlas).
    const args: Obj = {
        id,
        title: titulo ?? cur.title,
        frequency: frecuencia,
        interval: intervalo ?? cur.interval ?? 1,
        days: diasFinal,
        time: horaFinal,
        start_date: desde ?? cur.start_date,
        end_date: input.hasta === "" ? null : (hasta ?? cur.end_date ?? null),
        active: activa ?? cur.active !== false,
    };
    return {
        accion: { op: "editar_rutina", args, nombre: String(cur.title) },
        frase: fraseEdicion(`Edito la rutina «${cur.title}»`, [
            ["título", cur.title, titulo], ["hora", String(cur.time).slice(0, 5), hora], ["frecuencia", cur.frequency, fTxt === undefined ? undefined : frecuencia],
            ["días", cur.days, d ?? undefined], ["intervalo", cur.interval, intervalo], ["desde", cur.start_date, desde ?? undefined],
            ["hasta", cur.end_date, input.hasta === "" ? null : (hasta ?? undefined)],
            ["activa", cur.active !== false ? "sí" : "no", activa === undefined ? undefined : activa ? "sí" : "no"],
        ]),
    };
};

export const prepararBorrarRutina = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    if (id === undefined) return listo(falta(["rutina"]));
    const cur = await detalle(c, "routine/detail", id);
    if (cur === null) return listo(YA_NO_EXISTE);
    return { accion: { op: "borrar_rutina", args: { id }, nombre: String(cur.title) }, frase: `Borro la rutina «${cur.title}»`, extra: { nombre: String(cur.title) } };
};
