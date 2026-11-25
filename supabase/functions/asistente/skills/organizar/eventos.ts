// Herramientas de eventos: crear_evento, editar_evento, borrar_evento.
import { fraseEdicion } from "./acciones.ts";
import type { Tool } from "../../core.ts";
import {
    despachar, detalle, entero, enteroNoNeg, esquema, falta, herramienta, ids, resolverDestino, texto, YA_NO_EXISTE,
} from "./base.ts";
import type { Obj } from "./base.ts";
import { paredTexto, parsearPared } from "./tiempo.ts";

const ERROR_INICIO = { ok: false, error: "«inicio» debe ser AAAA-MM-DD HH:MM (hora local)." };
const ERROR_FIN = { ok: false, error: "«fin» debe ser una fecha AAAA-MM-DD." };

/** 'AAAA-MM-DD' → fecha de fin; `null` si no es válida. */
const finDe = (v: string): string | null => {
    const p = parsearPared(v);
    return p === null || p.h !== null ? null : paredTexto(p).slice(0, 10);
};

const cuando = (dateAt: unknown): string => {
    const m = /^\d{4}-(\d{2})-(\d{2}) (\d{2}:\d{2})/.exec(String(dateAt));
    return m ? ` del ${m[2]}/${m[1]} a las ${m[3]}` : "";
};

const crearEvento: Tool = herramienta({
    name: "crear_evento",
    description:
        "Crea un evento en un calendario. Indispensables: título, inicio (fecha y hora) y calendario (si solo hay uno editable se usa; si hay varios y no lo dicen, devuelve las opciones para preguntar). Opcionales: fin (solo para eventos de varios días), personas y alarma. La descripción no se puede guardar.",
    input_schema: esquema({
        titulo: { type: "string", description: "Título del evento." },
        inicio: { type: "string", description: "Inicio local, AAAA-MM-DD HH:MM." },
        calendario_id: { type: "integer", description: "Id del calendario (viene en el contexto)." },
        fin: { type: "string", description: "Último día, AAAA-MM-DD, solo si dura varios días." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas." },
        alarma_min: { type: "integer", description: "Minutos de antelación del aviso (0 o más)." },
    }, ["titulo", "inicio"]),
    run: async (input, ctx) => {
        const titulo = texto(input, "titulo");
        const inicio = texto(input, "inicio");
        const pared = inicio === undefined ? null : parsearPared(inicio);
        const cal = await resolverDestino(ctx, "calendar", "calendario", entero(input, "calendario_id"));
        if ("error" in cal) return { ok: false, error: cal.error };
        const faltan = [titulo ? "" : "titulo", inicio === undefined || (pared !== null && pared.h === null) ? "inicio (fecha y hora)" : "",
            "falta" in cal ? "calendario" : ""].filter((x) => x);
        if ("falta" in cal) return { ...cal.falta, falta: faltan };
        if (faltan.length) return falta(faltan);
        if (pared === null) return ERROR_INICIO;
        const personas = ids(input, "persona_ids");
        if (personas === null) return { ok: false, error: "persona_ids debe ser una lista de ids." };
        const finTxt = texto(input, "fin");
        const fin = finTxt === undefined ? undefined : finDe(finTxt);
        if (fin === null) return ERROR_FIN;
        const alarma = enteroNoNeg(input, "alarma_min");
        const args: Obj = { calendar_id: cal.id, title: titulo, date_at: paredTexto(pared) };
        if (alarma !== undefined) args.alarm = alarma;
        if (personas) args.person_ids = personas;
        if (fin) args.end_date = fin;
        return despachar(
            ctx,
            { op: "crear_evento", args, nombre: cal.nombre },
            { frase: `Creo el evento «${titulo}»${cuando(args.date_at)} en «${cal.nombre}»`, extra: { calendario: cal.nombre, inicio: args.date_at } },
        );
    },
});

const editarEvento: Tool = herramienta({
    name: "editar_evento",
    description:
        "Cambia un evento. Indispensable: id del evento (ver_eventos) y al menos un cambio. Solo manda lo que cambia (título, inicio, fin, personas, alarma): el resto se conserva, incluida la alarma. Si solo cambia la hora, manda inicio con la misma fecha y la hora nueva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id del evento." },
        titulo: { type: "string", description: "Nuevo título." },
        inicio: { type: "string", description: "Nuevo inicio local, AAAA-MM-DD HH:MM (o solo AAAA-MM-DD para mover el día y conservar la hora)." },
        fin: { type: "string", description: "Nuevo último día, AAAA-MM-DD." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas (sustituye a las actuales)." },
        alarma_min: { type: "integer", description: "Minutos de antelación del aviso (0 o más)." },
    }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        const titulo = texto(input, "titulo");
        const inicio = texto(input, "inicio");
        const finTxt = texto(input, "fin");
        const personas = ids(input, "persona_ids");
        const alarma = enteroNoNeg(input, "alarma_min");
        const cambia = titulo !== undefined || inicio !== undefined || finTxt !== undefined || personas !== undefined || alarma !== undefined;
        const pide = [id === undefined ? "evento" : "", !cambia ? "qué cambiar" : ""].filter((x) => x);
        if (pide.length) return falta(pide);
        const pared = inicio === undefined ? undefined : parsearPared(inicio);
        if (pared === null) return ERROR_INICIO;
        const fin = finTxt === undefined ? undefined : finDe(finTxt);
        if (fin === null) return ERROR_FIN;
        if (personas === null) return { ok: false, error: "persona_ids debe ser una lista de ids." };
        const cur = await detalle(ctx, "event/detail", id!);
        if (cur === null) return YA_NO_EXISTE;
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
        return despachar(ctx, { op: "editar_evento", args, nombre: String(cur.title) }, {
            frase: fraseEdicion(`Edito el evento «${cur.title}»${cuando(dateAtActual)}`, [
                ["título", cur.title, titulo], ["inicio", dateAtActual, pared ? args.date_at : undefined],
                ["último día", cur.end_date, fin ?? undefined], ["personas", cur.person_ids, personas ?? undefined],
                ["alarma (min)", cur.alarm, alarma],
            ]),
        });
    },
});

const borrarEvento: Tool = herramienta({
    name: "borrar_evento",
    description: "Pide borrar un evento. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id del evento.",
    input_schema: esquema({ id: { type: "integer", description: "Id del evento." } }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        if (id === undefined) return falta(["evento"]);
        const cur = await detalle(ctx, "event/detail", id);
        if (cur === null) return YA_NO_EXISTE;
        return despachar(ctx, { op: "borrar_evento", args: { id }, nombre: String(cur.title) }, { frase: `Borro el evento «${cur.title}»${cuando(cur.date_at)}` });
    },
});

export const HERRAMIENTAS_EVENTOS: Tool[] = [crearEvento, editarEvento, borrarEvento];
