// Herramientas de listas de tareas: crear_lista, editar_lista, borrar_lista.
import { fraseEdicion } from "./acciones.ts";
import type { Tool } from "../../core.ts";
import { despachar, entero, esquema, falta, filaPorId, herramienta, texto, YA_NO_EXISTE } from "./base.ts";
import type { Obj } from "./base.ts";
import { clientRequestId } from "./uuid.ts";

/** Mismo color que el api usa por defecto para las listas. */
export const COLOR_DEFECTO = "#6923E2";
export const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
export const ERROR_COLOR = { ok: false, error: "El color debe tener la forma #RRGGBB." };

const crearLista: Tool = herramienta({
    name: "crear_lista",
    description: "Crea una lista de tareas. Indispensable: nombre. Si no dan color, se usa el morado de Homita (#6923E2).",
    input_schema: esquema({
        nombre: { type: "string", description: "Nombre de la lista." },
        color: { type: "string", description: "Color #RRGGBB, solo si lo piden." },
    }, ["nombre"]),
    run: async (input, ctx, extra) => {
        const nombre = texto(input, "nombre");
        if (!nombre) return falta(["nombre"]);
        const color = texto(input, "color");
        if (color !== undefined && !COLOR_RE.test(color)) return ERROR_COLOR;
        const args: Obj = { name: nombre, color: color ?? COLOR_DEFECTO };
        if (extra?.toolUseId) args.client_request_id = await clientRequestId(ctx.appUserId ?? ctx.uid, ctx.homeId, extra.toolUseId);
        return despachar(ctx, { op: "crear_lista", args, nombre }, { extra: { color: args.color } });
    },
});

const editarLista: Tool = herramienta({
    name: "editar_lista",
    description:
        "Cambia el nombre o el color de una lista. Indispensable: id de la lista (viene en el contexto) y al menos un cambio. Solo manda lo que cambia: el resto se conserva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la lista." },
        nombre: { type: "string", description: "Nuevo nombre." },
        color: { type: "string", description: "Nuevo color #RRGGBB." },
    }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        const nombre = texto(input, "nombre");
        const color = texto(input, "color");
        const pide = [id === undefined ? "lista" : "", nombre === undefined && color === undefined ? "qué cambiar" : ""].filter((x) => x);
        if (pide.length) return falta(pide);
        if (color !== undefined && !COLOR_RE.test(color)) return ERROR_COLOR;
        const cur = await filaPorId(ctx, "task-list", id!);
        if (cur === null) return YA_NO_EXISTE;
        // El api exige nombre, color y orden, y pone widget/dashboard a true si faltan: se rellenan con lo actual.
        const args: Obj = {
            id,
            name: nombre ?? cur.name,
            color: color ?? cur.color,
            sort: cur.sort ?? "updated_at",
            widget: Number(cur.widget) === 1 || cur.widget === true,
            dashboard: Number(cur.dashboard) === 1 || cur.dashboard === true,
        };
        const frase = fraseEdicion(`Edito la lista «${cur.name}»`, [["nombre", cur.name, nombre], ["color", cur.color, color]]);
        return despachar(ctx, { op: "editar_lista", args, nombre: String(cur.name) }, { frase });
    },
});

const borrarLista: Tool = herramienta({
    name: "borrar_lista",
    description:
        "Pide borrar una lista con todas sus tareas. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id de la lista.",
    input_schema: esquema({ id: { type: "integer", description: "Id de la lista." } }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        if (id === undefined) return falta(["lista"]);
        const cur = await filaPorId(ctx, "task-list", id);
        if (cur === null) return YA_NO_EXISTE;
        const n = Number(cur.pending_task_count) || 0;
        const frase = n > 0
            ? `Borro la lista «${cur.name}» y sus tareas (${n} pendientes)`
            : `Borro la lista «${cur.name}»`;
        return despachar(ctx, { op: "borrar_lista", args: { id }, nombre: String(cur.name) }, { frase });
    },
});

export const HERRAMIENTAS_LISTAS: Tool[] = [crearLista, editarLista, borrarLista];
