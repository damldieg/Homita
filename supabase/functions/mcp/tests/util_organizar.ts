// Ayudas de los tests de las herramientas de escritura de organizar.
import { crearMundo, llamarTool, UID } from "./util.ts";
import type { EscrituraFalsa, Mundo } from "./util.ts";

export { UID };

export const ok = (data: unknown = { id: 1 }, status = 200): EscrituraFalsa => ({ ok: true, status, data });
export const fallo = (status: number, error?: string): EscrituraFalsa => ({ ok: false, status, data: { error }, ...(error ? { error } : {}) });

export const LISTAS = [
    { id: 1, name: "Casa", color: "#112233", sort: "title", widget: 0, dashboard: 1, pending_task_count: 3, can_edit: true },
    { id: 2, name: "Compra", color: "#445566", widget: true, dashboard: false, pending_task_count: 0, can_edit: true },
];
export const CALENDARIOS = [
    { id: 10, name: "Familia", color: "#aa0000", widget: 1, dashboard: 0, can_edit: true },
    { id: 11, name: "Fútbol", color: "#00aa00", widget: true, dashboard: true, can_edit: true },
];
export const PERSONAS = [
    { id: 20, name: "Lucía", app_user_id: 502, home_id: 7 },
    { id: 21, name: "Pedro", app_user_id: null, home_id: 7 },
    { id: 22, name: "Yo", app_user_id: 501, home_id: 7 },
    { id: 30, name: "De otro hogar", app_user_id: 600, home_id: 99 },
];
export const TAREA = { id: 5, title: "Llamar", task_list_id: 2, priority: "media", person_ids: [20] };
export const EVENTO = { id: 6, title: "Cena", date_at: "2030-02-01 20:30:00", end_date: null, alarm: 15 };
export const RUTINA = {
    id: 7, title: "Regar", frequency: "weekly", interval: 2, days: [1, 3], time: "08:30:00", start_date: "2030-01-01",
    end_date: "2030-06-01", active: true,
};

/** Un mundo con las escrituras habituales por defecto (todas ok con id 1) y los detalles de tarea, evento y rutina. */
export const mundo = (
    lecturas: Record<string, unknown> = {},
    falsas: Record<string, EscrituraFalsa> = {},
    over: Parameters<typeof crearMundo>[1] = {},
): Mundo =>
    crearMundo(
        { "task-list": LISTAS, calendar: CALENDARIOS, person: PERSONAS, task: [], ...lecturas },
        { appUserId: () => Promise.resolve("501"), ...over },
        {},
        {
            "POST task-list/create": ok({ id: 9 }, 201), "PATCH task-list/update": ok(), "DELETE task-list/delete": ok({}),
            "POST task/create": ok({ id: 8 }, 201), "PATCH task/update": ok(), "PATCH task/complete": ok(), "DELETE task/delete": ok({}),
            "GET task/detail": ok(TAREA), "GET event/detail": ok(EVENTO), "GET routine/detail": ok(RUTINA),
            "POST event/create": ok({ id: 8 }, 201), "PATCH event/update": ok(), "DELETE event/delete": ok({}),
            "POST routine/create": ok({ id: 8 }, 201), "PATCH routine/update": ok(), "DELETE routine/delete": ok({}),
            "POST calendar/create": ok({ id: 40 }, 201), "PATCH calendar/update": ok(), "DELETE calendar/delete": ok({}),
            "PATCH calendar/user": ok({}),
            ...falsas,
        },
    );

/** Llama a la herramienta y devuelve el resultado ya como objeto (`datos`), el texto crudo y `isError`. */
export const llamar = async (m: Mundo, nombre: string, args: Record<string, unknown> = {}) => {
    const { resultado, datos } = await llamarTool(m, nombre, args);
    return { datos: datos as Record<string, unknown>, isError: resultado?.isError === true, texto: resultado?.content?.[0]?.text ?? "" };
};

/** Escrituras que no son lecturas de detalle. */
export const escrituras = (m: Mundo) => m.escrituras.filter((e) => e.metodo !== "GET");
