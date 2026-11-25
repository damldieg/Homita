// Herramientas de rutinas: crear_rutina, editar_rutina, borrar_rutina.
import type { Tool } from "../../core.ts";
import {
    booleano, despachar, detalle, entero, enteroNoNeg, esquema, falta, herramienta, ids, lista, resolverDestino, texto, YA_NO_EXISTE,
} from "./base.ts";
import type { Input, Obj } from "./base.ts";
import { hoyLocal, paredTexto, parsearPared } from "./tiempo.ts";

const FRECUENCIAS: Record<string, string> = {
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

const crearRutina: Tool = herramienta({
    name: "crear_rutina",
    description:
        "Crea una rutina (algo que se repite). Indispensables: título, calendario (si solo hay uno editable se usa), hora y frecuencia; si es semanal, también los días. Empieza hoy y queda activa salvo que el usuario diga otra fecha de inicio: dilo en la confirmación.",
    input_schema: esquema({
        titulo: { type: "string", description: "Título de la rutina." },
        calendario_id: { type: "integer", description: "Id del calendario (viene en el contexto)." },
        hora: { type: "string", description: "Hora local HH:MM." },
        frecuencia: { type: "string", enum: ["diaria", "semanal", "mensual"], description: "Con qué frecuencia se repite." },
        dias: { type: "array", items: { type: "integer" }, description: "Solo si es semanal: días de la semana del 1 (lunes) al 7 (domingo)." },
        intervalo: { type: "integer", description: "Cada cuántas veces (1 por defecto; 2 = cada dos semanas)." },
        desde: { type: "string", description: "Primer día, AAAA-MM-DD; por defecto hoy." },
        hasta: { type: "string", description: "Último día, AAAA-MM-DD, si termina." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas." },
        alarma_min: { type: "integer", description: "Minutos de antelación del aviso (0 o más)." },
    }, ["titulo", "hora", "frecuencia"]),
    run: async (input, ctx) => {
        const titulo = texto(input, "titulo");
        const hora = texto(input, "hora");
        const d = dias(input);
        const fTxt = texto(input, "frecuencia")?.toLowerCase();
        const frecuencia = fTxt !== undefined ? FRECUENCIAS[fTxt] : (d && d.length > 0 ? "weekly" : undefined);
        const cal = await resolverDestino(ctx, "calendar", "calendario", entero(input, "calendario_id"));
        if ("error" in cal) return { ok: false, error: cal.error };
        const faltan = [
            titulo ? "" : "titulo",
            "falta" in cal ? "calendario" : "",
            hora !== undefined && HORA.test(hora) ? "" : "hora",
            frecuencia ? "" : "frecuencia",
            frecuencia === "weekly" && (d === undefined || d === null || d.length === 0) ? "días" : "",
        ].filter((x) => x);
        if ("falta" in cal) return { ...cal.falta, falta: faltan };
        if (faltan.length) return falta(faltan);
        if (d === null) return ERROR_DIAS;
        const personas = ids(input, "persona_ids");
        if (personas === null) return { ok: false, error: "persona_ids debe ser una lista de ids." };
        const desdeTxt = texto(input, "desde");
        const hastaTxt = texto(input, "hasta");
        const desde = desdeTxt === undefined ? hoyLocal(ctx.now, ctx.timezone) : soloFecha(desdeTxt);
        const hasta = hastaTxt === undefined ? undefined : soloFecha(hastaTxt);
        if (desde === null || hasta === null) return ERROR_FECHA;
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
        return despachar(
            ctx,
            { op: "crear_rutina", args, nombre: cal.nombre },
            {
                frase: `Creo la rutina «${titulo}» ${descripcionHorario(frecuencia!, d ?? [], hora!)} en «${cal.nombre}»`,
                extra: { calendario: cal.nombre, empieza: desde, activa: true, horario: descripcionHorario(frecuencia!, d ?? [], hora!) },
            },
        );
    },
});

const editarRutina: Tool = herramienta({
    name: "editar_rutina",
    description:
        "Cambia una rutina. Indispensable: id de la rutina (ver_rutinas) y al menos un cambio. Solo manda lo que cambia: el resto (fechas de inicio y fin, activa, días) se conserva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la rutina." },
        titulo: { type: "string", description: "Nuevo título." },
        hora: { type: "string", description: "Nueva hora local HH:MM." },
        frecuencia: { type: "string", enum: ["diaria", "semanal", "mensual"], description: "Nueva frecuencia." },
        dias: { type: "array", items: { type: "integer" }, description: "Días de la semana del 1 (lunes) al 7 (domingo)." },
        intervalo: { type: "integer", description: "Cada cuántas veces." },
        desde: { type: "string", description: "Nuevo primer día, AAAA-MM-DD." },
        hasta: { type: "string", description: "Nuevo último día, AAAA-MM-DD; cadena vacía para que no termine." },
        activa: { type: "boolean", description: "false para pausarla, true para reactivarla." },
    }, ["id"]),
    run: async (input, ctx) => {
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
        if (pide.length) return falta(pide);
        if (hora !== undefined && !HORA.test(hora)) return ERROR_HORA;
        if (fTxt !== undefined && FRECUENCIAS[fTxt] === undefined) return { ok: false, error: "La frecuencia debe ser diaria, semanal o mensual." };
        if (d === null) return ERROR_DIAS;
        const desde = desdeTxt === undefined ? undefined : soloFecha(desdeTxt);
        const hasta = hastaTxt === undefined ? undefined : soloFecha(hastaTxt);
        if (desde === null || hasta === null) return ERROR_FECHA;
        const cur = await detalle(ctx, "routine/detail", id!);
        if (cur === null) return YA_NO_EXISTE;
        const frecuencia = fTxt !== undefined ? FRECUENCIAS[fTxt] : String(cur.frequency);
        const diasFinal = frecuencia === "weekly"
            ? (d ?? (Array.isArray(cur.days) ? cur.days as number[] : []))
            : [];
        if (frecuencia === "weekly" && diasFinal.length === 0) return falta(["días"]);
        const horaFinal = hora ?? String(cur.time).slice(0, 5);
        // El api valida la rutina completa y una fecha de fin ausente la borra: se rellena con lo actual.
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
        return despachar(ctx, { op: "editar_rutina", args, nombre: String(cur.title) }, { frase: `Edito la rutina «${cur.title}»` });
    },
});

const borrarRutina: Tool = herramienta({
    name: "borrar_rutina",
    description: "Pide borrar una rutina. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id de la rutina.",
    input_schema: esquema({ id: { type: "integer", description: "Id de la rutina." } }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        if (id === undefined) return falta(["rutina"]);
        const cur = await detalle(ctx, "routine/detail", id);
        if (cur === null) return YA_NO_EXISTE;
        return despachar(ctx, { op: "borrar_rutina", args: { id }, nombre: String(cur.title) }, { frase: `Borro la rutina «${cur.title}»` });
    },
});

export const HERRAMIENTAS_RUTINAS: Tool[] = [crearRutina, editarRutina, borrarRutina];
