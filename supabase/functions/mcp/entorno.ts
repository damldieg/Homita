// Lo que el MCP necesita del exterior para una petición ya autenticada. Se inyecta (los tests, falsos): el cableado
// real está en index.ts y solo usa `api/usecases/*` (vía `leerRuta` y `crearEscritor`) y los helpers de hogar de `api/_shared`.
import type { EscribirFn } from "../_shared/homita/escritor.ts";
import type { LecturaRuta } from "../_shared/homita/lector.ts";

export type LeerRuta = (
    ruta: string, params: Record<string, string | undefined>, token: string, uid: string, tz: string,
) => Promise<LecturaRuta>;

export interface Entorno {
    /** JWT OAuth del usuario: se reenvía tal cual a los casos de uso. */
    token: string;
    uid: string;
    leerRuta: LeerRuta;
    /** ¿Es el usuario miembro de ese hogar? (`checkHomeMember` de `api`). */
    checkHomeMember: (homeId: string, token: string) => Promise<boolean>;
    /** Escritor del api con el JWT y la zona del usuario sobre la lista blanca del MCP (`escritor.ts`). */
    crearEscritor: (token: string, uid: string, tz: string) => EscribirFn;
    /** Ejecuta `fn` con el hogar activo (`runWithHome` de `api`). */
    runInHome: <T>(homeId: string | null, fn: () => T) => T;
    /** app_user.id numérico del usuario; solo se pide con `solo_mias`. */
    appUserId: (uid: string, token: string) => Promise<string | null>;
    now: () => Date;
}

export const ZONA_POR_DEFECTO = "Europe/Madrid";
