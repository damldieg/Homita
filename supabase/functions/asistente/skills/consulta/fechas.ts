// Utilidades de fecha de la skill `consulta`. Sin dependencias de `api` (se testean sin entorno).
//
// Dos convenciones del dato (change kito-calidad-consulta, Q1/Q3):
//  - `event.date_at` es hora local de pared sin zona ('YYYY-MM-DD HH:MM:SS'). El api convierte el epoch de
//    `start_date`/`end_date` a texto en UTC, así que para que el SQL compare horas de pared hay que mandar
//    un epoch «de pared» (UTC aparente = hora local). Ver `epochPared`.
//  - `task.due_at` es un instante UTC sin zona. Se compara en UTC y se muestra convertido a la zona del usuario.

export const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/** Día siguiente a YYYY-MM-DD, en el mismo formato (aritmética en UTC, sin zona). */
export const diaSiguiente = (ymd: string): string => {
    const [y, m, d] = ymd.split("-").map(Number);
    return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
};

/** Epoch (segundos) «de pared»: su texto UTC es exactamente la hora local indicada. No depende de la zona. */
export const epochPared = (ymd: string, hh = 0, mm = 0, ss = 0): number => {
    const [y, m, d] = ymd.split("-").map(Number);
    return Date.UTC(y, m - 1, d, hh, mm, ss) / 1000;
};

/** Inicio de un rango de días: 00:00:00 de `desde`. */
export const inicioRango = (desde: string): number => epochPared(desde);

/** Fin de un rango de días: último segundo de `hasta` (el predicado del SQL es `<=`). */
export const finRango = (hasta: string): number => epochPared(diaSiguiente(hasta)) - 1;

const partes = (ts: number, tz: string): number => {
    const p = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", second: "2-digit",
    }).formatToParts(new Date(ts));
    const g = (t: string) => Number(p.find((x) => x.type === t)!.value);
    return Date.UTC(g("year"), g("month") - 1, g("day"), g("hour"), g("minute"), g("second")) - ts;
};

/** Desfase de `tz` (ms) en el instante `ts`. */
export const desfaseMs = (ts: number, tz: string): number => partes(Math.floor(ts / 1000) * 1000, tz);

const pad = (n: number): string => String(n).padStart(2, "0");

const sufijo = (offMs: number): string => {
    const min = Math.round(offMs / 60000);
    const signo = min < 0 ? "-" : "+";
    const a = Math.abs(min);
    return `${signo}${pad(Math.floor(a / 60))}:${pad(a % 60)}`;
};

const WALL = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?/;

/** Hora de pared local 'YYYY-MM-DD HH:MM:SS' → ISO con desfase de la zona ('2026-11-24T18:30:00+01:00'). */
export const isoDeParedLocal = (pared: string | null | undefined, tz: string): string | null => {
    if (typeof pared !== "string") return null;
    const m = WALL.exec(pared);
    if (!m) return null;
    const [, y, mo, d, h, mi, s] = m;
    const wall = Date.UTC(+y, +mo - 1, +d, +h, +mi, +(s ?? "0"));
    const primera = wall - desfaseMs(wall, tz);
    const off = desfaseMs(primera, tz);
    return `${y}-${mo}-${d}T${h}:${mi}:${s ?? "00"}${sufijo(off)}`;
};

/** Instante UTC sin zona 'YYYY-MM-DD HH:MM:SS' (p. ej. task.due_at) → epoch en ms, o null. */
export const instanteUtcNaive = (utc: string | null | undefined): number | null => {
    if (typeof utc !== "string") return null;
    const m = WALL.exec(utc);
    if (!m) return null;
    const [, y, mo, d, h, mi, s] = m;
    return Date.UTC(+y, +mo - 1, +d, +h, +mi, +(s ?? "0"));
};

/** Instante (ms) → ISO con el desfase local de `tz`. */
export const isoDeInstante = (ms: number, tz: string): string => {
    const off = desfaseMs(ms, tz);
    const l = new Date(ms + off);
    return `${l.getUTCFullYear()}-${pad(l.getUTCMonth() + 1)}-${pad(l.getUTCDate())}T${pad(l.getUTCHours())}:${
        pad(l.getUTCMinutes())
    }:${pad(l.getUTCSeconds())}${sufijo(off)}`;
};

/** `due_at` (UTC naive) → ISO local, o null si falta o no es válido. */
export const dueAtALocal = (due: string | null | undefined, tz: string): string | null => {
    const ms = instanteUtcNaive(due);
    return ms === null ? null : isoDeInstante(ms, tz);
};
