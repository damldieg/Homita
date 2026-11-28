// Preparación de las operaciones de tareas: crear, editar, completar y borrar.
import { booleano, detalle, entero, falta, filas, ids, texto, YA_NO_EXISTE } from "./argumentos.ts";
import { fraseEdicion } from "./frases.ts";
import { localAUtc, parsearPared } from "./tiempo.ts";
import { listo } from "./tipos.ts";
import type { ClaveFn, Input, Obj, OrgCtx, Preparacion } from "./tipos.ts";

export const PRIORIDADES = ["alta", "media", "baja"];
const ERROR_VENCE = { ok: false, error: "«vence» debe ser AAAA-MM-DD o AAAA-MM-DD HH:MM (hora local)." };

/** Fecha límite local → instante UTC del api. `""` quita la fecha. `undefined` si no se manda; `null` si no es válida. */
const venceUtc = (input: Input, tz: string): string | undefined | null => {
    if (input.vence === "") return "";
    const v = texto(input, "vence");
    if (v === undefined) return undefined;
    const p = parsearPared(v);
    return p === null ? null : localAUtc(p, tz);
};

/** Lista de destino: la indicada o, si solo hay una donde se pueda escribir, esa. */
export const resolverLista = async (c: OrgCtx, listaId: number | undefined): Promise<
    { id: number; nombre: string } | { falta: Obj } | { error: string }
> => {
    const todas = await filas(c.leer, "task-list");
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

/**
 * Prepara el alta. El cuerpo lleva `due_at` aparte (se fija con un PATCH posterior en `ejecutarAccion`). El
 * `client_request_id` lo calcula quien llama (`clave`) a partir del cuerpo resuelto; no se calcula si hay errores antes.
 */
export const prepararCrearTarea = async (
    input: Input,
    c: OrgCtx,
    clave?: ClaveFn,
): Promise<Preparacion> => {
    const titulo = texto(input, "titulo");
    const lista = await resolverLista(c, entero(input, "lista_id"));
    if ("error" in lista) return listo({ ok: false, error: lista.error });
    if ("falta" in lista) return listo(titulo ? lista.falta : { ...lista.falta, falta: ["titulo", "lista"] });
    if (!titulo) return listo(falta(["titulo"]));
    const prioridad = texto(input, "prioridad");
    if (prioridad !== undefined && !PRIORIDADES.includes(prioridad)) return listo({ ok: false, error: "La prioridad debe ser alta, media o baja." });
    const personas = ids(input, "persona_ids");
    if (personas === null) return listo({ ok: false, error: "persona_ids debe ser una lista de ids." });
    const vence = venceUtc(input, c.timezone);
    if (vence === null) return listo(ERROR_VENCE);
    const args: Obj = { task_list_id: lista.id, title: titulo };
    if (prioridad) args.priority = prioridad;
    if (personas) args.person_ids = personas;
    if (vence) args.due_at = vence;
    const cid = clave ? await clave({ ...args }) : undefined;
    if (cid) args.client_request_id = cid;
    return {
        accion: { op: "crear_tarea", args, nombre: lista.nombre },
        frase: `Creo la tarea «${titulo}» en «${lista.nombre}»`,
        extra: { lista: lista.nombre },
    };
};

export const prepararEditarTarea = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    const titulo = texto(input, "titulo");
    const prioridad = texto(input, "prioridad");
    const personas = ids(input, "persona_ids");
    const vence = venceUtc(input, c.timezone);
    const cambia = titulo !== undefined || prioridad !== undefined || (personas !== undefined) || vence !== undefined;
    const pide = [id === undefined ? "tarea" : "", !cambia ? "qué cambiar" : ""].filter((x) => x);
    if (pide.length) return listo(falta(pide));
    if (prioridad !== undefined && !PRIORIDADES.includes(prioridad)) return listo({ ok: false, error: "La prioridad debe ser alta, media o baja." });
    if (personas === null) return listo({ ok: false, error: "persona_ids debe ser una lista de ids." });
    if (vence === null) return listo(ERROR_VENCE);
    const cur = await detalle(c, "task/detail", id!);
    if (cur === null) return listo(YA_NO_EXISTE);
    // El api exige el título; prioridad, personas y fecha se conservan si no se mandan.
    const args: Obj = { id, title: titulo ?? cur.title };
    if (prioridad) args.priority = prioridad;
    if (personas) args.person_ids = personas;
    if (vence !== undefined) args.due_at = vence;
    const frase = fraseEdicion(`Edito la tarea «${cur.title}»`, [
        ["título", cur.title, titulo], ["prioridad", cur.priority, prioridad], ["personas", cur.person_ids, personas ?? undefined],
        ["fecha límite", cur.due_at, vence],
    ]);
    return { accion: { op: "editar_tarea", args, nombre: String(cur.title) }, frase };
};

export const prepararCompletarTarea = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    if (id === undefined) return listo(falta(["tarea"]));
    const cur = await detalle(c, "task/detail", id);
    if (cur === null) return listo(YA_NO_EXISTE);
    const completed = booleano(input, "completada") ?? true;
    return { accion: { op: "completar_tarea", args: { id, completed }, nombre: String(cur.title) } };
};

export const prepararBorrarTarea = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    if (id === undefined) return listo(falta(["tarea"]));
    const cur = await detalle(c, "task/detail", id);
    if (cur === null) return listo(YA_NO_EXISTE);
    return { accion: { op: "borrar_tarea", args: { id }, nombre: String(cur.title) }, frase: `Borro la tarea «${cur.title}»`, extra: { nombre: String(cur.title) } };
};
