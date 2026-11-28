// Fechas de «organizar»: de la hora local que dice el usuario a lo que espera el api.
//  - `event.date_at` y las rutinas usan hora local de pared sin zona ('YYYY-MM-DD HH:MM:SS').
//  - `task.due_at` es un instante UTC sin zona.
import { desfaseMs, isoDeInstante } from "../fechas.ts";

const FECHA_HORA = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$/;

export interface Pared {
    y: number;
    mo: number;
    d: number;
    h: number | null;
    mi: number | null;
    s: number;
}

/** 'AAAA-MM-DD', 'AAAA-MM-DD HH:MM' o con 'T' y segundos. `null` si no tiene esa forma o la fecha no existe. */
export const parsearPared = (v: string): Pared | null => {
    const m = FECHA_HORA.exec(v.trim());
    if (!m) return null;
    const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
    const f = new Date(Date.UTC(y, mo - 1, d));
    if (f.getUTCFullYear() !== y || f.getUTCMonth() !== mo - 1 || f.getUTCDate() !== d) return null;
    const h = m[4] === undefined ? null : Number(m[4]);
    const mi = m[5] === undefined ? null : Number(m[5]);
    if ((h !== null && h > 23) || (mi !== null && mi > 59)) return null;
    return { y, mo, d, h, mi, s: m[6] === undefined ? 0 : Math.min(Number(m[6]), 59) };
};

const dos = (n: number): string => String(n).padStart(2, "0");

/** 'YYYY-MM-DD HH:MM:SS' de una hora de pared (sin hora → `porDefecto`). */
export const paredTexto = (p: Pared, porDefecto = "00:00"): string => {
    const hora = p.h === null || p.mi === null ? `${porDefecto}:00` : `${dos(p.h)}:${dos(p.mi)}:${dos(p.s)}`;
    return `${String(p.y).padStart(4, "0")}-${dos(p.mo)}-${dos(p.d)} ${hora}`;
};

/** Hora local de `tz` → instante UTC 'YYYY-MM-DD HH:MM:SS'. Sin hora se toma el final del día (23:59). */
export const localAUtc = (p: Pared, tz: string): string => {
    const wall = Date.UTC(p.y, p.mo - 1, p.d, p.h ?? 23, p.mi ?? 59, p.s);
    const primera = wall - desfaseMs(wall, tz);
    const utc = wall - desfaseMs(primera, tz);
    return new Date(utc).toISOString().slice(0, 19).replace("T", " ");
};

/** Hoy (AAAA-MM-DD) en la zona del usuario. */
export const hoyLocal = (now: Date, tz: string): string => isoDeInstante(now.getTime(), tz).slice(0, 10);
