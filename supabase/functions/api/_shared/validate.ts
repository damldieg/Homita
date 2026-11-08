// Validaciones de dominio PHP (mensajes exactos de Routine.php / Person.php) — puras salvo
// personIdsOf, que consulta get_persons para la visibilidad (Person::validateIds).
import { getInput, type PhpInput } from "./contract.ts";
import {
    errAlarmInvalid, errPersonIdsIds, errPersonIdsList, errPersonInvalid,
    errRoutineActive, errRoutineDate, errRoutineDateRange, errRoutineDaysRange, errRoutineDaysRequired,
    errRoutineFrequency, errRoutineInterval, errRoutineTime, errRoutineTitleRequired,
} from "./errors.ts";
import { rpc } from "./supabase.ts";

const FREQUENCIES = ["daily", "weekly", "monthly"];
const TIME_RE = /^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const isList = (v: unknown): v is unknown[] => Array.isArray(v) && v.every((_, i) => i in v);

// Routine::validateAlarm (Routine.php:83-86): int ≥ 0 o null. Rutas routine: sobre el input crudo
// (RoutineAlarm.php:11 / Routine::validate:90). Rutas event: sobre getInputInt (EventCreate:20,
// EventUpdate:19) o dentro de fn_apply_event_alarm (event/alarm, EventUser::apply:18) — R1-02.
export const validateAlarm = (v: unknown): number | null | Response => {
    if (v === null || v === undefined) return null;
    if (typeof v === "number" && Number.isInteger(v) && v >= 0) return v;
    return errAlarmInvalid();
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
    input: PhpInput,
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
    input: PhpInput,
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
export const personIdsOf = async (
    input: PhpInput,
    token: string,
): Promise<number[] | null | Response> => {
    const ids = getInput(input, "person_ids");
    if (ids === null || ids === undefined) return null;
    const res = await rpc("get_persons", {}, token);
    if (!res.ok) return errPersonInvalid();
    const rows: { id: number }[] = await res.json().catch(() => []);
    return validatePersonIdsWith(input, rows.map((r) => r.id));
};
