// Herramientas de tareas: crear_tarea, editar_tarea, completar_tarea, borrar_tarea.
import { fraseEdicion } from "./acciones.ts";
import type { Tool, ToolCtx } from "../../core.ts";
import { booleano, despachar, detalle, entero, esquema, falta, filas, herramienta, ids, texto, YA_NO_EXISTE } from "./base.ts";
import type { Input, Obj } from "./base.ts";
import { localAUtc, parsearPared } from "./tiempo.ts";
import { clientRequestId } from "./uuid.ts";

const PRIORIDADES = ["alta", "media", "baja"];
const ERROR_VENCE = { ok: false, error: "«vence» debe ser AAAA-MM-DD o AAAA-MM-DD HH:MM (hora local)." };

/** Fecha límite local → instante UTC del api. `""` quita la fecha. `undefined` si no se manda; `null` si no es válida. */
const venceUtc = (input: Input, ctx: ToolCtx): string | undefined | null => {
    if (input.vence === "") return "";
    const v = texto(input, "vence");
    if (v === undefined) return undefined;
    const p = parsearPared(v);
    return p === null ? null : localAUtc(p, ctx.timezone);
};

/** Lista de destino: la indicada o, si solo hay una donde se pueda escribir, esa. */
const resolverLista = async (ctx: ToolCtx, listaId: number | undefined): Promise<
    { id: number; nombre: string } | { falta: Obj } | { error: string }
> => {
    const todas = await filas(ctx.leer, "task-list");
    if (todas === null) return { error: "No he podido leer tus listas ahora mismo." };
    if (listaId !== undefined) {
        const l = todas.find((x) => Number(x.id) === listaId);
        return l ? { id: listaId, nombre: String(l.name) } : { error: "Ya no existe." };
    }
    const editables = todas.filter((x) => x.can_edit !== false);
    if (editables.length === 0) return { error: "No tienes ninguna lista donde puedas añadir tareas." };
    if (editables.length === 1) return { id: Number(editables[0].id), nombre: String(editables[0].name) };
    return { falta: falta(["lista"], { opciones: editables.map((x) => ({ id: x.id, nombre: x.name })) }) };
};

const crearTarea: Tool = herramienta({
    name: "crear_tarea",
    description:
        "Crea una tarea en una lista. Indispensables: título y lista (si solo hay una lista editable se usa; si hay varias y no la dicen, devuelve las opciones para preguntar). Opcionales: personas, prioridad y fecha límite.",
    input_schema: esquema({
        titulo: { type: "string", description: "Qué hay que hacer." },
        lista_id: { type: "integer", description: "Id de la lista (viene en el contexto)." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas." },
        prioridad: { type: "string", enum: PRIORIDADES, description: "alta, media o baja." },
        vence: { type: "string", description: "Fecha límite local: AAAA-MM-DD (hasta el final del día) o AAAA-MM-DD HH:MM." },
    }, ["titulo"]),
    run: async (input, ctx, extra) => {
        const titulo = texto(input, "titulo");
        const lista = await resolverLista(ctx, entero(input, "lista_id"));
        if ("error" in lista) return { ok: false, error: lista.error };
        if ("falta" in lista) return titulo ? lista.falta : { ...lista.falta, falta: ["titulo", "lista"] };
        if (!titulo) return falta(["titulo"]);
        const prioridad = texto(input, "prioridad");
        if (prioridad !== undefined && !PRIORIDADES.includes(prioridad)) return { ok: false, error: "La prioridad debe ser alta, media o baja." };
        const personas = ids(input, "persona_ids");
        if (personas === null) return { ok: false, error: "persona_ids debe ser una lista de ids." };
        const vence = venceUtc(input, ctx);
        if (vence === null) return ERROR_VENCE;
        const args: Obj = { task_list_id: lista.id, title: titulo };
        if (prioridad) args.priority = prioridad;
        if (personas) args.person_ids = personas;
        if (vence) args.due_at = vence;
        if (extra?.toolUseId) args.client_request_id = await clientRequestId(ctx.appUserId ?? ctx.uid, ctx.homeId, extra.toolUseId);
        return despachar(
            ctx,
            { op: "crear_tarea", args, nombre: lista.nombre },
            { frase: `Creo la tarea «${titulo}» en «${lista.nombre}»`, extra: { lista: lista.nombre } },
        );
    },
});

const editarTarea: Tool = herramienta({
    name: "editar_tarea",
    description:
        "Cambia una tarea. Indispensable: id de la tarea (ver_tareas) y al menos un cambio. Solo manda lo que cambia: título, personas, prioridad o fecha límite (vence vacío la quita).",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la tarea." },
        titulo: { type: "string", description: "Nuevo título." },
        persona_ids: { type: "array", items: { type: "integer" }, description: "Ids de las personas asignadas (sustituye a las actuales)." },
        prioridad: { type: "string", enum: PRIORIDADES, description: "alta, media o baja." },
        vence: { type: "string", description: "Fecha límite local AAAA-MM-DD o AAAA-MM-DD HH:MM; cadena vacía para quitarla." },
    }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        const titulo = texto(input, "titulo");
        const prioridad = texto(input, "prioridad");
        const personas = ids(input, "persona_ids");
        const vence = venceUtc(input, ctx);
        const cambia = titulo !== undefined || prioridad !== undefined || (personas !== undefined) || vence !== undefined;
        const pide = [id === undefined ? "tarea" : "", !cambia ? "qué cambiar" : ""].filter((x) => x);
        if (pide.length) return falta(pide);
        if (prioridad !== undefined && !PRIORIDADES.includes(prioridad)) return { ok: false, error: "La prioridad debe ser alta, media o baja." };
        if (personas === null) return { ok: false, error: "persona_ids debe ser una lista de ids." };
        if (vence === null) return ERROR_VENCE;
        const cur = await detalle(ctx, "task/detail", id!);
        if (cur === null) return YA_NO_EXISTE;
        // El api exige el título; prioridad, personas y fecha se conservan si no se mandan.
        const args: Obj = { id, title: titulo ?? cur.title };
        if (prioridad) args.priority = prioridad;
        if (personas) args.person_ids = personas;
        if (vence !== undefined) args.due_at = vence;
        const frase = fraseEdicion(`Edito la tarea «${cur.title}»`, [
            ["título", cur.title, titulo], ["prioridad", cur.priority, prioridad], ["personas", cur.person_ids, personas ?? undefined],
            ["fecha límite", cur.due_at, vence],
        ]);
        return despachar(ctx, { op: "editar_tarea", args, nombre: String(cur.title) }, { frase });
    },
});

const completarTarea: Tool = herramienta({
    name: "completar_tarea",
    description: "Marca una tarea como hecha (o como pendiente si completada es false). Indispensable: id de la tarea.",
    input_schema: esquema({
        id: { type: "integer", description: "Id de la tarea." },
        completada: { type: "boolean", description: "true (por defecto) para completarla, false para volver a ponerla pendiente." },
    }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        if (id === undefined) return falta(["tarea"]);
        const cur = await detalle(ctx, "task/detail", id);
        if (cur === null) return YA_NO_EXISTE;
        const completed = booleano(input, "completada") ?? true;
        return despachar(ctx, { op: "completar_tarea", args: { id, completed }, nombre: String(cur.title) });
    },
});

const borrarTarea: Tool = herramienta({
    name: "borrar_tarea",
    description: "Pide borrar una tarea. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id de la tarea.",
    input_schema: esquema({ id: { type: "integer", description: "Id de la tarea." } }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        if (id === undefined) return falta(["tarea"]);
        const cur = await detalle(ctx, "task/detail", id);
        if (cur === null) return YA_NO_EXISTE;
        return despachar(ctx, { op: "borrar_tarea", args: { id }, nombre: String(cur.title) }, { frase: `Borro la tarea «${cur.title}»` });
    },
});

export const HERRAMIENTAS_TAREAS: Tool[] = [crearTarea, editarTarea, completarTarea, borrarTarea];
