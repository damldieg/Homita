// Escritor del `api` para Kito: llama en proceso a los casos de uso de escritura con el JWT del usuario, así
// que heredan RLS, ACL (can_edit) y el hogar activo sin duplicar lógica. Es lo único de la skill `organizar`
// que importa `api`; las herramientas reciben el escritor por `ctx.escribir` y los tests inyectan uno falso.
import { crearEscritorCon, RUTAS_MENUS_COMUNES, RUTAS_ORGANIZAR } from "../../../_shared/homita/escritor.ts";
import type { RutasEscritura } from "../../../_shared/homita/escritor.ts";
import type { Escribir } from "../../core.ts";

/**
 * Rutas permitidas: las de organizar (compartidas con el MCP) y las comunes de menús (borrador, recetas, compra,
 * preferencias). `POST meal/plan/accept` NO está y no debe estar nunca: Kito no acepta el menú, lo acepta la persona
 * en la app. Tampoco archive, copy, schedule ni el perfil del hogar. Lo que no esté aquí no se puede llamar desde Kito.
 */
export const RUTAS: RutasEscritura = { ...RUTAS_ORGANIZAR, ...RUTAS_MENUS_COMUNES };

/** Escritor con el JWT, el uid y la zona del usuario. `homeId` lo aporta `runInHome` (contexto del hogar). */
export const crearEscritor = (token: string, uid: string, tz: string, _homeId?: string | null): Escribir =>
    crearEscritorCon(RUTAS, token, uid, tz);
