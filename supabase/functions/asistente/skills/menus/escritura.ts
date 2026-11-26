// guardar_receta, apuntar_compra y apuntar_preferencia: escrituras pequeñas de la skill `menus`. Todas con el
// JWT de la persona (ACL y permisos los pone el api). La preferencia solo se apunta tras preguntar.
import { conEfectos } from "../../core.ts";
import type { Tool } from "../../core.ts";
import { clientRequestId, uuidDe } from "../organizar/uuid.ts";
import {
    arr, entero, errorEscritura, escribirDe, esquema, FRANJAS, leerDe, leerPerfil, norm, obj, str,
} from "./util.ts";
import type { Obj } from "./util.ts";

const MAX_PASOS = 50;
const MAX_PASO_CHARS = 500;
const MAX_INGREDIENTES = 60;
const MAX_ARTICULOS = 20;
const MAX_PREFERENCIAS = 50;
const MAX_PREFERENCIA_CHARS = 200;
const UNIDADES = ["g", "kg", "ml", "l", "ud", "cda", "cdta", "pizca"];

/** Alimento del catálogo con ese nombre exacto (sin acentos ni mayúsculas); sin coincidencia exacta no se adivina. */
const alimentoExacto = async (leer: ReturnType<typeof leerDe>, nombre: string): Promise<number | null> => {
    const r = await leer("food", { q: nombre, limit: "10" }).catch(() => null);
    if (!Array.isArray(r)) return null;
    const n = norm(nombre);
    const hit = r.map(obj).find((f) => typeof f.name === "string" && norm(f.name) === n);
    return typeof hit?.id === "number" ? hit.id : null;
};

export const guardarRecetaTool: Tool = {
    name: "guardar_receta",
    description:
        "Guarda una receta en el recetario del hogar (origen Kito). Obligatorios: nombre y pasos (al menos uno). Los ingredientes se enlazan con el catálogo de alimentos por nombre exacto: los que no están en el catálogo quedan sin enlazar y el menú no puede comprobarlos contra alergias, así que prefiere nombres comunes («leche», «huevo», «harina de trigo»). Devuelve receta_id para usarlo en proponer_menu. Es idempotente: guardar dos veces la misma receta no la duplica.",
    input_schema: esquema({
        nombre: { type: "string" },
        raciones: { type: "integer", description: "Por defecto 4." },
        minutos: { type: "integer", description: "Tiempo total de preparación." },
        franjas: { type: "array", items: { type: "string", enum: [...FRANJAS] }, description: "Franjas en las que encaja." },
        pasos: { type: "array", items: { type: "string" }, description: "Pasos de la receta, uno por elemento." },
        ingredientes: {
            type: "array",
            items: {
                type: "object",
                properties: {
                    nombre: { type: "string" },
                    cantidad: { type: "number" },
                    unidad: { type: "string", enum: UNIDADES },
                    opcional: { type: "boolean" },
                },
                required: ["nombre"],
                additionalProperties: false,
            },
        },
    }, ["nombre", "pasos"]),
    escritura: true,
    strict: false,
    run: async (input, ctx) => {
        const nombre = str(input.nombre, 120);
        const pasos = arr(input.pasos).map((p) => str(p, MAX_PASO_CHARS + 1));
        const faltan = [nombre === undefined ? "nombre" : "", pasos.length === 0 ? "pasos" : ""].filter((x) => x);
        if (faltan.length > 0) return { falta: faltan, error: "Una receta necesita nombre y pasos." };
        if (pasos.some((p) => p === undefined || p.length > MAX_PASO_CHARS) || pasos.length > MAX_PASOS) {
            return { ok: false, error: `Los pasos deben ser textos de hasta ${MAX_PASO_CHARS} caracteres, como máximo ${MAX_PASOS}.` };
        }
        const crudos = arr(input.ingredientes).map(obj);
        if (crudos.length > MAX_INGREDIENTES) return { ok: false, error: `Como máximo ${MAX_INGREDIENTES} ingredientes.` };
        const leer = leerDe(ctx);
        const sinEnlazar: string[] = [];
        const ingredientes: Obj[] = [];
        for (const c of crudos) {
            const n = str(c.nombre, 120);
            if (n === undefined) return { ok: false, error: "Cada ingrediente necesita nombre." };
            if (c.unidad !== undefined && !UNIDADES.includes(String(c.unidad))) return { ok: false, error: `Unidad no válida en «${n}».` };
            if (c.cantidad !== undefined && !(typeof c.cantidad === "number" && Number.isFinite(c.cantidad) && c.cantidad >= 0)) {
                return { ok: false, error: `Cantidad no válida en «${n}».` };
            }
            const foodId = await alimentoExacto(leer, n);
            if (foodId === null) sinEnlazar.push(n);
            ingredientes.push({
                ...(foodId !== null ? { food_id: foodId } : {}), label: n,
                ...(c.cantidad !== undefined ? { quantity: c.cantidad } : {}),
                ...(c.unidad !== undefined ? { unit: c.unidad } : {}),
                ...(c.opcional === true ? { optional: true } : {}),
            });
        }
        const franjas = arr(input.franjas).filter((f): f is string => typeof f === "string" && (FRANJAS as readonly string[]).includes(f));
        const cuerpo: Obj = {
            name: nombre, servings: entero(input.raciones) ?? 4, steps: pasos, ingredients: ingredientes, origin: "kito",
            ...(entero(input.minutos) !== undefined ? { minutes: entero(input.minutos) } : {}),
            ...(franjas.length > 0 ? { slots: franjas } : {}),
        };
        cuerpo.client_request_id = await uuidDe(`receta|${ctx.appUserId ?? ctx.uid}|${ctx.homeId ?? ""}|${JSON.stringify(cuerpo)}`);
        const r = await escribirDe(ctx)("POST", "recipe/create", cuerpo);
        if (!r.ok) return errorEscritura(r);
        const id = entero(obj(r.data).id) ?? null;
        return conEfectos(
            {
                ok: true, receta_id: id, hecho: `Receta «${nombre}» guardada.`,
                ...(sinEnlazar.length > 0 ? { ingredientes_sin_enlazar: sinEnlazar, aviso: "Esos ingredientes no están en el catálogo: el menú no los comprueba contra alergias." } : {}),
            },
            { cambios: [{ tipo: "receta", id, op: "crear" }] },
        );
    },
};

export const apuntarCompraTool: Tool = {
    name: "apuntar_compra",
    description:
        "Apunta artículos en la Compra del hogar. Úsala solo si la persona lo pide (por ejemplo «apunta leche y huevos»); no apuntes por tu cuenta los ingredientes del menú: eso lo hace la app al aceptar el menú. Hasta 20 artículos por llamada.",
    input_schema: esquema({
        articulos: {
            type: "array",
            items: {
                type: "object",
                properties: {
                    nombre: { type: "string" },
                    cantidad: { type: "number" },
                    unidad: { type: "string", enum: UNIDADES },
                },
                required: ["nombre"],
                additionalProperties: false,
            },
        },
    }, ["articulos"]),
    escritura: true,
    strict: false,
    run: async (input, ctx, extra) => {
        const lista = arr(input.articulos).map(obj);
        if (lista.length === 0) return { falta: ["articulos"] };
        if (lista.length > MAX_ARTICULOS) return { ok: false, error: `Como máximo ${MAX_ARTICULOS} artículos por llamada.` };
        const escribir = escribirDe(ctx);
        const hechos: string[] = [];
        const fallos: string[] = [];
        for (const [i, a] of lista.entries()) {
            const nombre = str(a.nombre, 120);
            if (nombre === undefined) {
                fallos.push(`artículo ${i + 1}: falta el nombre`);
                continue;
            }
            if (a.unidad !== undefined && !UNIDADES.includes(String(a.unidad))) {
                fallos.push(`«${nombre}»: unidad no válida`);
                continue;
            }
            const cuerpo: Obj = {
                label: nombre,
                ...(typeof a.cantidad === "number" && Number.isFinite(a.cantidad) && a.cantidad >= 0 ? { quantity: a.cantidad } : {}),
                ...(a.unidad !== undefined ? { unit: a.unidad } : {}),
            };
            // La clave sale del tool_use: reintentar la misma llamada no duplica; otra petición sí puede apuntar de nuevo.
            if (extra?.toolUseId) cuerpo.client_request_id = await clientRequestId(ctx.appUserId ?? ctx.uid, ctx.homeId, extra.toolUseId, i);
            const r = await escribir("POST", "shopping/item/create", cuerpo);
            if (r.ok) hechos.push(nombre);
            else fallos.push(`«${nombre}»: ${String(errorEscritura(r).error)}`);
        }
        const valor = { ok: fallos.length === 0, apuntados: hechos, ...(fallos.length > 0 ? { fallos } : {}) };
        return hechos.length > 0 ? conEfectos(valor, { cambios: [{ tipo: "compra", id: null, op: "crear" }] }) : valor;
    },
};

const TIPOS_PREFERENCIA = ["no_le_gusta", "le_encanta", "picante"] as const;

export const apuntarPreferenciaTool: Tool = {
    name: "apuntar_preferencia",
    description:
        "Apunta una preferencia de una persona del hogar: lo que no le gusta (C1), lo que le encanta (C2) o cuánto picante tolera (C4, 0 a 3). SOLO después de preguntarle a la persona («¿lo apunto como algo que no os gusta?») y con su sí: pasa confirmado_por_usuario=true. Sin confirmación no hace nada. `persona_id` es el id de leer_perfil.",
    input_schema: esquema({
        persona_id: { type: "integer", description: "Id de la persona (leer_perfil)." },
        tipo: { type: "string", enum: [...TIPOS_PREFERENCIA] },
        valor: { type: "string", description: "El ingrediente o plato; para picante, un número de 0 (nada) a 3 (mucho)." },
        confirmado_por_usuario: { type: "boolean", description: "true solo si la persona ha dicho que sí a apuntarlo." },
    }, ["persona_id", "tipo", "valor", "confirmado_por_usuario"]),
    escritura: true,
    strict: false,
    run: async (input, ctx) => {
        if (input.confirmado_por_usuario !== true) {
            return { ok: false, error: "No lo apunto sin preguntar: pregunta a la persona si quiere que lo apuntes y, si dice que sí, vuelve a llamar con confirmado_por_usuario=true." };
        }
        const personaId = entero(input.persona_id);
        const tipo = String(input.tipo);
        const valor = str(input.valor, MAX_PREFERENCIA_CHARS);
        if (personaId === undefined || !(TIPOS_PREFERENCIA as readonly string[]).includes(tipo) || valor === undefined) {
            return { falta: ["persona_id", "tipo", "valor"].filter((k) => input[k] === undefined || input[k] === ""), error: "Faltan datos de la preferencia." };
        }
        const perfil = await leerPerfil(ctx);
        const persona = arr(perfil.members).map(obj).find((m) => m.home_member_id === personaId);
        if (persona === undefined) return { ok: false, error: "Esa persona no tiene ficha de comidas en el hogar." };
        let cuerpo: Obj;
        if (tipo === "picante") {
            if (!/^[0-3]$/.test(valor)) return { ok: false, error: "El picante es un número de 0 a 3." };
            cuerpo = { home_member_id: personaId, spice: Number(valor) };
        } else {
            const campo = tipo === "no_le_gusta" ? "dislikes" : "favorites";
            const actuales = arr(persona[campo]).filter((x): x is string => typeof x === "string");
            if (actuales.some((x) => norm(x) === norm(valor))) return { ok: true, hecho: "Ya estaba apuntado." };
            if (actuales.length >= MAX_PREFERENCIAS) return { ok: false, error: `Ya hay ${MAX_PREFERENCIAS} apuntados; no caben más.` };
            cuerpo = { home_member_id: personaId, [campo]: [...actuales, valor] };
        }
        const r = await escribirDe(ctx)("PATCH", "meal/profile/member", cuerpo);
        if (!r.ok) return errorEscritura(r);
        return { ok: true, hecho: `Apuntado para ${String(persona.name ?? "esa persona")}.` };
    },
};
