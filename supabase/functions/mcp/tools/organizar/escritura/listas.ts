// crear_lista, editar_lista, borrar_lista. La lógica es la de Kito (`_shared/homita/organizar/listas.ts`).
import { McpServer, z } from "../../../deps.ts";
import { prepararBorrarLista, prepararCrearLista, prepararEditarLista } from "../../../../_shared/homita/organizar/listas.ts";
import { arr } from "../../../../_shared/homita/menus.ts";
import type { Obj } from "../../../../_shared/homita/organizar/tipos.ts";
import type { Entorno } from "../../../entorno.ts";
import type { EscrituraCtx } from "../../comun.ts";
import {
    ANOTACIONES_BORRADO, ANOTACIONES_ORGANIZAR, AVISO_ESCRITURA, borrar, campoConfirmado, campoHogar, campoZona, claveOrganizar,
    conHogar, ejecutar, orgCtx, preparar,
} from "../comun.ts";

/** «la lista «X» y sus N tareas (P pendientes, H hechas)». Si la lectura falla, sin cifra: «y todas sus tareas». */
export const describirBorradoLista = async (ctx: EscrituraCtx, id: number, nombre: string, pendientes: number): Promise<string> => {
    try {
        const filas = await ctx.leer("task", { task_list_id: String(id) });
        if (!Array.isArray(filas)) throw new Error("forma");
        const hechas = filas.filter((t) => {
            const c = (t as Obj | null)?.completed_at;
            return c !== null && c !== undefined;
        }).length;
        const total = arr(filas).length;
        return `la lista «${nombre}» y todas sus tareas: ${total} (${total - hechas} pendientes, ${hechas} hechas), más las hechas hace días que la app ya no muestra`;
    } catch {
        return `la lista «${nombre}» y todas sus tareas${pendientes > 0 ? ` (al menos ${pendientes} pendientes)` : ""}`;
    }
};

export const registrarListas = (server: McpServer, env: Entorno): void => {
    server.registerTool("crear_lista", {
        title: "Crear una lista de tareas",
        description:
            `Crea una lista de tareas. Indispensable: nombre. Sin color usa el morado de Homita (#6923E2). Es idempotente: repetir la misma llamada en el mismo minuto no crea otra lista (dos listas idénticas e intencionadas hay que crearlas con más de un minuto de diferencia; si acabas de borrarla y la repites en el mismo minuto puede decir que ya no existe: espera o cambia el nombre). ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            nombre: z.string().describe("Nombre de la lista."),
            color: z.string().optional().describe("Color #RRGGBB, solo si lo piden."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, (ctx, a) => preparar(() => prepararCrearLista(a, claveOrganizar(ctx, "crear_lista"))).then((p) => ejecutar(ctx, p))));

    server.registerTool("editar_lista", {
        title: "Editar una lista de tareas",
        description:
            `Cambia el nombre o el color de una lista. Indispensables: id (ver_listas) y al menos un cambio. Solo manda lo que cambia: el resto se conserva. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id de la lista (ver_listas)."),
            nombre: z.string().optional().describe("Nuevo nombre."),
            color: z.string().optional().describe("Nuevo color #RRGGBB."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararEditarLista(a, orgCtx(ctx))))));

    server.registerTool("borrar_lista", {
        title: "Borrar una lista de tareas",
        description:
            `BORRA una lista con TODAS sus tareas (también las hechas). Es irreversible. Primera llamada SIN confirmado: no borra y te dice qué se borraría; cuéntaselo a la persona, espera un sí explícito y solo entonces repite con confirmado: true. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id de la lista (ver_listas)."),
            confirmado: campoConfirmado,
        }),
        annotations: ANOTACIONES_BORRADO,
    }, conHogar(env, async (ctx, a) => {
        const p = await preparar(() => prepararBorrarLista(a, orgCtx(ctx)));
        return borrar(ctx, p, a.confirmado, (extra, nombre) => describirBorradoLista(ctx, a.id, nombre, Number(extra.pendientes) || 0));
    }));
};
