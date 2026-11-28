// crear_calendario, editar_calendario, compartir_calendario, borrar_calendario. La lógica es la de Kito
// (`_shared/homita/organizar/calendarios.ts`); compartir un calendario existente es solo del MCP (en Kito solo se
// comparte al crear), sobre la misma función `compartirCalendario`.
import { McpServer, z } from "../../../deps.ts";
import { compartirCalendario } from "../../../../_shared/homita/organizar/acciones.ts";
import { ErrorLectura } from "../../../../_shared/homita/organizar/errores.ts";
import { filaPorId, filas, YA_NO_EXISTE } from "../../../../_shared/homita/organizar/argumentos.ts";
import {
    personaConCuenta, prepararBorrarCalendario, prepararCrearCalendario, prepararEditarCalendario,
} from "../../../../_shared/homita/organizar/calendarios.ts";
import type { Obj } from "../../../../_shared/homita/organizar/tipos.ts";
import type { Entorno } from "../../../entorno.ts";
import type { EscrituraCtx } from "../../comun.ts";
import {
    ANOTACIONES_BORRADO, ANOTACIONES_ORGANIZAR, AVISO_ESCRITURA, borrar, campoConfirmado, campoHogar, campoZona, conHogar, ejecutar,
    orgCtx, preparar,
} from "../comun.ts";

/** Comparte un calendario con una persona del hogar que tenga cuenta (upsert: si ya tenía acceso, cambia su permiso). */
export const compartir = async (ctx: EscrituraCtx, a: { calendario_id: number; persona_id: number; puede_editar?: boolean }): Promise<Obj> => {
    const c = orgCtx(ctx);
    const personas = await filas(c.leer, "person");
    if (personas === null) return { ok: false, error: "No he podido leer las personas del hogar ahora mismo." };
    const persona = personaConCuenta(personas, c.homeId, a.persona_id, c.appUserId);
    if ("error" in persona) return { ok: false, error: persona.error };
    if ("sinCuenta" in persona) {
        return {
            ok: false,
            sin_cuenta: [persona.sinCuenta],
            error: `${persona.sinCuenta} no tiene cuenta en Homita, así que no puedo compartir el calendario con esa persona.`,
        };
    }
    if ("propia" in persona) return { ok: false, error: "Esa persona eres tú: el calendario ya es tuyo, no hace falta compartirlo contigo." };
    const cal = await filaPorId(c, "calendar", a.calendario_id);
    if (cal === null) return YA_NO_EXISTE;
    const puedeEditar = a.puede_editar === true;
    const r = await compartirCalendario(ctx.escribir, a.calendario_id, persona.userId, puedeEditar, persona.nombre, String(cal.name));
    if (!r.ok) return { ok: false, error: r.texto };
    return {
        ok: true,
        hecho: `Compartido el calendario «${cal.name}» con ${persona.nombre} (${puedeEditar ? "puede editar" : "solo lectura"})`,
        id: a.calendario_id,
    };
};

export const registrarCalendarios = (server: McpServer, env: Entorno): void => {
    server.registerTool("crear_calendario", {
        title: "Crear un calendario",
        description:
            `Crea un calendario. Indispensables: nombre y con quién se comparte: compartir_con (personas del hogar con cuenta; por defecto en solo lectura, puede_editar da permiso de edición) o solo_yo true. Si falta, devuelve {falta} y debes preguntarlo. Si alguna persona no tiene cuenta no se crea nada (sin_cuenta). Crea el calendario y después comparte con cada persona: si compartir falla, el calendario queda creado y sale un aviso (no es atómico; reintenta con compartir_calendario). NO es idempotente: si no sabes si se creó, compruébalo con ver_calendarios antes de reintentar. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            nombre: z.string().describe("Nombre del calendario."),
            solo_yo: z.boolean().optional().describe("true si el calendario es solo para la persona que lo pide."),
            compartir_con: z.array(z.object({
                persona_id: z.number().int().positive().describe("Id de la persona (ver_personas; debe tener cuenta)."),
                puede_editar: z.boolean().optional().describe("true para permiso de edición; por defecto solo lectura."),
            })).optional().describe("Personas con las que se comparte."),
            color: z.string().optional().describe("Color #RRGGBB, solo si lo piden."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararCrearCalendario(a, orgCtx(ctx)))), { appUser: true }));

    server.registerTool("editar_calendario", {
        title: "Editar un calendario",
        description:
            `Cambia el nombre o el color de un calendario. Indispensables: id (ver_calendarios) y al menos un cambio. Solo manda lo que cambia: el resto se conserva. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id del calendario (ver_calendarios)."),
            nombre: z.string().optional().describe("Nuevo nombre."),
            color: z.string().optional().describe("Nuevo color #RRGGBB."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => ejecutar(ctx, await preparar(() => prepararEditarCalendario(a, orgCtx(ctx))))));

    server.registerTool("compartir_calendario", {
        title: "Compartir un calendario con una persona",
        description:
            `Da acceso a un calendario a una persona del hogar. Solo con personas que tienen cuenta en Homita (ver_personas lo indica) y solo si el usuario es el propietario del calendario; no se comparte con uno mismo. Por defecto solo lectura; puede_editar true da permiso de edición. Si la persona ya tenía acceso, cambia su permiso. No quita acceso a nadie. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            calendario_id: z.number().int().positive().describe("Id del calendario (ver_calendarios)."),
            persona_id: z.number().int().positive().describe("Id de la persona (ver_personas; debe tener cuenta)."),
            puede_editar: z.boolean().optional().describe("true para permiso de edición; por defecto solo lectura."),
        }),
        annotations: ANOTACIONES_ORGANIZAR,
    }, conHogar(env, async (ctx, a) => {
        try {
            return await compartir(ctx, a);
        } catch (e) {
            if (e instanceof ErrorLectura) return { ok: false, error: e.message };
            throw e;
        }
    }, { appUser: true }));

    server.registerTool("borrar_calendario", {
        title: "Borrar un calendario",
        description:
            `BORRA un calendario con TODOS sus eventos y rutinas. Es irreversible. Primera llamada SIN confirmado: no borra y te dice qué se borraría; cuéntaselo a la persona, espera un sí explícito y solo entonces repite con confirmado: true. ${AVISO_ESCRITURA}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            id: z.number().int().positive().describe("Id del calendario (ver_calendarios)."),
            confirmado: campoConfirmado,
        }),
        annotations: ANOTACIONES_BORRADO,
    }, conHogar(env, async (ctx, a) => {
        const p = await preparar(() => prepararBorrarCalendario(a, orgCtx(ctx)));
        return borrar(ctx, p, a.confirmado, (_extra, nombre) => `el calendario «${nombre}» con todos sus eventos y rutinas`);
    }));
};
