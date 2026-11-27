// Lector del `api` para Kito y para el MCP: llama en proceso a los casos de uso GET con el JWT del usuario,
// así heredan RLS, ACL y el filtro del hogar activo (X-Home-Id, ver `runWithHome`) sin duplicar lógica.
// Es lo único de `_shared/homita` que importa `api/usecases`.
//
//  - `leerRuta` es el núcleo: devuelve `{ok, status, body}` sin envolver los errores, para que el MCP distinga
//    un 403/404 de un dato.
//  - `crearLector` es el lector de Kito: mismo contrato de siempre (`{error, detalle}` si el api falla,
//    `{error: "respuesta no válida"}` si no es JSON, `{error: "ruta no permitida"}` fuera de su lista).
import { handlePersonIndex } from "../../api/usecases/persons.ts";
import { handleTask } from "../../api/usecases/tasks.ts";
import { handleTaskListIndex } from "../../api/usecases/task-lists.ts";
import { handleEvent } from "../../api/usecases/events.ts";
import { handleRoutineIndex } from "../../api/usecases/routines.ts";
import { handleCalendarIndex, handleCalendarUserIndex } from "../../api/usecases/calendars.ts";
import { handleHomeIndex } from "../../api/usecases/homes.ts";
import { handleMealPlanCheck, handleMealPlanGet, handleMealProfileGet } from "../../api/usecases/meals.ts";
import { handleFoodSearch, handleRecipeDetail, handleRecipeIndex } from "../../api/usecases/recipes.ts";
import { handleShoppingList, handleShoppingPreview } from "../../api/usecases/shopping.ts";
import type { Leer } from "./tipos.ts";

/** Resultado crudo de una lectura: `body` es el JSON del api (o su texto si no era JSON válido: `json` false). */
export interface LecturaRuta {
    ok: boolean;
    status: number;
    body: unknown;
    /** Texto de la respuesta tal cual. */
    texto: string;
    /** `body` salió de parsear `texto` como JSON. */
    json: boolean;
}

type Params = Record<string, string | undefined>;
type Caso = (req: Request, token: string, uid: string) => Promise<Response>;

/** Rutas de lectura de Kito (no incluye la compra). */
export const RUTAS_KITO = [
    "event", "routine", "task", "task-list", "person", "calendar", "calendar/user", "home",
    "meal/profile", "meal/plan", "meal/plan/check", "recipe", "recipe/detail", "food",
] as const;

/** Rutas de lectura que añade el MCP. Ninguna herramienta de Kito las llama. */
export const RUTAS_COMPRA = ["shopping", "shopping/preview"] as const;

const CASOS: Record<string, Caso> = {
    "event": (req, token, uid) => handleEvent(req, token, uid),
    "routine": (req, token, uid) => handleRoutineIndex(req, token, uid),
    "task": (req, token) => handleTask(req, token),
    "task-list": (req, token) => handleTaskListIndex(req, token),
    "person": (req, token) => handlePersonIndex(req, token),
    "calendar": (req, token) => handleCalendarIndex(req, token),
    "calendar/user": (req, token) => handleCalendarUserIndex(req, token),
    "home": (req, token) => handleHomeIndex(req, token),
    // Menús (solo lectura): perfil de comidas, menú de una semana y su comprobación, recetas y alimentos.
    "meal/profile": (req, token) => handleMealProfileGet(req, token),
    "meal/plan": (req, token) => handleMealPlanGet(req, token),
    "meal/plan/check": (req, token) => handleMealPlanCheck(req, token),
    "recipe": (req, token) => handleRecipeIndex(req, token),
    "recipe/detail": (req, token) => handleRecipeDetail(req, token),
    "food": (req, token) => handleFoodSearch(req, token),
    // Compra (solo la usa el MCP).
    "shopping": (req, token) => handleShoppingList(req, token),
    "shopping/preview": (req, token) => handleShoppingPreview(req, token),
};

const peticion = (ruta: string, params: Params, tz: string): Request => {
    const url = new URL(`https://homita.local/api/${ruta}`);
    for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") url.searchParams.set(k, v);
    url.searchParams.set("timezone", tz);
    return new Request(url.toString(), { method: "GET" });
};

/** Ejecuta el caso de uso GET de `ruta` con el JWT del usuario. Una ruta desconocida da `{ok:false, status:400}`. */
export const leerRuta = async (
    ruta: string, params: Params, token: string, uid: string, tz: string,
): Promise<LecturaRuta> => {
    const caso = Object.hasOwn(CASOS, ruta) ? CASOS[ruta] : undefined;
    if (!caso) return { ok: false, status: 400, body: { error: "ruta no permitida" }, texto: "", json: true };
    const res = await caso(peticion(ruta, params, tz), token, uid);
    const texto = await res.text();
    try {
        return { ok: res.ok, status: res.status, body: JSON.parse(texto), texto, json: true };
    } catch {
        return { ok: res.ok, status: res.status, body: texto, texto, json: false };
    }
};

/** Lector de Kito: el contrato histórico de `consulta/api.ts` sobre `leerRuta`. */
export const crearLector = (token: string, uid: string, tz: string): Leer => async (ruta, params = {}) => {
    if (!(RUTAS_KITO as readonly string[]).includes(ruta)) return { error: "ruta no permitida" };
    const r = await leerRuta(ruta, params, token, uid, tz);
    if (!r.ok) return { error: r.status, detalle: r.texto.slice(0, 200) };
    if (!r.json) return { error: "respuesta no válida" };
    return r.body;
};
