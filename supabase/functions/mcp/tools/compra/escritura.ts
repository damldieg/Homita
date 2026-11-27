// apuntar_compra y marcar_comprado. Solo lo que la persona pide: los ingredientes del menú entran solos en la Compra al
// aceptarlo. Éxito parcial: cada artículo va por separado y se informa de los que fallan.
import { McpServer, z } from "../../deps.ts";
import { idCompra } from "../../../_shared/homita/idempotencia.ts";
import { arr, entero, norm, obj, str } from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import { textoDeEscritura } from "../../errores.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_ESCRITURA, AVISO_DATOS, campoHogar, campoZona, escribirEnHogar } from "../comun.ts";
import type { EscrituraCtx } from "../comun.ts";

const MAX_ARTICULOS = 20;
const MAX_ITEMS = 50;
const UNIDADES = ["g", "kg", "ml", "l", "ud", "cda", "cdta", "pizca"] as const;
const ESTADOS = ["pending", "checked", "skipped"] as const;

/** Fecha local (AAAA-MM-DD) de ahora en la zona del usuario: la «ventana» de idempotencia de la compra. */
const diaLocal = (ctx: EscrituraCtx): string => ctx.now.toLocaleDateString("sv-SE", { timeZone: ctx.timezone });

const texto = (r: { status: number; error?: string }): string => textoDeEscritura(r.status, r.error);

/** `apuntar_compra`: hasta 20 artículos; mismo artículo el mismo día local = un solo apunte. */
export const apuntarCompra = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    const lista = arr(a.articulos).map(obj);
    if (lista.length === 0) return { ok: false, error: "Pasa al menos un artículo." };
    if (lista.length > MAX_ARTICULOS) return { ok: false, error: `Como máximo ${MAX_ARTICULOS} artículos por llamada.` };
    const dia = diaLocal(ctx);
    const apuntados: Obj[] = [];
    const fallos: string[] = [];
    for (const [i, art] of lista.entries()) {
        const etiqueta = str(art.etiqueta, 120);
        const alimentoId = art.alimento_id === undefined || art.alimento_id === null ? undefined : entero(art.alimento_id);
        const donde = etiqueta !== undefined ? `«${etiqueta}»` : `artículo ${i + 1}`;
        if (art.alimento_id !== undefined && art.alimento_id !== null && alimentoId === undefined) {
            fallos.push(`${donde}: alimento_id no válido`);
            continue;
        }
        if (etiqueta === undefined && alimentoId === undefined) {
            fallos.push(`${donde}: pasa etiqueta o alimento_id`);
            continue;
        }
        if (art.unidad !== undefined && !(UNIDADES as readonly string[]).includes(String(art.unidad))) {
            fallos.push(`${donde}: unidad no válida`);
            continue;
        }
        if (art.cantidad !== undefined && !(typeof art.cantidad === "number" && Number.isFinite(art.cantidad) && art.cantidad >= 0)) {
            fallos.push(`${donde}: cantidad no válida`);
            continue;
        }
        const cuerpo: Obj = {
            ...(etiqueta !== undefined ? { label: etiqueta } : {}),
            ...(alimentoId !== undefined ? { food_id: alimentoId } : {}),
            ...(art.cantidad !== undefined ? { quantity: art.cantidad } : {}),
            ...(art.unidad !== undefined ? { unit: art.unidad } : {}),
        };
        cuerpo.client_request_id = await idCompra(ctx.uid, ctx.homeId, dia, {
            e: etiqueta === undefined ? null : norm(etiqueta), a: alimentoId ?? null, c: art.cantidad ?? null, u: art.unidad ?? null,
        });
        const r = await ctx.escribir("POST", "shopping/item/create", cuerpo);
        if (r.ok) {
            const d = obj(r.data);
            apuntados.push({ item_id: d.id ?? null, etiqueta: d.label ?? etiqueta ?? null });
        } else {
            fallos.push(`${donde}: ${texto(r)}`);
        }
    }
    const valor: Obj = { ok: fallos.length === 0, apuntados, ...(fallos.length > 0 ? { fallos } : {}) };
    // Si no se apuntó nada, es un error de herramienta.
    return apuntados.length === 0 ? { ...valor, error: fallos.join("; ") } : valor;
};

/** `marcar_comprado`: marca, desmarca (pending) o «ya lo tengo» (skipped). Idempotente por naturaleza. */
export const marcarComprado = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    const ids = arr(a.item_ids).map(entero);
    if (ids.length === 0) return { ok: false, error: "Pasa al menos un artículo (item_ids de ver_compra)." };
    if (ids.length > MAX_ITEMS) return { ok: false, error: `Como máximo ${MAX_ITEMS} artículos por llamada.` };
    if (ids.some((n) => n === undefined)) return { ok: false, error: "item_ids debe ser una lista de ids numéricos de ver_compra." };
    const estado = String(a.estado);
    if (!(ESTADOS as readonly string[]).includes(estado)) return { ok: false, error: "estado debe ser checked, pending o skipped." };
    const actualizados: number[] = [];
    const fallos: { item_id: number; error: string }[] = [];
    for (const id of [...new Set(ids as number[])]) {
        const r = await ctx.escribir("PATCH", "shopping/item/check", { id, state: estado });
        if (r.ok) actualizados.push(id);
        else fallos.push({ item_id: id, error: texto(r) });
    }
    const valor: Obj = { ok: fallos.length === 0, estado, actualizados, ...(fallos.length > 0 ? { fallos } : {}) };
    return actualizados.length === 0 ? { ...valor, error: fallos.map((f) => `${f.item_id}: ${f.error}`).join("; ") } : valor;
};

export const registrarCompraEscritura = (server: McpServer, env: Entorno): void => {
    server.registerTool("apuntar_compra", {
        title: "Apuntar en la compra",
        description:
            `Apunta artículos sueltos en la Compra del hogar (hasta ${MAX_ARTICULOS}). Úsala solo si la persona lo pide («apunta leche y huevos»): los ingredientes del menú entran solos al aceptarlo. Cada artículo lleva etiqueta o alimento_id. Reintentar es seguro dentro del mismo día: el mismo artículo apuntado dos veces el mismo día no se duplica. Si algunos fallan, devuelve los apuntados y los fallos. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            articulos: z.array(z.object({
                etiqueta: z.string().optional().describe("Nombre del artículo (obligatorio si no hay alimento_id)."),
                alimento_id: z.number().int().positive().optional().describe("Id de buscar_alimento."),
                cantidad: z.number().nonnegative().optional(),
                unidad: z.enum(UNIDADES).optional(),
            })).describe(`1 a ${MAX_ARTICULOS} artículos.`),
        }),
        annotations: ANOTACIONES_ESCRITURA,
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => apuntarCompra(ctx, resto)));

    server.registerTool("marcar_comprado", {
        title: "Marcar artículos de la compra",
        description:
            `Marca artículos de la Compra como comprados (checked), los desmarca (pending) o los da por tenidos (skipped, «ya lo tengo»). item_ids salen de ver_compra (hasta ${MAX_ITEMS}). Repetirlo es seguro. Si algunos fallan, devuelve los actualizados y los fallos. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            item_ids: z.array(z.number().int().positive()).describe(`Ids de artículos de ver_compra (1 a ${MAX_ITEMS}).`),
            estado: z.enum(ESTADOS).describe("checked = comprado; pending = desmarcar; skipped = ya lo tengo."),
        }),
        annotations: { ...ANOTACIONES_ESCRITURA, idempotentHint: true },
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => marcarComprado(ctx, resto)));
};
