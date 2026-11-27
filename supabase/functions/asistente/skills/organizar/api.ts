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
import { crearEscritorCon, RUTAS_MENUS_COMUNES } from "../../../_shared/homita/escritor.ts";
import type { RutasEscritura } from "../../../_shared/homita/escritor.ts";
import type { Escribir } from "../../core.ts";

/** Rutas permitidas: «METODO ruta». Lo que no esté aquí no se puede llamar desde Kito. */
const RUTAS: RutasEscritura = {
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
    // Skill `menus` (kito-menus): las rutas comunes de menús (borrador, recetas, compra, preferencias).
    // `POST meal/plan/accept` NO está y no debe estar nunca: Kito no acepta el menú, lo acepta la persona en
    // la app. Tampoco archive, copy, schedule ni el perfil del hogar.
    ...RUTAS_MENUS_COMUNES,
};

/** Escritor con el JWT, el uid y la zona del usuario. `homeId` lo aporta `runInHome` (contexto del hogar). */
export const crearEscritor = (token: string, uid: string, tz: string, _homeId?: string | null): Escribir =>
    crearEscritorCon(RUTAS, token, uid, tz);
