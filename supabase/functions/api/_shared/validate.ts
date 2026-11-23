// Validaciones de dominio PHP (mensajes exactos de Routine.php / Person.php) — puras salvo
// personIdsOf, que consulta get_persons para la visibilidad (Person::validateIds).
import { getInput, type ContractInput } from "./contract.ts";
import {
    errAlarmInvalid, errClientRequestIdInvalid, errEventEndDate, errInvalidDueAt, errInvalidPriority, errFeedbackInvalid, errEventEndDateRange, errPersonIdsIds, errPersonIdsList, errPersonInvalid,
    errRoutineActive, errRoutineDate, errRoutineDateRange, errRoutineDaysRange, errRoutineDaysRequired,
    errRoutineFrequency, errRoutineInterval, errRoutineTime, errRoutineTitleRequired,
} from "./errors.ts";
import { rpc } from "./supabase.ts";

const FREQUENCIES = ["daily", "weekly", "monthly"];
const TIME_RE = /^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// client_request_id opcional de task/create y task-list/create (0035, D-024): ausente o null →
// undefined (la clave p_client_request_id no se envía a la RPC: Android y la BD sin 0035 siguen
// igual); presente → string UUID o 400 'Invalid client_request_id' sin llamar a la RPC.
export const clientRequestIdOf = (input: ContractInput): string | undefined | Response => {
    const v = getInput(input, "client_request_id");
    if (v === null) return undefined;
    if (typeof v !== "string" || !UUID_RE.test(v)) return errClientRequestIdInvalid();
    return v.toLowerCase();
};

export const PRIORITIES = ["alta", "media", "baja"] as const;
export type Priority = typeof PRIORITIES[number];

// priority opcional de task (0037, D-026): clave ausente o null → undefined (no se envía
// p_priority a la RPC: create guarda 'media', update conserva, y la BD sin 0037 sigue igual);
// 'alta'|'media'|'baja' exacto (sensible a mayúsculas) → ese valor; cualquier otra cosa
// ('', números, 'ALTA', …) → 400 'Invalid priority' sin llamar a la RPC.
export const priorityOf = (input: ContractInput): Priority | undefined | Response => {
    const v = getInput(input, "priority");
    if (v === null) return undefined;
    if (typeof v !== "string" || !(PRIORITIES as readonly string[]).includes(v)) return errInvalidPriority();
    return v as Priority;
};

// due_at opcional de task (0041, fecha-limite-vencimiento): clave ausente o null → undefined (no se
// toca la fecha); '' → { clear: true } (borra la fecha); 'YYYY-MM-DD[ T]HH:MM[:SS]' → { value } normalizado a
// 'YYYY-MM-DD HH:MM:SS' en UTC naive; cualquier otra cosa → 400 'Invalid due_at' sin llamar a la RPC.
const DUE_AT = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})(:\d{2})?$/;
export type DueAt = { value?: string; clear?: boolean };
export const dueAtOf = (input: ContractInput): DueAt | undefined | Response => {
    const v = getInput(input, "due_at");
    if (v === null) return undefined;
    if (v === "") return { clear: true };
    if (typeof v !== "string") return errInvalidDueAt();
    const m = DUE_AT.exec(v);
    if (!m) return errInvalidDueAt();
    return { value: `${m[1]} ${m[2]}${m[3] ?? ":00"}` };
};

const isList = (v: unknown): v is unknown[] => Array.isArray(v) && v.every((_, i) => i in v);

// Routine::validateAlarm (Routine.php:83-86): int ≥ 0 o null. Rutas routine: sobre el input crudo
// (RoutineAlarm.php:11 / Routine::validate:90). Rutas event: sobre getInputInt (EventCreate:20,
// EventUpdate:19) o dentro de fn_apply_event_alarm (event/alarm, EventUser::apply:18) — R1-02.
export const validateAlarm = (v: unknown): number | null | Response => {
    if (v === null || v === undefined) return null;
    if (typeof v === "number" && Number.isInteger(v) && v >= 0) return v;
    return errAlarmInvalid();
};

export type EventEndDate = { present: boolean; value: string | null } | { err: Response };

// end_date opcional de event/create y event/update (0030). `present` = la clave viene en el body
// (incluido null o ''), que en update significa "fijar o borrar"; ausente = conservar el guardado.
// null/'' → value null. Si hay valor: 'YYYY-MM-DD' real (round-trip) y no anterior al día de
// `dateAt` ('YYYY-MM-DD HH:MM:SS'). La RPC repite las comprobaciones (defensa ante llamada directa).
export const validateEventEndDate = (input: ContractInput, dateAt: string | null): EventEndDate => {
    const present = "end_date" in input;
    const raw = getInput(input, "end_date");
    if (raw === null || raw === "") return { present, value: null };
    if (typeof raw !== "string" || !DATE_RE.test(raw)) return { err: errEventEndDate() };
    const parsed = new Date(raw + "T00:00:00Z");
    if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== raw) {
        return { err: errEventEndDate() };
    }
    if (dateAt !== null && raw < dateAt.slice(0, 10)) return { err: errEventEndDateRange() };
    return { present, value: raw };
};

export type RoutineValues = {
    title: string;
    frequency: string;
    interval: number;
    days: number[];
    time: string;
    start_date: string | null;
    end_date: string | null;
    active: boolean;
};

// Routine::validate (Routine.php:50-82). `current` = frequency/interval actuales (solo update:
// los defaults vienen de ahí, como validate($data, $current) de PHP).
export const validateRoutine = (
    input: ContractInput,
    current: { frequency: string; interval: number } | null,
): { values: RoutineValues } | { err: Response } => {
    const rawTitle = getInput(input, "title");
    if (typeof rawTitle !== "string") return { err: errRoutineTitleRequired() };
    const title = rawTitle.trim();

    const frequency = getInput(input, "frequency") ?? current?.frequency ?? "weekly";
    const interval = getInput(input, "interval") ?? current?.interval ?? 1;
    if (!FREQUENCIES.includes(frequency as string)) return { err: errRoutineFrequency() };
    if (typeof interval !== "number" || !Number.isInteger(interval) || interval < 1 || interval > 99) {
        return { err: errRoutineInterval() };
    }

    // Solo la semanal usa días de la semana: la diaria/mensual quedan en []
    const daysRaw = frequency === "weekly" ? (getInput(input, "days") ?? null) : [];
    if (title === "" || !isList(daysRaw) || (frequency === "weekly" && (daysRaw as unknown[]).length === 0)) {
        return { err: errRoutineDaysRequired() };
    }
    for (const d of daysRaw as unknown[]) {
        if (typeof d !== "number" || !Number.isInteger(d) || d < 1 || d > 7) return { err: errRoutineDaysRange() };
    }
    const days = [...new Set(daysRaw as number[])].sort((a, b) => a - b);

    const time = getInput(input, "time");
    if (typeof time !== "string" || !TIME_RE.test(time)) return { err: errRoutineTime() };

    const start = getInput(input, "start_date") ?? null;
    const end = getInput(input, "end_date") ?? null;
    for (const date of [start, end]) {
        if (date === null) continue;
        if (typeof date !== "string" || !DATE_RE.test(date)) return { err: errRoutineDate() };
        const parsed = new Date(date + "T00:00:00Z");
        if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== date) {
            return { err: errRoutineDate() };
        }
    }
    if (start === null || (end !== null && (end as string) < (start as string))) {
        return { err: errRoutineDateRange() };
    }

    if (typeof getInput(input, "active") !== "boolean") return { err: errRoutineActive() };

    return {
        values: {
            title,
            frequency: frequency as string,
            interval: interval as number,
            days,
            time: time as string,
            start_date: start as string | null,
            end_date: end as string | null,
            active: getInput(input, "active") as boolean,
        },
    };
};

// Person::validateIds (Person.php:60-70): null si no se envía (no se toca la asignación), lista de
// ids únicos ≥1 visibles para el usuario, o el error exacto. `visible` = ids de get_persons.
export const validatePersonIdsWith = (
    input: ContractInput,
    visible: number[],
): number[] | null | Response => {
    const ids = getInput(input, "person_ids");
    if (ids === null || ids === undefined) return null;
    if (!isList(ids)) return errPersonIdsList();
    for (const id of ids as unknown[]) {
        if (typeof id !== "number" || !Number.isInteger(id) || id < 1) return errPersonIdsIds();
    }
    const uniq = [...new Set(ids as number[])];
    if (uniq.length === 0) return [];
    for (const id of uniq) {
        if (!visible.includes(id)) return errPersonInvalid();
    }
    return uniq;
};

// Igual que validatePersonIdsWith consultando primero la visibilidad (get_persons) como hace PHP
// con Person::VISIBLE. Sin `person_ids` en el input no hay consulta (como validateIds → null).
// 1.5 (§5): p_include_inactive := true — la lista completa que envía el cliente puede traer un
// miembro ya desactivado pero asignado (histórico, K11); la barrera de inactivos nuevos es el
// trigger/RPC (mismo mensaje 'Invalid person').
export const personIdsOf = async (
    input: ContractInput,
    token: string,
): Promise<number[] | null | Response> => {
    const ids = getInput(input, "person_ids");
    if (ids === null || ids === undefined) return null;
    const res = await rpc("get_persons", { p_include_inactive: true }, token);
    if (!res.ok) return errPersonInvalid();
    const rows: { id: number }[] = await res.json().catch(() => []);
    return validatePersonIdsWith(input, rows.map((r) => r.id));
};

// ── feedback (POST /feedback) ──

export type FeedbackPantalla = { nombre: string; acciones: string[] };
export type FeedbackSeccion = { nombre: string; pantallas: FeedbackPantalla[] };

// Catálogo de la app (FeedbackCatalog.swift): sección › pantalla › acción. Mantener sincronizado a mano; el
// fixture tests/fixtures/feedback_catalog.json es la referencia y feedback_test.ts exige igualdad exacta.
// Ningún nombre contiene ": " (el parseo de `subseccion` usa el último). El valor enviado es el nombre visible.
// Una pantalla alcanzable desde varios sitios lleva el camino desde la raíz de la sección, con " › ".
export const FEEDBACK_CATALOG: FeedbackSeccion[] = [
    {
        nombre: "Inicio",
        pantallas: [
            { nombre: "Inicio", acciones: ["Ver / cargar", "Tirar para actualizar", "Crear › Tarea", "Crear › Evento", "Ir a Hogar"] },
            { nombre: "Inicio › Nueva tarea", acciones: ["Título", "Lista", "Personas", "Crear tarea", "Cancelar"] },
            { nombre: "Inicio › Nuevo evento", acciones: ["Título", "Fecha y hora", "Fecha de fin", "Calendario", "Aviso", "Personas", "Crear evento", "Cancelar"] },
            { nombre: "Hoy · Eventos", acciones: ["Ver / cargar", "Ir a Hoy · Eventos", "Ya pasaron", "Reintentar"] },
            { nombre: "Tareas pendientes", acciones: ["Ver / cargar", "Ir a Tareas pendientes", "Marcar hecha", "Lista", "Deslizar entre listas", "Ver más", "Reintentar"] },
            { nombre: "Rutinas de hoy", acciones: ["Ver / cargar", "Ver todas", "Completadas", "Reintentar"] },
        ],
    },
    {
        nombre: "Tareas",
        pantallas: [
            { nombre: "Tareas", acciones: ["Ver / cargar", "Tirar para actualizar", "Nueva tarea", "Filtrar", "Campo Nueva tarea", "Marcar hecha", "Editar tarea", "Deslizar para eliminar", "Editar", "Plegar / desplegar lista", "Eliminar tareas completadas"] },
            { nombre: "Tareas › Nueva tarea", acciones: ["Título", "Lista", "Personas", "Crear tarea", "Cancelar"] },
            { nombre: "Tareas › Editar tarea", acciones: ["Título", "Personas", "Personas con acceso", "Guardar", "Eliminar tarea", "Cancelar"] },
            { nombre: "Listas", acciones: ["Ver / cargar", "Tirar para actualizar", "Abrir lista", "Nueva lista"] },
            { nombre: "Listas › Nueva lista", acciones: ["Nombre", "Color", "Orden de las tareas", "Widget", "Dashboard", "Crear lista", "Cancelar"] },
            { nombre: "Detalle de lista", acciones: ["Ver / cargar", "Tirar para actualizar", "Campo Nueva tarea", "Marcar hecha", "Editar tarea", "Deslizar para eliminar", "Reordenar", "Editar lista", "Eliminar todas las completadas", "Email a invitar", "Invitar", "Quitar persona", "Dar acceso", "Lectura", "Edición"] },
            { nombre: "Detalle de lista › Editar tarea", acciones: ["Título", "Personas", "Personas con acceso", "Guardar", "Eliminar tarea", "Cancelar"] },
            { nombre: "Detalle de lista › Editar lista", acciones: ["Nombre", "Color", "Orden de las tareas", "Widget", "Dashboard", "Guardar", "Eliminar lista", "Cancelar"] },
        ],
    },
    {
        nombre: "Calendario",
        pantallas: [
            { nombre: "Eventos", acciones: ["Ver / cargar", "Semana anterior", "Semana siguiente", "Deslizar entre semanas", "Tira de semana", "Hoy", "Elegir fecha", "Nuevo evento", "Abrir evento"] },
            { nombre: "Eventos › Elegir fecha", acciones: ["Fecha", "Hoy", "Listo"] },
            { nombre: "Eventos › Nuevo evento", acciones: ["Título", "Fecha y hora", "Fecha de fin", "Calendario", "Aviso", "Personas", "Crear evento", "Cancelar"] },
            { nombre: "Eventos › Editar evento", acciones: ["Título", "Fecha y hora", "Fecha de fin", "Aviso", "Personas", "Guardar", "Eliminar evento", "Cancelar"] },
            { nombre: "Rutinas", acciones: ["Ver / cargar", "Tirar para actualizar", "Nueva rutina", "Abrir rutina", "Deslizar para eliminar"] },
            { nombre: "Rutinas › Nueva rutina", acciones: ["Título", "Calendario", "Frecuencia", "Horario", "Activa", "Aviso", "Personas", "Crear rutina", "Cancelar"] },
            { nombre: "Rutinas › Editar rutina", acciones: ["Título", "Frecuencia", "Horario", "Activa", "Aviso", "Personas", "Guardar", "Eliminar rutina", "Cancelar"] },
            { nombre: "Calendarios", acciones: ["Ver / cargar", "Tirar para actualizar", "Nuevo calendario", "Abrir calendario"] },
            { nombre: "Calendarios › Nuevo calendario", acciones: ["Nombre", "Color", "Widget", "Dashboard", "Crear calendario", "Cancelar"] },
            { nombre: "Calendarios › Editar calendario", acciones: ["Nombre", "Color", "Widget", "Dashboard", "Guardar", "Email a invitar", "Invitar", "Quitar persona", "Dar acceso", "Lectura", "Edición", "Eliminar calendario", "Cancelar"] },
        ],
    },
    {
        nombre: "Hogar",
        pantallas: [
            { nombre: "Hogar", acciones: ["Ver / cargar", "Tirar para actualizar", "Hogar activo", "Ver más", "Crear invitación", "Invitaciones pendientes", "Administración", "Reintentar"] },
            { nombre: "Permisos del hogar", acciones: ["Cerrar"] },
            { nombre: "Hogar › Nueva invitación", acciones: ["Tipo", "Vincular a un miembro (opcional)", "Email del invitado", "Crear", "Cancelar"] },
            { nombre: "Hogar › Invitación creada", acciones: ["Copiar código", "Enviar por WhatsApp", "Compartir invitación", "Listo"] },
            { nombre: "Hogar › Invitaciones", acciones: ["Ver / cargar", "Tirar para actualizar", "Crear invitación", "Revocar", "Reintentar"] },
            { nombre: "Hogar › Invitaciones › Nueva invitación", acciones: ["Tipo", "Vincular a un miembro (opcional)", "Email del invitado", "Crear", "Cancelar"] },
            { nombre: "Hogar › Invitaciones › Invitación creada", acciones: ["Copiar código", "Enviar por WhatsApp", "Compartir invitación", "Listo"] },
            { nombre: "Administración", acciones: ["Configuración", "Administradores", "Miembros", "Invitaciones", "Accesos", "Auditoría"] },
            { nombre: "Administración › Configuración", acciones: ["Ver / cargar", "Nombre", "Zona horaria", "Guardar cambios", "Reintentar"] },
            { nombre: "Administración › Configuración › Zona horaria", acciones: ["Buscar zona horaria", "Elegir zona", "Cerrar"] },
            { nombre: "Administración › Administradores", acciones: ["Ver / cargar", "Tirar para actualizar", "Quitar admin", "Quitar", "Hacer admin", "Transferir", "Salir", "Reintentar"] },
            { nombre: "Administración › Miembros", acciones: ["Ver / cargar", "Tirar para actualizar", "Agregar", "Abrir miembro", "Reintentar"] },
            { nombre: "Administración › Miembros › Nuevo miembro", acciones: ["Nombre (1-50)", "Color", "Tipo", "Agregar", "Cancelar"] },
            { nombre: "Administración › Miembros › Editar miembro", acciones: ["Nombre (1-50)", "Color", "Tipo", "Estado", "Guardar", "Cambiar tipo", "Cancelar"] },
            { nombre: "Administración › Invitaciones", acciones: ["Ver / cargar", "Tirar para actualizar", "Crear invitación", "Revocar", "Reintentar"] },
            { nombre: "Administración › Invitaciones › Nueva invitación", acciones: ["Tipo", "Vincular a un miembro (opcional)", "Email del invitado", "Crear", "Cancelar"] },
            { nombre: "Administración › Invitaciones › Invitación creada", acciones: ["Copiar código", "Enviar por WhatsApp", "Compartir invitación", "Listo"] },
            { nombre: "Administración › Accesos", acciones: ["Ver / cargar", "Tirar para actualizar", "Editar", "Reintentar"] },
            { nombre: "Administración › Accesos › Editor de accesos", acciones: ["Interruptor de permiso", "Restablecer a tipo", "Guardar", "Cancelar"] },
            { nombre: "Administración › Auditoría", acciones: ["Ver / cargar", "Tirar para actualizar", "Todo", "Acción", "Persona", "Cargar más", "Reintentar"] },
        ],
    },
    {
        nombre: "Ajustes",
        pantallas: [
            { nombre: "Ajustes", acciones: ["Nombre", "Email", "Nueva contraseña (opcional, mínimo 8)", "Guardar cambios", "Personas", "Avisos, widgets y pantalla de bloqueo", "Unirse a un hogar con un código", "Enviar feedback", "Modo oscuro", "Cerrar sesión"] },
            { nombre: "Personas", acciones: ["Ver / cargar", "Tirar para actualizar", "Nueva persona", "Editar persona", "Eliminar persona", "Reintentar"] },
            { nombre: "Personas › Nueva persona", acciones: ["Nombre (1-50)", "Color", "Crear persona", "Cancelar"] },
            { nombre: "Personas › Editar persona", acciones: ["Nombre (1-50)", "Color", "Guardar", "Eliminar persona", "Cancelar"] },
            { nombre: "Notificaciones", acciones: ["Eventos", "Rutinas", "Resumen de tareas pendientes", "Hora del resumen", "Rutinas en tiempo real", "Datos en widgets", "Abrir Ajustes de iOS"] },
            { nombre: "Unirse a un hogar", acciones: ["Código de invitación", "Unirse", "Ver el hogar"] },
            { nombre: "Enviar feedback", acciones: ["Sección", "Pantalla", "Acción", "Tipo", "Qué pasó o qué mejorarías", "Enviar feedback"] },
        ],
    },
    {
        nombre: "Acceso",
        pantallas: [
            { nombre: "Bienvenida", acciones: ["Iniciar sesión", "Registrarse"] },
            { nombre: "Iniciar sesión", acciones: ["Email", "Contraseña", "Iniciar sesión"] },
            { nombre: "Registrarse", acciones: ["Nombre", "Email", "Contraseña (mínimo 8)", "Código (opcional)", "Crear cuenta"] },
            { nombre: "No tienes ningún hogar", acciones: ["Nombre del hogar", "Crear hogar", "Aceptar invitación", "Ahora no"] },
            { nombre: "Cargando inicio", acciones: ["Ver / cargar"] },
            { nombre: "No se pudo cargar tu hogar", acciones: ["Reintentar"] },
        ],
    },
    {
        nombre: "General / otro",
        pantallas: [
            { nombre: "Otro", acciones: ["General"] },
            { nombre: "Banner sin conexión", acciones: ["General"] },
            { nombre: "Animación de arranque", acciones: ["General"] },
        ],
    },
];
export const FEEDBACK_SECCIONES = FEEDBACK_CATALOG.map((s) => s.nombre);

// TRANSITORIO (compat con el catálogo 2026-11-19, apps instaladas): sub-áreas por sección y acciones ver/crear/
// editar/eliminar en minúscula. Se retira en un cambio posterior, no antes de que las apps viejas dejen de usarse.
const FEEDBACK_LEGACY_SUBAREAS: Record<string, string[]> = {
    Inicio: ["resumen del día", "eventos de hoy", "rutinas de hoy"],
    Tareas: ["listas", "tareas"],
    Calendario: ["eventos", "rutinas", "calendarios"],
    Hogar: ["miembros", "invitaciones", "administradores", "permisos"],
    Ajustes: ["perfil", "notificaciones", "cuenta"],
};
const FEEDBACK_LEGACY_ACCIONES = ["ver", "crear", "editar", "eliminar"];
export const FEEDBACK_TIPOS = ["bug", "mejora"];
// Límite en UTF-16 code units (String.length de JS). El cliente iOS cuenta igual (`String.utf16.count`),
// así un emoji (2 unidades) cuenta lo mismo en ambos lados.
export const FEEDBACK_TEXTO_MAX = 2000;
export const FEEDBACK_SUBSECCION_MAX = 100;

// "<pantalla>: <acción>" en el catálogo nuevo: pantalla y acción exactas de la sección (comparación en arrays).
const isCurrentSubseccion = (seccion: string, sub: string): boolean => {
    const i = sub.lastIndexOf(": ");
    if (i <= 0 || i + 2 >= sub.length) return false;
    const pantalla = sub.slice(0, i);
    const accion = sub.slice(i + 2);
    const sec = FEEDBACK_CATALOG.find((s) => s.nombre === seccion);
    const pan = sec?.pantallas.find((p) => p.nombre === pantalla);
    return pan !== undefined && pan.acciones.includes(accion);
};

// Catálogo 2026-11-19 (transitorio): regex vieja, sub-área de la sección y acción de la lista vieja.
const isLegacySubseccion = (seccion: string, sub: string): boolean => {
    const m = sub.match(/^(.+): (\S+)$/);
    if (m === null) return false;
    const subareas = Object.hasOwn(FEEDBACK_LEGACY_SUBAREAS, seccion) ? FEEDBACK_LEGACY_SUBAREAS[seccion] : [];
    // "resumen del día" solo admitía "ver" en el cliente viejo (la Edge vieja aceptaba cualquiera; se estrecha).
    if (!subareas.includes(m[1])) return false;
    if (m[1] === "resumen del día") return m[2] === "ver";
    return FEEDBACK_LEGACY_ACCIONES.includes(m[2]);
};

export type FeedbackValues = { seccion: string; subseccion: string | null; tipo: string; texto: string };

// Valida el cuerpo de POST /feedback (pura). `subseccion` opcional; si viene: "<pantalla>: <acción>" con
// pantalla de la sección y acción de esa pantalla (FEEDBACK_CATALOG), o un par del catálogo viejo (transitorio),
// y longitud <= 100. `texto` se recorta y debe tener 1..2000.
export const validateFeedback = (input: ContractInput): FeedbackValues | Response => {
    const seccion = getInput(input, "seccion");
    if (typeof seccion !== "string" || !FEEDBACK_SECCIONES.includes(seccion)) {
        return errFeedbackInvalid("Invalid seccion");
    }
    const tipo = getInput(input, "tipo");
    if (typeof tipo !== "string" || !FEEDBACK_TIPOS.includes(tipo)) return errFeedbackInvalid("Invalid tipo");
    const rawTexto = getInput(input, "texto");
    const texto = typeof rawTexto === "string" ? rawTexto.trim() : "";
    if (texto.length === 0) return errFeedbackInvalid("Texto is required");
    if (texto.length > FEEDBACK_TEXTO_MAX) return errFeedbackInvalid("Texto is too long (max 2000 characters)");
    const rawSub = getInput(input, "subseccion");
    let subseccion: string | null = null;
    if (rawSub !== null && rawSub !== undefined && rawSub !== "") {
        if (typeof rawSub !== "string" || rawSub.length > FEEDBACK_SUBSECCION_MAX) {
            return errFeedbackInvalid("Invalid subseccion");
        }
        if (!isCurrentSubseccion(seccion, rawSub) && !isLegacySubseccion(seccion, rawSub)) {
            return errFeedbackInvalid("Invalid subseccion");
        }
        subseccion = rawSub;
    }
    return { seccion, subseccion, tipo, texto };
};
