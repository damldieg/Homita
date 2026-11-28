// Preparación de las operaciones de listas de tareas: crear, editar y borrar. Devuelven la acción lista para
// ejecutar (o el resultado ya terminado: «falta», error, «ya no existe»); no llaman al api para escribir.
import { entero, falta, filaPorId, texto, YA_NO_EXISTE } from "./argumentos.ts";
import { fraseEdicion } from "./frases.ts";
import { listo } from "./tipos.ts";
import type { ClaveFn, Input, Obj, OrgCtx, Preparacion } from "./tipos.ts";

/** Mismo color que el api usa por defecto para las listas. */
export const COLOR_DEFECTO = "#6923E2";
export const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
export const ERROR_COLOR = { ok: false, error: "El color debe tener la forma #RRGGBB." };

/** `clave`: calcula la clave de idempotencia a partir del cuerpo resuelto (Kito: por `tool_use.id`; MCP: por contenido y minuto). */
export const prepararCrearLista = async (input: Input, clave?: ClaveFn): Promise<Preparacion> => {
    const nombre = texto(input, "nombre");
    if (!nombre) return listo(falta(["nombre"]));
    const color = texto(input, "color");
    if (color !== undefined && !COLOR_RE.test(color)) return listo(ERROR_COLOR);
    const args: Obj = { name: nombre, color: color ?? COLOR_DEFECTO };
    const cid = clave ? await clave({ ...args }) : undefined;
    if (cid) args.client_request_id = cid;
    return { accion: { op: "crear_lista", args, nombre }, extra: { color: args.color } };
};

export const prepararEditarLista = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    const nombre = texto(input, "nombre");
    const color = texto(input, "color");
    const pide = [id === undefined ? "lista" : "", nombre === undefined && color === undefined ? "qué cambiar" : ""].filter((x) => x);
    if (pide.length) return listo(falta(pide));
    if (color !== undefined && !COLOR_RE.test(color)) return listo(ERROR_COLOR);
    const cur = await filaPorId(c, "task-list", id!);
    if (cur === null) return listo(YA_NO_EXISTE);
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
    return { accion: { op: "editar_lista", args, nombre: String(cur.name) }, frase };
};

/** `extra` lleva el nombre y las pendientes (para que el MCP describa lo que se borraría; Kito lo ignora). */
export const prepararBorrarLista = async (input: Input, c: OrgCtx): Promise<Preparacion> => {
    const id = entero(input, "id");
    if (id === undefined) return listo(falta(["lista"]));
    const cur = await filaPorId(c, "task-list", id);
    if (cur === null) return listo(YA_NO_EXISTE);
    const n = Number(cur.pending_task_count) || 0;
    const frase = n > 0
        ? `Borro la lista «${cur.name}» y sus tareas (${n} pendientes)`
        : `Borro la lista «${cur.name}»`;
    return { accion: { op: "borrar_lista", args: { id }, nombre: String(cur.name) }, frase, extra: { nombre: String(cur.name), pendientes: n } };
};
