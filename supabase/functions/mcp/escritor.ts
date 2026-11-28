// Escritor del MCP: la lista blanca PROPIA de rutas de escritura. Son las comunes de menús y las de organizar (las mismas
// que usa Kito, incluido compartir un calendario y los 3 GET de detalle) más las tres que solo tiene el MCP: aceptar el
// menú, crear un alimento y marcar un artículo de la compra. Nada más: archivar, copiar, el horario, el perfil del hogar,
// las alarmas, la administración del hogar ni las invitaciones no se pueden llamar desde aquí.
import { handleFoodCreate } from "../api/usecases/recipes.ts";
import { handleMealPlanAccept } from "../api/usecases/meals.ts";
import { handleShoppingItemCheck } from "../api/usecases/shopping.ts";
import { crearEscritorCon, RUTAS_MENUS_COMUNES, RUTAS_ORGANIZAR } from "../_shared/homita/escritor.ts";
import type { EscribirFn, RutasEscritura } from "../_shared/homita/escritor.ts";

export const RUTAS_MCP: RutasEscritura = {
    ...RUTAS_MENUS_COMUNES,
    ...RUTAS_ORGANIZAR,
    "POST meal/plan/accept": (r, t) => handleMealPlanAccept(r, t),
    "POST food/create": (r, t) => handleFoodCreate(r, t),
    "PATCH shopping/item/check": (r, t) => handleShoppingItemCheck(r, t),
};

/** Escritor con el JWT del usuario y su zona sobre `RUTAS_MCP`. Lo ejecuta quien llama dentro de `runInHome`. */
export const crearEscritorMcp = (token: string, uid: string, tz: string): EscribirFn =>
    crearEscritorCon(RUTAS_MCP, token, uid, tz);
