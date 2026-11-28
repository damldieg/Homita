// Escritor del `api` en proceso: llama a los casos de uso con el JWT del usuario, así que heredan RLS, ACL y el hogar
// activo sin duplicar lógica. Cada consumidor compone SU lista blanca de rutas con `crearEscritorCon`: Kito
// (`asistente/skills/organizar/api.ts`) y el MCP (`mcp/escritor.ts`). `POST meal/plan/accept` NO está en las rutas
// comunes: solo la añade el MCP, a propósito (Kito nunca acepta el menú).
import {
    handleCalendarCreate, handleCalendarDelete, handleCalendarUpdate, handleCalendarUserAccess,
} from "../../api/usecases/calendars.ts";
import {
    handleEventCreate, handleEventDelete, handleEventDetail, handleEventUpdate,
} from "../../api/usecases/events.ts";
import { handleRoutineCreate, handleRoutineDelete, handleRoutineDetail, handleRoutineUpdate } from "../../api/usecases/routines.ts";
import {
    handleTaskListCreate, handleTaskListDelete, handleTaskListUpdate,
} from "../../api/usecases/task-lists.ts";
import {
    handleTaskComplete, handleTaskCreate, handleTaskDelete, handleTaskDetail, handleTaskUpdate,
} from "../../api/usecases/tasks.ts";
import { handleMealPlanItems, handleMealProfileMemberUpdate } from "../../api/usecases/meals.ts";
import { handleRecipeCreate } from "../../api/usecases/recipes.ts";
import { handleShoppingItemCreate } from "../../api/usecases/shopping.ts";
import type { RespuestaEscritura } from "./util-escritura.ts";

export type Manejador = (req: Request, token: string, uid: string) => Promise<Response>;
export type RutasEscritura = Record<string, Manejador>;

/** Escritura (o lectura de detalle) del `api` con el JWT del usuario. */
export type EscribirFn = (
    metodo: "GET" | "POST" | "PATCH" | "DELETE",
    ruta: string,
    cuerpo?: Record<string, unknown>,
) => Promise<RespuestaEscritura>;

/**
 * Rutas de menús que escriben tanto Kito como el MCP: borrador del menú (`origin` kito; la RPC no toca un plan
 * aceptado ni casillas locked), recetas con pasos, artículos de compra y preferencias de una persona. NO incluye
 * `POST meal/plan/accept`, `POST food/create` ni `PATCH shopping/item/check`.
 */
export const RUTAS_MENUS_COMUNES: RutasEscritura = {
    "PATCH meal/plan/items": (r, t) => handleMealPlanItems(r, t),
    "POST recipe/create": (r, t) => handleRecipeCreate(r, t),
    "POST shopping/item/create": (r, t) => handleShoppingItemCreate(r, t),
    "PATCH meal/profile/member": (r, t) => handleMealProfileMemberUpdate(r, t),
};

/**
 * Rutas de «organizar» (listas, tareas, eventos, rutinas, calendarios) que usan Kito y el MCP: las 16 operaciones de
 * `OPS`, `PATCH calendar/user` (compartir un calendario) y los 3 GET de detalle (lectura, para rellenar ediciones).
 * No hay alarmas (`/event/alarm`, `/routine/alarm`), administración del hogar, invitaciones ni `meal/plan/accept`.
 */
export const RUTAS_ORGANIZAR: RutasEscritura = {
    "POST task-list/create": (r, t) => handleTaskListCreate(r, t),
    "PATCH task-list/update": (r, t) => handleTaskListUpdate(r, t),
    "DELETE task-list/delete": (r, t) => handleTaskListDelete(r, t),
    "POST task/create": (r, t) => handleTaskCreate(r, t),
    "PATCH task/update": (r, t) => handleTaskUpdate(r, t),
    "PATCH task/complete": (r, t) => handleTaskComplete(r, t),
    "DELETE task/delete": (r, t) => handleTaskDelete(r, t),
    "GET task/detail": (r, t) => handleTaskDetail(r, t),
    "POST event/create": (r, t) => handleEventCreate(r, t),
    "PATCH event/update": (r, t) => handleEventUpdate(r, t),
    "DELETE event/delete": (r, t) => handleEventDelete(r, t),
    "GET event/detail": (r, t, u) => handleEventDetail(r, t, u),
    "POST routine/create": (r, t) => handleRoutineCreate(r, t),
    "PATCH routine/update": (r, t) => handleRoutineUpdate(r, t),
    "DELETE routine/delete": (r, t) => handleRoutineDelete(r, t),
    "GET routine/detail": (r, t, u) => handleRoutineDetail(r, t, u),
    "POST calendar/create": (r, t) => handleCalendarCreate(r, t),
    "PATCH calendar/update": (r, t) => handleCalendarUpdate(r, t),
    "DELETE calendar/delete": (r, t) => handleCalendarDelete(r, t),
    "PATCH calendar/user": (r, t) => handleCalendarUserAccess(r, t),
};

const respuesta = async (res: Response): Promise<RespuestaEscritura> => {
    const texto = await res.text();
    let data: unknown = texto;
    try {
        data = texto === "" ? null : JSON.parse(texto);
    } catch { /* se queda el texto */ }
    const error = data !== null && typeof data === "object" && typeof (data as { error?: unknown }).error === "string"
        ? (data as { error: string }).error
        : undefined;
    return { ok: res.ok, status: res.status, data, ...(error !== undefined ? { error } : {}) };
};

/** Escritor con el JWT, el uid y la zona del usuario sobre una lista blanca. Lo que no esté en `rutas` no se llama. */
export const crearEscritorCon = (rutas: RutasEscritura, token: string, uid: string, tz: string): EscribirFn =>
async (metodo, ruta, cuerpo = {}) => {
    const manejador = rutas[`${metodo} ${ruta}`];
    if (!manejador) return { ok: false, status: 400, data: null, error: "ruta no permitida" };
    const url = new URL(`https://homita.local/api/${ruta}`);
    url.searchParams.set("timezone", tz);
    let req: Request;
    if (metodo === "GET") {
        for (const [k, v] of Object.entries(cuerpo)) if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
        req = new Request(url.toString(), { method: "GET" });
    } else {
        req = new Request(url.toString(), {
            method: metodo,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ timezone: tz, ...cuerpo }),
        });
    }
    try {
        return await respuesta(await manejador(req, token, uid));
    } catch {
        // En proceso no hay capa superior que convierta la excepción en 500: se devuelve como fallo del api.
        return { ok: false, status: 500, data: null };
    }
};
