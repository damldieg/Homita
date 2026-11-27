// guardar_receta y crear_alimento. Una receta del MCP lleva pasos e ingredientes enlazados al catálogo de alimentos
// (sin enlazar el servidor no puede comprobar alergias ni generar la Compra). Los alimentos que no existen se dan de
// alta ANTES con `crear_alimento`: aquí nunca se crean a escondidas.
import { McpServer, z } from "../../deps.ts";
import { alimentoPorNombre } from "../../../_shared/homita/alimentos.ts";
import { idReceta } from "../../../_shared/homita/idempotencia.ts";
import { arr, entero, FRANJAS, obj, str } from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import { ErrorEscritura } from "../../errores.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_ESCRITURA, AVISO_DATOS, campoHogar, campoZona, datosDe, escribirEnHogar } from "../comun.ts";
import type { EscrituraCtx } from "../comun.ts";

const MAX_PASOS = 50;
const MAX_PASO_CHARS = 500;
const MAX_INGREDIENTES = 60;
const UNIDADES = ["g", "kg", "ml", "l", "ud", "cda", "cdta", "pizca"] as const;
const MAX_ALERGENOS = 14;

const error = (texto: string, extra: Obj = {}): Obj => ({ ok: false, error: texto, ...extra });

/** `guardar_receta`: validación y mapeo (alimento_id -> food_id; texto -> alimento exacto del catálogo) y alta. */
export const guardarReceta = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    const nombre = str(a.nombre, 120);
    if (nombre === undefined) return error("La receta necesita un nombre.");
    const pasos = arr(a.pasos).map((p) => str(p, MAX_PASO_CHARS + 1));
    if (pasos.length === 0) return error("Una receta necesita pasos: añade al menos uno (un texto por paso).");
    if (pasos.length > MAX_PASOS || pasos.some((p) => p === undefined || p.length > MAX_PASO_CHARS)) {
        return error(`Los pasos deben ser textos de hasta ${MAX_PASO_CHARS} caracteres, como máximo ${MAX_PASOS}.`);
    }
    const crudos = arr(a.ingredientes).map(obj);
    if (crudos.length === 0) {
        return error("Una receta necesita ingredientes: sin ellos no se puede comprobar contra alergias ni generar la Compra. Pasa `ingredientes` con alimento_id (buscar_alimento) o texto.");
    }
    if (crudos.length > MAX_INGREDIENTES) return error(`Como máximo ${MAX_INGREDIENTES} ingredientes.`);

    const ingredientes: Obj[] = [];
    const faltan: string[] = [];
    for (const [i, c] of crudos.entries()) {
        const donde = `ingrediente ${i + 1}`;
        const texto = str(c.texto, 120);
        const alimentoId = c.alimento_id === undefined || c.alimento_id === null ? undefined : entero(c.alimento_id);
        if (c.alimento_id !== undefined && c.alimento_id !== null && alimentoId === undefined) return error(`${donde}: alimento_id no válido.`);
        if (alimentoId === undefined && texto === undefined) return error(`${donde}: pasa alimento_id (de buscar_alimento) o texto.`);
        if (c.unidad !== undefined && !(UNIDADES as readonly string[]).includes(String(c.unidad))) return error(`${donde}: unidad no válida.`);
        if (c.cantidad !== undefined && !(typeof c.cantidad === "number" && Number.isFinite(c.cantidad) && c.cantidad >= 0)) {
            return error(`${donde}: cantidad no válida.`);
        }
        let foodId = alimentoId;
        if (foodId === undefined) {
            const hit = await alimentoPorNombre(ctx.leer, texto as string);
            if (hit === null) {
                faltan.push(texto as string);
                continue;
            }
            foodId = hit.id as number;
        }
        ingredientes.push({
            food_id: foodId,
            ...(texto !== undefined ? { label: texto } : {}),
            ...(c.cantidad !== undefined ? { quantity: c.cantidad } : {}),
            ...(c.unidad !== undefined ? { unit: c.unidad } : {}),
            ...(c.opcional === true ? { optional: true } : {}),
        });
    }
    if (faltan.length > 0) {
        return error(
            `Estos ingredientes no están en el catálogo de alimentos: ${faltan.map((f) => `«${f}»`).join(", ")}. Créalos con crear_alimento (o usa un alimento_id de buscar_alimento) y vuelve a guardar la receta.`,
            { sin_alimento: faltan },
        );
    }
    const franjas = arr(a.franjas).filter((f): f is string => typeof f === "string" && (FRANJAS as readonly string[]).includes(f));
    const cuerpo: Obj = {
        name: nombre, servings: entero(a.raciones) ?? 4, steps: pasos, ingredients: ingredientes, origin: "kito",
        ...(entero(a.minutos) !== undefined ? { minutes: entero(a.minutos) } : {}),
        ...(franjas.length > 0 ? { slots: franjas } : {}),
    };
    cuerpo.client_request_id = await idReceta(ctx.uid, ctx.homeId, cuerpo);
    let receta: Obj;
    try {
        receta = obj(datosDe(await ctx.escribir("POST", "recipe/create", cuerpo)));
    } catch (e) {
        if (e instanceof ErrorEscritura && e.status === 400) {
            return error("No se ha podido guardar la receta: revisa que cada alimento_id sea del catálogo del hogar (buscar_alimento), y las cantidades y unidades.");
        }
        throw e;
    }
    return {
        ok: true,
        receta_id: receta.id ?? null,
        nombre: receta.name ?? nombre,
        ingredientes: arr(receta.ingredients).map(obj).map((i) => ({
            alimento_id: i.food_id ?? null, texto: i.label ?? null, cantidad: i.quantity ?? null, unidad: i.unit ?? null, opcional: i.optional === true,
        })),
        alergenos: arr(receta.allergens),
        nota: "Guardar la misma receta otra vez no la duplica.",
    };
};

/** `crear_alimento`: reutiliza el que ya existe con ese nombre; si no, lo crea. */
export const crearAlimento = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    const nombre = str(a.nombre, 120);
    if (nombre === undefined) return error("El alimento necesita un nombre.");
    const existente = await alimentoPorNombre(ctx.leer, nombre);
    if (existente !== null) return { ok: true, alimento_id: existente.id, nombre: existente.name, creado: false };
    if (a.unidad !== undefined && !(UNIDADES as readonly string[]).includes(String(a.unidad))) return error("Unidad no válida.");
    const alergenos = arr(a.alergenos).map((x) => str(x, 40));
    if (alergenos.length > MAX_ALERGENOS || alergenos.some((x) => x === undefined)) return error("Los alérgenos son textos cortos (como máximo 14).");
    const cuerpo: Obj = {
        name: nombre,
        ...(str(a.seccion, 40) !== undefined ? { section: str(a.seccion, 40) } : {}),
        ...(a.unidad !== undefined ? { default_unit: a.unidad } : {}),
        ...(alergenos.length > 0 ? { allergens: alergenos } : {}),
    };
    const r = await ctx.escribir("POST", "food/create", cuerpo);
    if (!r.ok) {
        // Carrera: otro lo creó entre la búsqueda y el alta (índice único por hogar y nombre) -> se reutiliza.
        if (r.status === 400) {
            const ya = await alimentoPorNombre(ctx.leer, nombre);
            if (ya !== null) return { ok: true, alimento_id: ya.id, nombre: ya.name, creado: false };
        }
        datosDe(r);
    }
    const creado = obj(r.data);
    return { ok: true, alimento_id: creado.id ?? null, nombre: creado.name ?? nombre, creado: true };
};

export const registrarReceta = (server: McpServer, env: Entorno): void => {
    server.registerTool("guardar_receta", {
        title: "Guardar una receta",
        description:
            `Guarda una receta nueva en el recetario del hogar. Obligatorios: nombre, pasos (al menos uno) e ingredientes (al menos uno). Cada ingrediente lleva alimento_id (de buscar_alimento) o texto: con texto solo se enlaza si coincide exactamente con un alimento del catálogo; si no existe, devuelve error y debes crearlo antes con crear_alimento. Úsala también para platos de fuera o inventados que quieras poner en el menú: guárdalos aquí ANTES de guardar_borrador, para que la Compra los incluya. Guardar dos veces la misma receta no la duplica. Devuelve receta_id para usarlo en guardar_borrador. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            nombre: z.string().describe("Nombre de la receta."),
            raciones: z.number().int().positive().optional().describe("Raciones (por defecto 4)."),
            minutos: z.number().int().positive().optional().describe("Tiempo total de preparación."),
            franjas: z.array(z.enum(FRANJAS)).optional().describe("Franjas en las que encaja."),
            pasos: z.array(z.string()).describe("Pasos de la receta, uno por elemento. Obligatorio, al menos uno."),
            ingredientes: z.array(z.object({
                alimento_id: z.number().int().positive().optional().describe("Id de buscar_alimento."),
                texto: z.string().optional().describe("Nombre del alimento; se enlaza solo si coincide exactamente con el catálogo."),
                cantidad: z.number().nonnegative().optional(),
                unidad: z.enum(UNIDADES).optional(),
                opcional: z.boolean().optional(),
            })).describe("Ingredientes. Obligatorio, al menos uno."),
        }),
        annotations: ANOTACIONES_ESCRITURA,
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => guardarReceta(ctx, resto)));

    server.registerTool("crear_alimento", {
        title: "Crear un alimento",
        description:
            `Da de alta un alimento en el catálogo del hogar (para usarlo como ingrediente o en la Compra). Si ya existe uno con ese nombre lo reutiliza (creado: false) y no duplica. Devuelve alimento_id. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            nombre: z.string().describe("Nombre del alimento."),
            seccion: z.string().optional().describe("Sección de la compra (por defecto «otros»)."),
            unidad: z.enum(UNIDADES).optional().describe("Unidad por defecto (g si se omite)."),
            alergenos: z.array(z.string()).optional().describe("Alérgenos que contiene (textos cortos, como los de buscar_alimento)."),
        }),
        annotations: ANOTACIONES_ESCRITURA,
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => crearAlimento(ctx, resto)));
};
