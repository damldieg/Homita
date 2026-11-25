// Escritor del `api` para Kito: llama en proceso a los casos de uso de escritura con el JWT del usuario, así
// que heredan RLS, ACL (can_edit) y el hogar activo sin duplicar lógica. Es lo único de la skill `organizar`
// que importa `api`; las herramientas reciben el escritor por `ctx.escribir` y los tests inyectan uno falso.
import {
    handleCalendarCreate, handleCalendarDelete, handleCalendarUpdate, handleCalendarUserAccess,
} from "../../../api/usecases/calendars.ts";
import {
    handleEventCreate, handleEventDelete, handleEventDetail, handleEventUpdate,
} from "../../../api/usecases/events.ts";
import { handleRoutineCreate, handleRoutineDelete, handleRoutineDetail, handleRoutineUpdate } from "../../../api/usecases/routines.ts";
import {
    handleTaskListCreate, handleTaskListDelete, handleTaskListUpdate,
} from "../../../api/usecases/task-lists.ts";
import {
    handleTaskComplete, handleTaskCreate, handleTaskDelete, handleTaskDetail, handleTaskUpdate,
} from "../../../api/usecases/tasks.ts";
import type { Escribir, RespuestaApi } from "../../core.ts";

type Manejador = (req: Request, token: string, uid: string) => Promise<Response>;

/** Rutas permitidas: «METODO ruta». Lo que no esté aquí no se puede llamar desde Kito. */
const RUTAS: Record<string, Manejador> = {
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

const respuesta = async (res: Response): Promise<RespuestaApi> => {
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

/** Escritor con el JWT, el uid y la zona del usuario. `homeId` lo aporta `runInHome` (contexto del hogar). */
export const crearEscritor = (token: string, uid: string, tz: string, _homeId?: string | null): Escribir =>
async (metodo, ruta, cuerpo = {}) => {
    const manejador = RUTAS[`${metodo} ${ruta}`];
    if (!manejador) return { ok: false, status: 400, data: null, error: "ruta no permitida" };
    const url = new URL(`https://asistente.local/api/${ruta}`);
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
    return await respuesta(await manejador(req, token, uid));
};
