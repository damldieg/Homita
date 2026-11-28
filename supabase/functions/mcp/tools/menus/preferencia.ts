// apuntar_preferencia: lo que no le gusta a una persona (C1, `dislikes`), lo que le encanta (C2, `favorites`) o cuánto
// picante tolera (C4, `spice`, 0-3). No toca las manías y texturas (C3, `quirks`). Solo con el sí de la persona
// (`confirmado_por_usuario`). Los permisos los decide el servidor (`menu.profile.edit` o persona vinculada).
import { McpServer, z } from "../../deps.ts";
import { arr, entero, leerPerfil, norm, obj, str } from "../../../_shared/homita/menus.ts";
import type { Obj } from "../../../_shared/homita/menus.ts";
import type { Entorno } from "../../entorno.ts";
import { ANOTACIONES_ESCRITURA, AVISO_DATOS, campoHogar, campoZona, datosDe, escribirEnHogar } from "../comun.ts";
import type { EscrituraCtx } from "../comun.ts";

const MAX_PREFERENCIAS = 50;
const MAX_PREFERENCIA_CHARS = 200;
const CAMPOS = ["no_le_gusta", "le_encanta", "picante"] as const;

export const apuntarPreferencia = async (ctx: EscrituraCtx, a: Obj): Promise<Obj> => {
    if (a.confirmado_por_usuario !== true) {
        return { ok: false, error: "No lo apunto sin preguntar: pregunta a la persona si quiere que lo apuntes y, si dice que sí, vuelve a llamar con confirmado_por_usuario=true." };
    }
    const personaId = entero(a.persona_id);
    const campo = String(a.campo);
    const valor = str(typeof a.valor === "number" ? String(a.valor) : a.valor, MAX_PREFERENCIA_CHARS);
    if (personaId === undefined || !(CAMPOS as readonly string[]).includes(campo) || valor === undefined) {
        return { ok: false, error: "Faltan datos: persona_id, campo (no_le_gusta, le_encanta o picante) y valor." };
    }
    const perfil = await leerPerfil(ctx.leer);
    const persona = arr(perfil.members).map(obj).find((m) => m.home_member_id === personaId);
    if (persona === undefined) return { ok: false, error: "Esa persona no tiene ficha de comidas en el hogar (persona_id de leer_perfil)." };
    let cuerpo: Obj;
    if (campo === "picante") {
        if (!/^[0-3]$/.test(valor)) return { ok: false, error: "El picante es un número de 0 (nada) a 3 (mucho)." };
        cuerpo = { home_member_id: personaId, spice: Number(valor) };
    } else {
        const clave = campo === "no_le_gusta" ? "dislikes" : "favorites";
        const actuales = arr(persona[clave]).filter((x): x is string => typeof x === "string");
        if (actuales.some((x) => norm(x) === norm(valor))) return { ok: true, hecho: "Ya estaba apuntado." };
        if (actuales.length >= MAX_PREFERENCIAS) return { ok: false, error: `Ya hay ${MAX_PREFERENCIAS} apuntados; no caben más.` };
        cuerpo = { home_member_id: personaId, [clave]: [...actuales, valor] };
    }
    datosDe(await ctx.escribir("PATCH", "meal/profile/member", cuerpo));
    return { ok: true, hecho: `Apuntado para ${str(persona.name, 80) ?? "esa persona"}.` };
};

export const registrarPreferencia = (server: McpServer, env: Entorno): void => {
    server.registerTool("apuntar_preferencia", {
        title: "Apuntar una preferencia",
        description:
            `Apunta una preferencia de una persona del hogar: lo que no le gusta (campo no_le_gusta), lo que le encanta (le_encanta) o cuánto picante tolera (picante, de 0 a 3). SOLO después de preguntarle a la persona («¿lo apunto como algo que no os gusta?») y con su sí: pasa confirmado_por_usuario=true; sin confirmación no hace nada. persona_id es el id de leer_perfil. No guarda manías ni texturas. ${AVISO_DATOS}`,
        inputSchema: z.object({
            hogar: campoHogar,
            timezone: campoZona,
            persona_id: z.number().int().positive().describe("Id de la persona (leer_perfil)."),
            campo: z.enum(CAMPOS),
            valor: z.string().describe("El ingrediente o plato; para picante, un número de 0 a 3."),
            confirmado_por_usuario: z.boolean().describe("true solo si la persona ha dicho que sí a apuntarlo."),
        }),
        annotations: ANOTACIONES_ESCRITURA,
    }, ({ hogar, timezone, ...resto }) => escribirEnHogar(env, { hogar, timezone }, (ctx) => apuntarPreferencia(ctx, resto)));
};
