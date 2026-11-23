// Lector del `api` para Kito: llama en proceso a los casos de uso GET con el JWT del usuario, así que
// heredan RLS, ACL y el filtro del hogar activo (X-Home-Id) sin duplicar lógica. Es lo único de la skill que
// importa `api`; las herramientas reciben el lector por `ctx.leer`, y los tests inyectan uno falso.
import { handlePersonIndex } from "../../../api/usecases/persons.ts";
import { handleTask } from "../../../api/usecases/tasks.ts";
import { handleTaskListIndex } from "../../../api/usecases/task-lists.ts";
import { handleEvent } from "../../../api/usecases/events.ts";
import { handleRoutineIndex } from "../../../api/usecases/routines.ts";
import { handleCalendarIndex, handleCalendarUserIndex } from "../../../api/usecases/calendars.ts";
import { handleHomeIndex } from "../../../api/usecases/homes.ts";
import type { Leer } from "../../core.ts";

/** Ejecuta un caso de uso GET y devuelve su JSON; un error HTTP se devuelve como `{error, detalle}`. */
const leerRespuesta = async (res: Response): Promise<unknown> => {
    const texto = await res.text();
    if (!res.ok) return { error: res.status, detalle: texto.slice(0, 200) };
    try {
        return JSON.parse(texto);
    } catch {
        return { error: "respuesta no válida" };
    }
};

const peticion = (ruta: string, params: Record<string, string | undefined>, tz: string): Request => {
    const url = new URL(`https://asistente.local/api/${ruta}`);
    for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") url.searchParams.set(k, v);
    url.searchParams.set("timezone", tz);
    return new Request(url.toString(), { method: "GET" });
};

export const crearLector = (token: string, uid: string, tz: string): Leer => async (ruta, params = {}) => {
    const req = peticion(ruta, params, tz);
    switch (ruta) {
        case "event": return await leerRespuesta(await handleEvent(req, token, uid));
        case "routine": return await leerRespuesta(await handleRoutineIndex(req, token, uid));
        case "task": return await leerRespuesta(await handleTask(req, token));
        case "task-list": return await leerRespuesta(await handleTaskListIndex(req, token));
        case "person": return await leerRespuesta(await handlePersonIndex(req, token));
        case "calendar": return await leerRespuesta(await handleCalendarIndex(req, token));
        case "calendar/user": return await leerRespuesta(await handleCalendarUserIndex(req, token));
        case "home": return await leerRespuesta(await handleHomeIndex(req, token));
        default: return { error: "ruta no permitida" };
    }
};
